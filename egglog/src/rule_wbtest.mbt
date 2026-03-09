///|
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
  // Should return an IdVal
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
