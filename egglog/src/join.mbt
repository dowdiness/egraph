///|
/// Evaluate a term under substitution. Returns None for unbound variables.
fn eval_term_opt(
  db : Database,
  subst : Map[String, Value],
  term : Term,
) -> Value? {
  match term {
    Var(name) => subst.get(name)
    Lit(v) => Some(v)
    Call(name, args) => {
      let evaluated : Array[Value] = []
      for a in args {
        match eval_term_opt(db, subst, a) {
          Some(v) => evaluated.push(v)
          None => return None
        }
      }
      Some(db.call(name, evaluated))
    }
  }
}

///|
/// Try to match terms against a row of values, extending the substitution.
fn unify_row(
  db : Database,
  subst : Map[String, Value],
  terms : Array[Term],
  row : Array[Value],
) -> Map[String, Value]? {
  if terms.length() != row.length() {
    return None
  }
  let new_subst : Map[String, Value] = {}
  subst.each(fn(k, v) { new_subst[k] = v })
  for i, term in terms {
    let val = db.canonicalize_value(row[i])
    match term {
      Var(name) =>
        match new_subst.get(name) {
          Some(existing) => {
            let canon_existing = db.canonicalize_value(existing)
            if canon_existing != val {
              return None
            }
          }
          None => new_subst[name] = val
        }
      Lit(v) => if db.canonicalize_value(v) != val { return None }
      Call(_name, _args) =>
        match eval_term_opt(db, new_subst, term) {
          Some(evaluated) =>
            if db.canonicalize_value(evaluated) != val {
              return None
            }
          None => return None
        }
    }
  }
  Some(new_subst)
}

///|
/// Execute a conjunctive query, returning all matching substitutions.
fn execute_query(
  db : Database,
  query : Array[Atom],
) -> Array[Map[String, Value]] {
  // Separate Fact atoms from Equal atoms
  let facts : Array[(String, Array[Term])] = []
  let equals : Array[(Term, Term)] = []
  for atom in query {
    match atom {
      Fact(name, terms) => facts.push((name, terms))
      Equal(lhs, rhs) => equals.push((lhs, rhs))
    }
  }
  // Start with one empty substitution
  let mut substs : Array[Map[String, Value]] = [{}]
  // For each Fact atom, scan the table and unify
  for fact in facts {
    let (name, terms) = fact
    let table = match db.tables.get(name) {
      Some(t) => t
      None => return []
    }
    let rows = table.scan()
    let new_substs : Array[Map[String, Value]] = []
    for s in substs {
      for row_pair in rows {
        let (key, value) = row_pair
        // Build full row: key columns + output column
        let full_row : Array[Value] = key.copy()
        full_row.push(value)
        match unify_row(db, s, terms, full_row) {
          Some(extended) => new_substs.push(extended)
          None => ()
        }
      }
    }
    substs = new_substs
  }
  // Filter by Equal constraints
  let result : Array[Map[String, Value]] = []
  for s in substs {
    let mut ok = true
    for eq in equals {
      let (lhs, rhs) = eq
      match (eval_term_opt(db, s, lhs), eval_term_opt(db, s, rhs)) {
        (Some(lval), Some(rval)) =>
          if db.canonicalize_value(lval) != db.canonicalize_value(rval) {
            ok = false
          }
        _ => ok = false
      }
    }
    if ok {
      result.push(s)
    }
  }
  result
}
