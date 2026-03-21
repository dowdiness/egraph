///|
/// Surface syntax for the rule language.
///
/// Terms build expressions, atoms describe query patterns, and actions describe
/// side effects once a match has been found.
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
/// Action-time term evaluation.
///
/// In actions, `Call` is effectful: it interns any missing application through
/// `db.call`. That is the crucial difference from query evaluation.
/// Aborts on unbound variables. Used for action execution (not queries).
fn eval_term(db : Database, subst : Map[String, Value], term : Term) -> Value {
  match term {
    Var(name) =>
      match subst.get(name) {
        Some(v) => v
        None => abort("unbound variable in term")
      }
    Lit(v) => v
    Call(name, args) => {
      let evaluated = args.map(fn(a) { eval_term(db, subst, a) })
      db.call(name, evaluated)
    }
  }
}

///|
/// Execute a rule body once a query match has produced bindings.
///
/// `Union` grows the pending equality set, `Set` writes functional facts, and
/// `LetAction` gives later actions a local name for an intermediate value.
/// Returns the number of new unions.
fn execute_actions(
  db : Database,
  subst : Map[String, Value],
  actions : Array[Action],
) -> Int {
  let mut unions = 0
  // Copy the match so local lets remain scoped to this one rule firing.
  let bindings : Map[String, Value] = {}
  subst.each(fn(k, v) { bindings[k] = v })
  for action in actions {
    match action {
      Union(lhs, rhs) => {
        let lval = eval_term(db, bindings, lhs)
        let rval = eval_term(db, bindings, rhs)
        match (lval, rval) {
          (IdVal(a), IdVal(b)) => {
            let ra = db.find(a)
            let rb = db.find(b)
            if ra != rb {
              db.union(a, b)
              unions = unions + 1
            }
          }
          _ => ()
        }
      }
      Set(name, args, val) => {
        let evaluated_args : Array[Value] = args.map(fn(t) {
          eval_term(db, bindings, t)
        })
        let evaluated_val = eval_term(db, bindings, val)
        let _ = db.set(name, evaluated_args, evaluated_val)
      }
      LetAction(name, term) => {
        let val = eval_term(db, bindings, term)
        bindings[name] = val
      }
    }
  }
  unions
}

///|
/// Collect all variable names used in a term.
fn collect_vars(term : Term, names : Map[String, Unit]) -> Unit {
  match term {
    Var(n) => names[n] = ()
    Lit(_) => ()
    Call(_, ts) =>
      for t in ts {
        collect_vars(t, names)
      }
  }
}

///|
/// Sugar for the common "match one function row, then union its output with a
/// replacement term" pattern.
#warnings("-unused_value")
fn rewrite(
  name : String,
  func_name : String,
  args : Array[Term],
  rhs : Term,
) -> Rule {
  // Collect all variable names in args and rhs to avoid capture.
  let used : Map[String, Unit] = {}
  for a in args {
    collect_vars(a, used)
  }
  collect_vars(rhs, used)
  let mut output_var = "__out"
  let mut i = 0
  while used.contains(output_var) {
    output_var = "__out" + i.to_string()
    i = i + 1
  }
  // Query the function row and bind its output to the fresh variable.
  let query_terms : Array[Term] = []
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
