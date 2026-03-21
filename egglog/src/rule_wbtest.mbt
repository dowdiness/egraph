///|
/// Rule tests focus on the little language used by schedules.
test "eval_term Lit returns value" {
  let db = Database::new()
  let subst : Map[String, Value] = {}
  let result = eval_term(db, subst, Lit(IntVal(42)))
  inspect(result, content="IntVal(42)")
}

///|
test "eval_term Var looks up substitution" {
  let db = Database::new()
  let subst : Map[String, Value] = { "x": IntVal(7) }
  let result = eval_term(db, subst, Var("x"))
  inspect(result, content="IntVal(7)")
}

///|
test "eval_term Call creates node in database" {
  let db = Database::new()
  db.register("Num")
  let subst : Map[String, Value] = {}
  let result = eval_term(db, subst, Call("Num", [Lit(IntVal(42))]))
  // Action-time calls intern missing rows, so the result is an e-class id.
  match result {
    IdVal(_) => inspect(true, content="true")
    _ => inspect(false, content="true")
  }
}

///|
test "rewrite sugar creates correct rule" {
  let rule = rewrite(
    "commute-add",
    "Add",
    [Var("a"), Var("b")],
    Call("Add", [Var("b"), Var("a")]),
  )
  inspect(rule.name, content="commute-add")
  inspect(rule.query.length(), content="1")
  inspect(rule.actions.length(), content="1")
}

///|
test "rewrite avoids capturing __out variable" {
  // If args or rhs use "__out", the synthetic variable must pick a fresh name.
  let rule = rewrite("test", "F", [Var("__out")], Var("__out"))
  // The query should have 2 terms: the user's __out and a fresh synthetic var.
  match rule.query[0] {
    Fact(_, terms) =>
      // Last term is the synthetic output variable.
      match terms[terms.length() - 1] {
        Var(name) => inspect(name != "__out", content="true")
        _ => inspect(false, content="true")
      }
    _ => inspect(false, content="true")
  }
}
