///|
/// A term in the egglog language.
pub(all) enum Term {
  Var(String)
  Lit(Value)
  Call(String, Array[Term])
} derive(Eq, Show, Debug)

///|
/// An atom in a query pattern.
pub(all) enum Atom {
  Fact(String, Array[Term])
  Equal(Term, Term)
} derive(Show, Debug)

///|
/// An action to execute when a rule fires.
pub(all) enum Action {
  Union(Term, Term)
  Set(String, Array[Term], Term)
  LetAction(String, Term)
} derive(Show, Debug)

///|
/// A rule: query atoms + actions.
pub(all) struct Rule {
  name : String
  query : Array[Atom]
  actions : Array[Action]
} derive(Show, Debug)

///|
/// Evaluate a term under a substitution.
fn eval_term(db : Database, subst : Map[String, Value], term : Term) -> Value {
  match term {
    Var(name) =>
      match subst.get(name) {
        Some(v) => v
        None => abort("unbound variable: " + name)
      }
    Lit(v) => v
    Call(name, args) => {
      let evaluated : Array[Value] = args.map(fn(t) { eval_term(db, subst, t) })
      db.call(name, evaluated)
    }
  }
}

///|
/// Execute actions under a substitution. Returns the number of new unions.
fn execute_actions(
  db : Database,
  subst : Map[String, Value],
  actions : Array[Action],
) -> Int {
  let mut unions = 0
  for action in actions {
    match action {
      Union(lhs, rhs) => {
        let lval = eval_term(db, subst, lhs)
        let rval = eval_term(db, subst, rhs)
        match (lval, rval) {
          (IdVal(a), IdVal(b)) => {
            let ra = db.find(a)
            let rb = db.find(b)
            if ra != rb {
              let _ = db.union(a, b)
              unions = unions + 1
            }
          }
          _ => ()
        }
      }
      Set(name, args, val) => {
        let evaluated_args : Array[Value] = args.map(fn(t) {
          eval_term(db, subst, t)
        })
        let evaluated_val = eval_term(db, subst, val)
        let _ = db.set(name, evaluated_args, evaluated_val)
      }
      LetAction(name, term) => {
        let val = eval_term(db, subst, term)
        subst[name] = val
      }
    }
  }
  unions
}

///|
/// Sugar for creating a rewrite rule: lhs => rhs for a given function.
fn rewrite(
  name : String,
  func_name : String,
  args : Array[Term],
  rhs : Term,
) -> Rule {
  // Build variable names for pattern matching
  let query_terms : Array[Term] = []
  let output_var = "__out"
  for a in args {
    query_terms.push(a)
  }
  query_terms.push(Var(output_var))
  {
    name,
    query: [Fact(func_name, query_terms)],
    actions: [Union(Var(output_var), rhs)],
  }
}
