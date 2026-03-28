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
/// Copy elements of `src` into `dst`, skipping `exclude`.
/// Used for binder scopes: FV(λx. body) = FV(body) \ {x}.
fn fv_add_except(
  dst : @hashset.HashSet[String],
  src : @hashset.HashSet[String],
  exclude : String,
) -> Unit {
  for y in src {
    if y != exclude {
      dst.add(y)
    }
  }
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
        eg.union(subst_class, v_id) |> ignore
      } else {
        eg.union(subst_class, eg.add(LVar(y))) |> ignore
      }
    LNum(n) => eg.union(subst_class, eg.add(LNum(n))) |> ignore
    LBool(b) => eg.union(subst_class, eg.add(LBool(b))) |> ignore
    LAdd(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      eg.union(subst_class, eg.add(LAdd(sa, sb))) |> ignore
    }
    LMinus(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      eg.union(subst_class, eg.add(LMinus(sa, sb))) |> ignore
    }
    LMul(a, b) => {
      let sa = eg.add(LSubst(x, v_id, a))
      let sb = eg.add(LSubst(x, v_id, b))
      eg.union(subst_class, eg.add(LMul(sa, sb))) |> ignore
    }
    LApp(f, a) => {
      let sf = eg.add(LSubst(x, v_id, f))
      let sa = eg.add(LSubst(x, v_id, a))
      eg.union(subst_class, eg.add(LApp(sf, sa))) |> ignore
    }
    LIsZero(inner) =>
      eg.union(subst_class, eg.add(LIsZero(eg.add(LSubst(x, v_id, inner)))))
      |> ignore
    LIf(c, t, fb) => {
      let sc = eg.add(LSubst(x, v_id, c))
      let st = eg.add(LSubst(x, v_id, t))
      let sf = eg.add(LSubst(x, v_id, fb))
      eg.union(subst_class, eg.add(LIf(sc, st, sf))) |> ignore
    }
    LLam(y, body_id) =>
      if x == y {
        // x is shadowed — substitution does not enter the body
        eg.union(subst_class, eg.add(LLam(y, body_id))) |> ignore
      } else if not(eg.get_data(v_id).fv.contains(y)) {
        // Safe: y ∉ FV(v), no capture possible
        let new_body = eg.add(LSubst(x, v_id, body_id))
        eg.union(subst_class, eg.add(LLam(y, new_body))) |> ignore
      }
    // Capture case (y ∈ FV(v)): leave LSubst unreduced
    LLet(y, val_id, body_id) =>
      if x == y {
        // x is shadowed in body — substitute only in the binding value
        let new_val = eg.add(LSubst(x, v_id, val_id))
        eg.union(subst_class, eg.add(LLet(y, new_val, body_id))) |> ignore
      } else if not(eg.get_data(v_id).fv.contains(y)) {
        let new_val = eg.add(LSubst(x, v_id, val_id))
        let new_body = eg.add(LSubst(x, v_id, body_id))
        eg.union(subst_class, eg.add(LLet(y, new_val, new_body))) |> ignore
      }
    // Capture case: leave LSubst unreduced
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
        LLam(x, body) => fv_add_except(fv, get_data(body).fv, x)
        LLet(x, v, body) => {
          fv_union(fv, get_data(v).fv)
          fv_add_except(fv, get_data(body).fv, x)
        }
        LSubst(x, v, e) => {
          fv_add_except(fv, get_data(e).fv, x)
          fv_union(fv, get_data(v).fv)
        }
      }
      { fv, val }
    },
    merge: fn(a, b) {
      let fv : @hashset.HashSet[String] = @hashset.new()
      fv_union(fv, a.fv)
      fv_union(fv, b.fv)
      let val = match (a.val, b.val) {
        (Some(v1), Some(v2)) => if v1 == v2 { Some(v1) } else { None }
        (Some(v), None) | (None, Some(v)) => Some(v)
        _ => None
      }
      { fv, val }
    },
    modify: fn(eg, id) {
      match eg.get_data(id).val {
        Some(VInt(n)) => eg.union(id, eg.add(LNum(n))) |> ignore
        Some(VBool(b)) => eg.union(id, eg.add(LBool(b))) |> ignore
        None => ()
      }
      let class_id = eg.find(id)
      match eg.egraph.classes.get(class_id) {
        None => ()
        Some(class) =>
          for node in class.nodes {
            match node {
              LApp(lam_id, arg_id) => {
                let lam_canonical = eg.find(lam_id)
                match eg.egraph.classes.get(lam_canonical) {
                  None => ()
                  Some(lam_class) =>
                    for lam_node in lam_class.nodes {
                      match lam_node {
                        LLam(x, body_id) =>
                          eg.union(class_id, eg.add(LSubst(x, arg_id, body_id)))
                          |> ignore
                        _ => ()
                      }
                    }
                }
              }
              LSubst(x, v_id, e_id) => {
                let e_canonical = eg.find(e_id)
                match eg.egraph.classes.get(e_canonical) {
                  None => ()
                  Some(e_class) =>
                    for e_node in e_class.nodes {
                      apply_subst(eg, class_id, x, v_id, e_node)
                    }
                }
              }
              LLet(x, v_id, body_id) =>
                eg.union(class_id, eg.add(LSubst(x, v_id, body_id))) |> ignore
              LIf(cond_id, then_id, else_id) =>
                match eg.get_data(eg.find(cond_id)).val {
                  Some(VBool(true)) => eg.union(class_id, then_id) |> ignore
                  Some(VBool(false)) => eg.union(class_id, else_id) |> ignore
                  _ => ()
                }
              _ => ()
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

///|
test "eval: (λx. λy. x + y) 2 3 = 5 (two beta steps)" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x = eg.add(LVar("x"))
  let y = eg.add(LVar("y"))
  let add_xy = eg.add(LAdd(x, y))
  let inner_lam = eg.add(LLam("y", add_xy))
  let outer_lam = eg.add(LLam("x", inner_lam))
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let app1 = eg.add(LApp(outer_lam, two))
  let app2 = eg.add(LApp(app1, three))
  eg.rebuild()
  let five = eg.add(LNum(5))
  assert_eq(eg.find(app2), eg.find(five))
}

///|
test "eval: let x = 2 in x + x = 4" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let two = eg.add(LNum(2))
  let x = eg.add(LVar("x"))
  let body = eg.add(LAdd(x, x))
  let let_expr = eg.add(LLet("x", two, body))
  eg.rebuild()
  let four = eg.add(LNum(4))
  assert_eq(eg.find(let_expr), eg.find(four))
}

///|
test "eval: (λy. λx. y) x leaves unreduced LSubst in extracted term (capture)" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x_free = eg.add(LVar("x"))
  let y_var = eg.add(LVar("y"))
  let inner_lam = eg.add(LLam("x", y_var))
  let outer_lam = eg.add(LLam("y", inner_lam))
  let app = eg.add(LApp(outer_lam, x_free))
  eg.rebuild()
  let (_, expr) = eg.extract(app, ast_size())
  let mut has_subst = false
  for n in expr.nodes {
    match n {
      LSubst(_, _, _) => has_subst = true
      _ => ()
    }
  }
  assert_true(has_subst)
}

///|
test "eval integration: (2 + 3) * (4 - 1) = 15" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let two = eg.add(LNum(2))
  let three = eg.add(LNum(3))
  let four = eg.add(LNum(4))
  let one = eg.add(LNum(1))
  let sum = eg.add(LAdd(two, three))
  let diff = eg.add(LMinus(four, one))
  let prod = eg.add(LMul(sum, diff))
  eg.rebuild()
  let (cost, expr) = eg.extract(prod, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LNum(15))
}

///|
test "eval integration: if IsZero(1) then 1 else 2 = 2" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let one = eg.add(LNum(1))
  let two = eg.add(LNum(2))
  let iszero = eg.add(LIsZero(one))
  let if_expr = eg.add(LIf(iszero, one, two))
  eg.rebuild()
  assert_eq(eg.find(if_expr), eg.find(two))
}

///|
test "eval integration: (λx. x * 0) 42 = 0 (beta + constant fold)" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x = eg.add(LVar("x"))
  let zero = eg.add(LNum(0))
  let body = eg.add(LMul(x, zero))
  let lam = eg.add(LLam("x", body))
  let n42 = eg.add(LNum(42))
  let app = eg.add(LApp(lam, n42))
  eg.rebuild()
  let (cost, expr) = eg.extract(app, ast_size())
  assert_eq(cost, 1)
  assert_eq(expr.root(), LNum(0))
}

///|
test "eval integration: variable has no constant value" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
  let x = eg.add(LVar("x"))
  assert_eq(eg.get_data(x).val, None)
  let three = eg.add(LNum(3))
  let sum = eg.add(LAdd(x, three))
  assert_eq(eg.get_data(sum).val, None)
}
