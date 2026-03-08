///|
test "single atom query scans table" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  let _ = db.call("Num", [IntVal(2)])
  // Query: Num(?x, ?out)
  let results = execute_query(db, [Fact("Num", [Var("x"), Var("out")])])
  inspect(results.length(), content="2")
}

///|
test "single atom with literal filters" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  let _ = db.call("Num", [IntVal(2)])
  // Query: Num(1, ?out) — should match only one row
  let results = execute_query(db, [Fact("Num", [Lit(IntVal(1)), Var("out")])])
  inspect(results.length(), content="1")
}

///|
test "two atom join with shared variable" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  // Query: Num(1, ?x), Add(?x, ?y, ?out)
  let results = execute_query(db, [
    Fact("Num", [Lit(IntVal(1)), Var("x")]),
    Fact("Add", [Var("x"), Var("y"), Var("out")]),
  ])
  inspect(results.length(), content="1")
}

///|
test "equal constraint filters" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  let _ = db.call("Num", [IntVal(2)])
  // Query: Num(?x, ?out) where ?x = IntVal(1)
  let results = execute_query(db, [
    Fact("Num", [Var("x"), Var("out")]),
    Equal(Var("x"), Lit(IntVal(1))),
  ])
  inspect(results.length(), content="1")
}

///|
test "empty result when no match" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  // Query: Num(99, ?out) — no such row
  let results = execute_query(db, [Fact("Num", [Lit(IntVal(99)), Var("out")])])
  inspect(results.length(), content="0")
}
