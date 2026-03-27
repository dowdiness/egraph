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
/// Combined analysis: free-variable tracking + constant folding.
///
/// `make` computes EvalState bottom-up from child data.
/// `merge` unions FV sets and preserves agreeing constant values.
/// `modify` is a no-op placeholder until Task 4.
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
          fv_union(fv, get_data(body).fv)
          fv.remove(x)
        }
        LLet(x, v, body) => {
          fv_union(fv, get_data(v).fv)
          for y in get_data(body).fv {
            if y != x {
              fv.add(y)
            }
          }
        }
        LSubst(x, v, e) => {
          fv_union(fv, get_data(e).fv)
          fv.remove(x)
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
    modify: fn(_eg, _id) { () },
  }
}

///|
test "eval: make — FV for new variants" {
  let eg = AnalyzedEGraph::new(subst_and_eval_analysis())
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
  let if_expr = eg.add(LIf(btrue, x_id, y_id))
  assert_true(eg.get_data(if_expr).fv.contains("x"))
  assert_true(eg.get_data(if_expr).fv.contains("y"))
  let subst = eg.add(LSubst("x", num5, x_id))
  assert_true(eg.get_data(subst).fv.is_empty())
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
