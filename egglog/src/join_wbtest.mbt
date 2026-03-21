///|
/// Query tests show how substitutions are produced and filtered.
test "single atom query scans table" {
  let db = Database::new()
  db.register("Num")
  let _ = db.call("Num", [IntVal(1)])
  let _ = db.call("Num", [IntVal(2)])
  // One fact atom scans the whole table and binds both columns.
  let results = execute_query(db, [Fact("Num", [Var("x"), Var("out")])])
  inspect(results.length(), content="2")
}

///|
test "single atom with literal filters" {
  let db = Database::new()
  db.register("Num")
  let _ = db.call("Num", [IntVal(1)])
  let _ = db.call("Num", [IntVal(2)])
  // Literal terms act like selection predicates.
  let results = execute_query(db, [Fact("Num", [Lit(IntVal(1)), Var("out")])])
  inspect(results.length(), content="1")
}

///|
test "two atom join with shared variable" {
  let db = Database::new()
  db.register("Num")
  db.register("Add")
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  // Shared variables turn two scans into a join.
  let results = execute_query(db, [
    Fact("Num", [Lit(IntVal(1)), Var("x")]),
    Fact("Add", [Var("x"), Var("y"), Var("out")]),
  ])
  inspect(results.length(), content="1")
}

///|
test "equal constraint filters" {
  let db = Database::new()
  db.register("Num")
  let _ = db.call("Num", [IntVal(1)])
  let _ = db.call("Num", [IntVal(2)])
  // Equality atoms behave like a post-join filter.
  let results = execute_query(db, [
    Fact("Num", [Var("x"), Var("out")]),
    Equal(Var("x"), Lit(IntVal(1))),
  ])
  inspect(results.length(), content="1")
}

///|
test "empty result when no match" {
  let db = Database::new()
  db.register("Num")
  let _ = db.call("Num", [IntVal(1)])
  // No matching row means the whole query result is empty.
  let results = execute_query(db, [Fact("Num", [Lit(IntVal(99)), Var("out")])])
  inspect(results.length(), content="0")
}

///|
test "nested call pattern learns variables from matched row" {
  let db = Database::new()
  db.register("Num")
  db.register("Add")
  let lhs = db.call("Num", [IntVal(1)])
  let rhs = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [lhs, rhs])
  let results = execute_query(db, [
    Fact("Add", [
      Call("Num", [Var("lhs")]),
      Call("Num", [Var("rhs")]),
      Var("out"),
    ]),
  ])
  inspect(results.length(), content="1")
  match results {
    [result] => {
      inspect(result.get("lhs").unwrap(), content="IntVal(1)")
      inspect(result.get("rhs").unwrap(), content="IntVal(2)")
      inspect(result.get("out").unwrap() is IdVal(_), content="true")
    }
    _ => abort("expected exactly one result")
  }
}
