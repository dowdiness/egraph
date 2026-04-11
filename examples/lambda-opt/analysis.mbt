// E-class analysis: free-variable tracking + constant folding + beta reduction.

///|
/// Per-e-class analysis data.
/// `fv`: free variables (intersection on merge — sound for equivalent terms).
/// `val`: known integer constant if this e-class reduces to a literal.
pub(all) struct EvalState {
  fv : @hashset.HashSet[String]
  val : Int?
}

///|
fn fv_union(
  dst : @hashset.HashSet[String],
  src : @hashset.HashSet[String],
) -> Unit {
  for x in src {
    dst.add(x)
  }
}

///|
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
/// Reduce LSubst(x, v_id, e_node) by dispatching on e_node's structure.
fn apply_subst(
  eg : @egraph.AnalyzedEGraph[LambdaLang, EvalState],
  subst_class : @egraph.Id,
  x : String,
  v_id : @egraph.Id,
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
    LApp(f, a) => {
      let sf = eg.add(LSubst(x, v_id, f))
      let sa = eg.add(LSubst(x, v_id, a))
      eg.union(subst_class, eg.add(LApp(sf, sa))) |> ignore
    }
    LIf(c, t, e) => {
      let sc = eg.add(LSubst(x, v_id, c))
      let st = eg.add(LSubst(x, v_id, t))
      let se = eg.add(LSubst(x, v_id, e))
      eg.union(subst_class, eg.add(LIf(sc, st, se))) |> ignore
    }
    LLam(y, body_id) =>
      if x == y {
        eg.union(subst_class, eg.add(LLam(y, body_id))) |> ignore
      } else if !eg.get_data(v_id).fv.contains(y) {
        let new_body = eg.add(LSubst(x, v_id, body_id))
        eg.union(subst_class, eg.add(LLam(y, new_body))) |> ignore
      } else if !eg.get_data(body_id).fv.contains(x) {
        eg.union(subst_class, eg.add(LLam(y, body_id))) |> ignore
      }
    LLet(y, val_id, body_id) =>
      if x == y {
        let new_val = eg.add(LSubst(x, v_id, val_id))
        eg.union(subst_class, eg.add(LLet(y, new_val, body_id))) |> ignore
      } else if !eg.get_data(v_id).fv.contains(y) {
        let new_val = eg.add(LSubst(x, v_id, val_id))
        let new_body = eg.add(LSubst(x, v_id, body_id))
        eg.union(subst_class, eg.add(LLet(y, new_val, new_body))) |> ignore
      } else if !eg.get_data(body_id).fv.contains(x) {
        let new_val = eg.add(LSubst(x, v_id, val_id))
        eg.union(subst_class, eg.add(LLet(y, new_val, body_id))) |> ignore
      }
    LSubst(_, _, _) => () // re-dispatched once inner e-class reduces
  }
}

///|
/// Combined analysis: FV tracking + constant folding + beta reduction.
pub fn eval_analysis() -> @egraph.Analysis[LambdaLang, EvalState] {
  {
    make: fn(node, get_data) {
      let fv : @hashset.HashSet[String] = @hashset.new()
      let mut val : Int? = None
      match node {
        LNum(n) => val = Some(n)
        LVar(x) => fv.add(x)
        LAdd(a, b) => {
          let da = get_data(a)
          let db = get_data(b)
          fv_union(fv, da.fv)
          fv_union(fv, db.fv)
          match (da.val, db.val) {
            (Some(x), Some(y)) => val = Some(x + y)
            _ => ()
          }
        }
        LMinus(a, b) => {
          let da = get_data(a)
          let db = get_data(b)
          fv_union(fv, da.fv)
          fv_union(fv, db.fv)
          match (da.val, db.val) {
            (Some(x), Some(y)) => val = Some(x - y)
            _ => ()
          }
        }
        LIf(c, t, e) => {
          fv_union(fv, get_data(c).fv)
          fv_union(fv, get_data(t).fv)
          fv_union(fv, get_data(e).fv)
          // If condition is a known integer: 0=false, nonzero=true
          match get_data(c).val {
            Some(0) => val = get_data(e).val
            Some(_) => val = get_data(t).val
            None => ()
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
      for x in a.fv {
        if b.fv.contains(x) {
          fv.add(x)
        }
      }
      let val = match (a.val, b.val) {
        (Some(v1), Some(v2)) => if v1 == v2 { Some(v1) } else { None }
        (Some(v), None) | (None, Some(v)) => Some(v)
        _ => None
      }
      let result : EvalState = { fv, val }
      let a_changed = a.fv.length() != fv.length() || a.val != val
      let b_changed = b.fv.length() != fv.length() || b.val != val
      (result, { a_changed, b_changed })
    },
    modify: fn(eg, id) {
      // Constant folding: if we know the value, add the literal node
      match eg.get_data(id).val {
        Some(n) => eg.union(id, eg.add(LNum(n))) |> ignore
        None => ()
      }
      // Beta reduction + substitution dispatch
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
              _ => ()
            }
          }
      }
    },
  }
}
