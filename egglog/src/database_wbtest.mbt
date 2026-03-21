///|
/// White-box tests for the database layer.
///
/// These tests double as executable examples for interning, congruence
/// closure, and the partial-function semantics of `set`.
test "fresh id allocation" {
  let db = Database::new()
  let a = db.alloc_id()
  let b = db.alloc_id()
  inspect(a, content="0")
  inspect(b, content="1")
}

///|
test "register and call function" {
  let db = Database::new()
  db.register("Num")
  let id = db.call("Num", [IntVal(42)])
  inspect(id is IdVal(_), content="true")
}

///|
test "call same args returns same id" {
  let db = Database::new()
  db.register("Num")
  let id1 = db.call("Num", [IntVal(42)])
  let id2 = db.call("Num", [IntVal(42)])
  inspect(id1 == id2, content="true")
}

///|
test "call different args returns different ids" {
  let db = Database::new()
  db.register("Num")
  let id1 = db.call("Num", [IntVal(1)])
  let id2 = db.call("Num", [IntVal(2)])
  inspect(id1 == id2, content="false")
}

///|
test "union and find" {
  let db = Database::new()
  db.register("Num")
  let v1 = db.call("Num", [IntVal(1)])
  let v2 = db.call("Num", [IntVal(2)])
  match (v1, v2) {
    (IdVal(id1), IdVal(id2)) => {
      db.union(id1, id2)
      db.rebuild()
      inspect(db.find(id1) == db.find(id2), content="true")
    }
    _ => abort("expected IdVal")
  }
}

///|
test "congruence closure" {
  let db = Database::new()
  db.register("Num")
  db.register("Add")
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let add1 = db.call("Add", [n1, n2])
  let n1b = db.call("Num", [IntVal(10)])
  let add2 = db.call("Add", [n1b, n2])
  match (n1, n1b) {
    (IdVal(id1), IdVal(id1b)) => {
      db.union(id1, id1b)
      db.rebuild()
      match (add1, add2) {
        (IdVal(a1), IdVal(a2)) =>
          inspect(db.find(a1) == db.find(a2), content="true")
        _ => abort("expected IdVal")
      }
    }
    _ => abort("expected IdVal")
  }
}

///|
/// Conflicting primitive facts are illegal for non-merged tables.
test "panic conflicting primitive set without merge aborts" {
  let db = Database::new()
  db.register("Score")
  let _ = db.set("Score", [IntVal(1)], IntVal(10))
  ignore(db.set("Score", [IntVal(1)], IntVal(20)))
}

///|
/// A conflict may be discovered only after two input e-classes become equal.
test "panic rebuild rejects conflicting primitive outputs after union" {
  let db = Database::new()
  db.register("Num")
  db.register("Color")
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.set("Color", [n1], StrVal("red"))
  let _ = db.set("Color", [n2], StrVal("blue"))
  match (n1, n2) {
    (IdVal(id1), IdVal(id2)) => {
      db.union(id1, id2)
      db.rebuild()
    }
    _ => abort("expected IdVal")
  }
}
