///|
/// Schedule tests document the control flow around rule application.
test "run applies rules once" {
  let db = Database::new()
  db.register("Num")
  db.register("Add")
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  db.rebuild()
  // One pass of a commutativity rule should intern the swapped node.
  let comm : Rule = {
    name: "comm-add",
    query: [Fact("Add", [Var("a"), Var("b"), Var("out")])],
    actions: [Union(Var("out"), Call("Add", [Var("b"), Var("a")]))],
  }
  let reason = db.run_schedule(Run([comm]))
  inspect(reason, content="Saturated")
  // The new row is visible after the rebuild that happens inside `Run`.
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

///|
test "saturate flushes pending unions before first pass" {
  let db = Database::new()
  db.register("Num")
  db.register("HasType")
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  // Queue a union but don't rebuild yet.
  match (n1, n2) {
    (IdVal(a), IdVal(b)) => db.union(a, b)
    _ => abort("expected IdVal")
  }
  // The rule reads HasType — if pending unions aren't flushed, the Saturate
  // loop could declare saturation without the union taking effect.
  let _ = db.set("HasType", [n1], IntVal(99))
  let rule : Rule = {
    name: "propagate",
    query: [Fact("HasType", [Var("e"), Var("t")])],
    actions: [],
  }
  let _ = db.run_schedule(Saturate(Run([rule]), 10))
  // After saturation, n1 and n2 should be in the same e-class.
  inspect(db.find(Id(0)) == db.find(Id(1)), content="true")
}

///|
/// A merge that keeps the old value should not force another saturation round.
fn max_int_value(old : Value, new : Value) -> Value {
  match (old, new) {
    (IntVal(lhs), IntVal(rhs)) => IntVal(if lhs >= rhs { lhs } else { rhs })
    _ => old
  }
}

///|
test "saturate stops when merge keeps existing row" {
  let db = Database::new()
  let merge : ((Value, Value) -> Value)? = Some(max_int_value)
  db.register("Trigger")
  db.register("Score", merge~)
  let _ = db.set("Trigger", [], IntVal(0))
  let _ = db.set("Score", [], IntVal(5))
  let stable_merge : Rule = {
    name: "stable-merge",
    query: [Fact("Trigger", [Var("flag")])],
    actions: [Set("Score", [], Lit(IntVal(3)))],
  }
  let reason = db.run_schedule(Saturate(Run([stable_merge]), 5))
  inspect(reason, content="Saturated")
  inspect(db.lookup("Score", []).unwrap(), content="IntVal(5)")
}
