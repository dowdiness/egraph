///|
/// Values the constant-folding lattice can represent.
enum ValLit {
  VInt(Int)
  VBool(Bool)
} derive(Eq, Show)

///|
/// Combined analysis data per e-class.
///
/// `fv`: free variables (sound over-approximation — set-union on merge).
/// `val`: known constant value if this e-class reduces to a literal.
struct EvalState {
  fv : @hashset.HashSet[String]
  val : ValLit?
}

///|
/// Copy all elements of `src` into `dst`.
fn fv_union(
  dst : @hashset.HashSet[String],
  src : @hashset.HashSet[String],
) -> Unit {
  for x in src {
    dst.add(x)
  }
}

///|
/// Union two e-classes and overwrite the winner's analysis data with `exact`.
fn union_with_exact_data(
  eg : AnalyzedEGraph[LambdaLang, EvalState],
  a : Id,
  b : Id,
  exact : EvalState,
) -> Unit {
  let winner = eg.union(a, b)
  eg.data[eg.find(winner)] = exact
}

///|
/// Reduce `LSubst(x, v_id, e_node)` by dispatching on the structure of `e_node`.
/// Unions `subst_class` with the reduced form when a rule applies.
fn apply_subst(
  eg : AnalyzedEGraph[LambdaLang, EvalState],
  subst_class : Id,
  x : String,
  v_id : Id,
  e_node : LambdaLang,
) -> Unit {
  match e_node {
    LVar(y) =>
      if x == y {
        union_with_exact_data(eg, subst_class, v_id, eg.get_data(v_id))
      } else {
        let y_id = eg.add(LVar(y))
        union_with_exact_data(eg, subst_class, y_id, eg.get_data(y_id))
      }
    LNum(n) => {
      let num_id = eg.add(LNum(n))
      union_with_exact_data(eg, subst_class, num_id, eg.get_data(num_id))
    }
    LBool(b) => {
      let bool_id = eg.add(LBool(b))
      union_with_exact_data(eg, subst_class, bool_id, eg.get_data(bool_id))
    }
    LAdd(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      let add_id = eg.add(LAdd(sa, sb))
      union_with_exact_data(eg, subst_class, add_id, eg.get_data(add_id))
    }
    LMinus(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      let minus_id = eg.add(LMinus(sa, sb))
      union_with_exact_data(eg, subst_class, minus_id, eg.get_data(minus_id))
    }
    LMul(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      let mul_id = eg.add(LMul(sa, sb))
      union_with_exact_data(eg, subst_class, mul_id, eg.get_data(mul_id))
    }
    LApp(f, a) => {
      let sf = eg.add(LSubst(x, v_id, f))
      let sa = eg.add(LSubst(x, v_id, a))
      let app_id = eg.add(LApp(sf, sa))
      union_with_exact_data(eg, subst_class, app_id, eg.get_data(app_id))
    }
    LIsZero(inner) => {
      let subst_inner = eg.add(LSubst(x, v_id, inner))
      let iszero_id = eg.add(LIsZero(subst_inner))
      union_with_exact_data(eg, subst_class, iszero_id, eg.get_data(iszero_id))
    }
    LIf(c, t, fb) => {
      let sc = eg.add(LSubst(x, v_id, c))
      let st = eg.add(LSubst(x, v_id, t))
      let sf = eg.add(LSubst(x, v_id, fb))
      let if_id = eg.add(LIf(sc, st, sf))
      union_with_exact_data(eg, subst_class, if_id, eg.get_data(if_id))
    }
    _ => ()
  }
}

///|
/// Combined analysis: free-variable tracking + constant folding.
///
/// `make` computes EvalState bottom-up from child data.
/// `merge` unions FV sets and preserves agreeing constant values.
fn subst_and_eval_analysis() -> Analysis[LambdaLang, EvalState] {
  {
    make: fn(node, get_data) {
      let fv : @hashset.HashSet[String] = @hashset.new()
      let mut val : ValLit? = None
      match node {
        LNum(n) => val = Some(VInt(n))
        LBool(b) => val = Some(VBool(b))
        LVar(x) => fv.add(x)
        LAdd(a, b) => {
          let da = get_data(a)
          let db = get_data(b)
          fv_union(fv, da.fv)
          fv_union(fv, db.fv)
          match (da.val, db.val) {
            (Some(VInt(x)), Some(VInt(y))) => val = Some(VInt(x + y))
            _ => ()
          }
        }
        LMinus(a, b) => {
          let da = get_data(a)
          let db = get_data(b)
          fv_union(fv, da.fv)
          fv_union(fv, db.fv)
          match (da.val, db.val) {
            (Some(VInt(x)), Some(VInt(y))) => val = Some(VInt(x - y))
            _ => ()
          }
        }
        LMul(a, b) => {
          let da = get_data(a)
          let db = get_data(b)
          fv_union(fv, da.fv)
          fv_union(fv, db.fv)
          match (da.val, db.val) {
            (Some(VInt(x)), Some(VInt(y))) => val = Some(VInt(x * y))
            _ => ()
          }
        }
        LIsZero(inner) => {
          let d = get_data(inner)
          fv_union(fv, d.fv)
          match d.val {
            Some(VInt(n)) => val = Some(VBool(n == 0))
            _ => ()
          }
        }
        LIf(c, t, fb) => {
          let dc = get_data(c)
          let dt = get_data(t)
          let df = get_data(fb)
          fv_union(fv, dc.fv)
          fv_union(fv, dt.fv)
          fv_union(fv, df.fv)
          match dc.val {
            Some(VBool(true)) => val = dt.val
            Some(VBool(false)) => val = df.val
            _ => ()
          }
        }
        LApp(f, a) => {
          fv_union(fv, get_data(f).fv)
          fv_union(fv, get_data(a).fv)
        }
        LLam(x, body) => {
          for y in get_data(body).fv {
            let name = y.to_string()
            if name != x {
              fv.add(name)
            }
          }
        }
        LLet(x, v, body) => {
          fv_union(fv, get_data(v).fv)
          for y in get_data(body).fv {
            let name = y.to_string()
            if name != x {
              fv.add(name)
            }
          }
        }
        LSubst(x, v, e) => {
          for y in get_data(e).fv {
            let name = y.to_string()
            if name != x {
              fv.add(name)
            }
          }
          fv_union(fv, get_data(v).fv)
        }
      }
      { fv, val }
    },
    merge: fn(a, b) {
      let fv : @hashset.HashSet[String] = @hashset.new()
      for x in a.fv {
        fv.add(x)
      }
      for x in b.fv {
        fv.add(x)
      }
      let val = match (a.val, b.val) {
        (Some(v1), Some(v2)) => if v1 == v2 { Some(v1) } else { None }
        (Some(v), None) | (None, Some(v)) => Some(v)
        _ => None
      }
      { fv, val }
    },
    modify: fn(eg, id) {
      match eg.get_data(id).val {
        Some(VInt(n)) => {
          let num_id = eg.add(LNum(n))
          union_with_exact_data(eg, id, num_id, eg.get_data(num_id))
        }
        Some(VBool(b)) => {
          let bool_id = eg.add(LBool(b))
          union_with_exact_data(eg, id, bool_id, eg.get_data(bool_id))
        }
        None => ()
      }
      let class_id = eg.find(id)
      match eg.egraph.classes.get(class_id) {
        None => ()
        Some(class) => {
          for node in class.nodes {
            match node {
              LApp(lam_id, arg_id) => {
                let lam_canonical = eg.find(lam_id)
                match eg.egraph.classes.get(lam_canonical) {
                  None => ()
                  Some(lam_class) => {
                    for lam_node in lam_class.nodes {
                      match lam_node {
                        LLam(x, body_id) => {
                          let subst_id = eg.add(LSubst(x, arg_id, body_id))
                          union_with_exact_data(
                            eg,
                            class_id,
                            subst_id,
                            eg.get_data(subst_id),
                          )
                        }
                        _ => ()
                      }
                    }
                  }
                }
              }
              LSubst(x, v_id, e_id) => {
                let e_canonical = eg.find(e_id)
                match eg.egraph.classes.get(e_canonical) {
                  None => ()
                  Some(e_class) => {
                    for e_node in e_class.nodes {
                      apply_subst(eg, class_id, x, v_id, e_node)
                    }
                  }
                }
              }
              LLet(x, v_id, body_id) => {
                let subst_id = eg.add(LSubst(x, v_id, body_id))
                union_with_exact_data(eg, class_id, subst_id, eg.get_data(subst_id))
              }
              LIf(cond_id, then_id, else_id) => {
                match eg.get_data(eg.find(cond_id)).val {
                  Some(VBool(true)) =>
                    union_with_exact_data(eg, class_id, then_id, eg.get_data(then_id))
                  Some(VBool(false)) =>
                    union_with_exact_data(eg, class_id, else_id, eg.get_data(else_id))
                  _ => ()
                }
              }
              _ => ()
            }
          }
        }
      }
    },
  }
}

///|
test "eval: make — FV for new variants" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let c_id = eg.add(LVar("c"))
  let x_id = eg.add(LVar("x"))
  let y_id = eg.add(LVar("y"))
  let num5 = eg.add(LNum(5))
  let btrue = eg.add(LBool(true))
  assert_true(eg.get_data(btrue).fv.is_empty())
  let iszero_x = eg.add(LIsZero(x_id))
  assert_true(eg.get_data(iszero_x).fv.contains("x"))
  let minus_xy = eg.add(LMinus(x_id, y_id))
  assert_true(eg.get_data(minus_xy).fv.contains("x"))
  assert_true(eg.get_data(minus_xy).fv.contains("y"))
  let if_expr = eg.add(LIf(c_id, x_id, y_id))
  assert_true(eg.get_data(if_expr).fv.contains("c"))
  assert_true(eg.get_data(if_expr).fv.contains("x"))
  assert_true(eg.get_data(if_expr).fv.contains("y"))
  let subst = eg.add(LSubst("x", num5, y_id))
  assert_true(eg.get_data(subst).fv.contains("y"))
  assert_true(not(eg.get_data(subst).fv.contains("x")))
}

///|
test "eval: make — constant values for new literals" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let btrue = eg.add(LBool(true))
  assert_eq(eg.get_data(btrue).val, Some(VBool(true)))
  let bfalse = eg.add(LBool(false))
  assert_eq(eg.get_data(bfalse).val, Some(VBool(false)))
  let zero = eg.add(LNum(0))
  let iszero_0 = eg.add(LIsZero(zero))
  assert_eq(eg.get_data(iszero_0).val, Some(VBool(true)))
  let one = eg.add(LNum(1))
  let iszero_1 = eg.add(LIsZero(one))
  assert_eq(eg.get_data(iszero_1).val, Some(VBool(false)))
  let five = eg.add(LNum(5))
  let three = eg.add(LNum(3))
  let minus_53 = eg.add(LMinus(five, three))
  assert_eq(eg.get_data(minus_53).val, Some(VInt(2)))
}

///|
test "eval: constant folding — 2 + 3 = 5 after rebuild" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let sum = eg.add(LAdd(two, three))
  eg.rebuild()
  let five = eg.add(LNum(5))
  assert_eq(eg.find(sum), eg.find(five))
}

///|
test "eval: constant folding — 5 - 3 = 2 after rebuild" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let five = eg.add(LNum(5))
  let three = eg.add(LNum(3))
  let diff = eg.add(LMinus(five, three))
  eg.rebuild()
  let two = eg.add(LNum(2))
  assert_eq(eg.find(diff), eg.find(two))
}

///|
test "eval: IsZero(0) folds to LBool(true) after rebuild" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let zero = eg.add(LNum(0))
  let iszero = eg.add(LIsZero(zero))
  eg.rebuild()
  let btrue = eg.add(LBool(true))
  assert_eq(eg.find(iszero), eg.find(btrue))
}

///|
test "eval: if IsZero(0) then 1 else 2 = 1 after rebuild" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let zero = eg.add(LNum(0))
  let iszero = eg.add(LIsZero(zero))
  let one = eg.add(LNum(1))
  let two = eg.add(LNum(2))
  let if_expr = eg.add(LIf(iszero, one, two))
  eg.rebuild()
  assert_eq(eg.find(if_expr), eg.find(one))
}

///|
test "eval: beta reduction — (λx. x + 1) 5 = 6" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x = eg.add(LVar("x"))
  let one = eg.add(LNum(1))
  let body = eg.add(LAdd(x, one))
  let lam = eg.add(LLam("x", body))
  let five = eg.add(LNum(5))
  let app = eg.add(LApp(lam, five))
  eg.rebuild()
  let six = eg.add(LNum(6))
  assert_eq(eg.find(app), eg.find(six))
}
