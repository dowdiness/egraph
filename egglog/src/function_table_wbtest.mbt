///|
/// These tests isolate table storage rules from the rest of the e-graph.
test "insert and lookup row" {
  let ft = FunctionTable::new(None)
  let key : Array[Value] = [IdVal(Id(0)), IdVal(Id(1))]
  let _ = ft.insert(key, IdVal(Id(2)))
  inspect(ft.lookup(key), content="Some(IdVal(2))")
}

///|
test "lookup missing row returns None" {
  let ft = FunctionTable::new(None)
  let key : Array[Value] = [IdVal(Id(0)), IdVal(Id(1))]
  inspect(ft.lookup(key), content="None")
}

///|
test "insert duplicate key without merge keeps old" {
  let ft = FunctionTable::new(None)
  let key : Array[Value] = [IdVal(Id(0)), IdVal(Id(1))]
  let _ = ft.insert(key, IdVal(Id(2)))
  let result = ft.insert(key, IdVal(Id(3)))
  inspect(result, content="(IdVal(2), false)")
}

///|
test "insert duplicate key with merge resolves" {
  let merge : (Value, Value) -> Value = fn(a, b) {
    match (a, b) {
      (IdVal(Id(x)), IdVal(Id(y))) => IdVal(Id(if x < y { x } else { y }))
      _ => a
    }
  }
  let ft = FunctionTable::new(Some(merge))
  let key : Array[Value] = [IdVal(Id(0))]
  let _ = ft.insert(key, IdVal(Id(5)))
  let _ = ft.insert(key, IdVal(Id(3)))
  inspect(ft.lookup(key), content="Some(IdVal(3))")
}

///|
test "row count" {
  let ft = FunctionTable::new(None)
  let _ = ft.insert([IdVal(Id(0))], IdVal(Id(1)))
  let _ = ft.insert([IdVal(Id(2))], IdVal(Id(3)))
  inspect(ft.row_count(), content="2")
}

///|
test "scan all rows" {
  let ft = FunctionTable::new(None)
  let _ = ft.insert([IntVal(1)], IdVal(Id(0)))
  let _ = ft.insert([IntVal(2)], IdVal(Id(1)))
  let rows = ft.scan()
  inspect(rows.length(), content="2")
}
