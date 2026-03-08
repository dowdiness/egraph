///|
test "run applies rules once" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  db.rebuild()
  // Rule: Add(?a, ?b, ?out) => Add(?b, ?a, ?out) (commutativity)
  let comm : Rule = {
    name: "comm-add",
    query: [Fact("Add", [Var("a"), Var("b"), Var("out")])],
    actions: [Union(Var("out"), Call("Add", [Var("b"), Var("a")]))],
  }
  let reason = db.run_schedule(Run([comm]))
  inspect(reason, content="Saturated")
  // After rule, Add(n2, n1) should exist
  let result = db.lookup("Add", [n2, n1])
  inspect(result is Some(_), content="true")
}

///|
test "saturate reaches fixed point" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  db.rebuild()
  let comm : Rule = {
    name: "comm-add",
    query: [Fact("Add", [Var("a"), Var("b"), Var("out")])],
    actions: [Union(Var("out"), Call("Add", [Var("b"), Var("a")]))],
  }
  let reason = db.run_schedule(Saturate(Run([comm]), 100))
  inspect(reason, content="Saturated")
}

///|
test "repeat respects limit" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  db.rebuild()
  // A trivial rule that does nothing
  let noop : Rule = {
    name: "noop",
    query: [Fact("Num", [Lit(IntVal(999)), Var("out")])],
    actions: [],
  }
  let reason = db.run_schedule(Repeat(3, Run([noop])))
  inspect(reason, content="Saturated")
}

///|
test "seq composes schedules" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  db.rebuild()
  let comm : Rule = {
    name: "comm-add",
    query: [Fact("Add", [Var("a"), Var("b"), Var("out")])],
    actions: [Union(Var("out"), Call("Add", [Var("b"), Var("a")]))],
  }
  let reason = db.run_schedule(Seq([Run([comm]), Run([comm])]))
  inspect(reason, content="Saturated")
}
