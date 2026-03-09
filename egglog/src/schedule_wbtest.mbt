///|
test "run applies rules once" {
  let db = Database::new()
  db.register("Num")
  db.register("Add")
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
  db.register("Num")
  db.register("Add")
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
  db.register("Num")
  db.register("Add")
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  db.rebuild()
  let comm : Rule = {
    name: "comm-add",
    query: [Fact("Add", [Var("a"), Var("b"), Var("out")])],
    actions: [Union(Var("out"), Call("Add", [Var("b"), Var("a")]))],
  }
  let reason = db.run_schedule(Repeat(2, Run([comm])))
  inspect(reason, content="Saturated")
  // Verify the rule actually fired during repeat
  inspect(db.lookup("Add", [n2, n1]) is Some(_), content="true")
}

///|
test "seq composes schedules" {
  let db = Database::new()
  db.register("Num")
  db.register("Add")
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
