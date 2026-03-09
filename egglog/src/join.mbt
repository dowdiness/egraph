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
      db.lookup(name, evaluated)
    }
  }
}

///|
fn copy_subst(subst : Map[String, Value]) -> Map[String, Value] {
  let copied : Map[String, Value] = {}
  subst.each(fn(k, v) { copied[k] = v })
  copied
}

///|
fn match_term(
  db : Database,
  subst : Map[String, Value],
  term : Term,
  value : Value,
) -> Array[Map[String, Value]] {
  let canon_value = db.canonicalize_value(value)
  match term {
    Var(name) =>
      match subst.get(name) {
        Some(existing) =>
          if db.canonicalize_value(existing) == canon_value {
            [subst]
          } else {
            []
          }
        None => {
          let extended = copy_subst(subst)
          extended[name] = canon_value
          [extended]
        }
      }
    Lit(v) => if db.canonicalize_value(v) == canon_value { [subst] } else { [] }
    Call(name, args) => {
      let table = match db.tables.get(name) {
        Some(t) => t
        None => return []
      }
      let matches : Array[Map[String, Value]] = []
      for row_pair in table.scan() {
        let (key, row_value) = row_pair
        if db.canonicalize_value(row_value) == canon_value {
          for matched in unify_row(db, subst, args, key) {
            matches.push(matched)
          }
        }
      }
      matches
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
) -> Array[Map[String, Value]] {
  if terms.length() != row.length() {
    return []
  }
  let mut current : Array[Map[String, Value]] = [subst]
  for i, term in terms {
    let next : Array[Map[String, Value]] = []
    for candidate in current {
      for matched in match_term(db, candidate, term, row[i]) {
        next.push(matched)
      }
    }
    current = next
    if current.is_empty() {
      return []
    }
  }
  current
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
        for extended in unify_row(db, s, terms, full_row) {
          new_substs.push(extended)
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
