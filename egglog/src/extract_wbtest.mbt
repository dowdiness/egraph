///|
test "extract single constant" {
  let db = Database::new()
  db.register("Num", 2, None)
  let v = db.call("Num", [IntVal(42)])
  db.rebuild()
  match v {
    IdVal(id) => {
      let (cost, expr) = db.extract(id, ast_size)
      inspect(cost, content="1")
      inspect(expr, content="(Num IntVal(42))")
    }
    _ => abort("expected IdVal")
  }
}

///|
test "extract picks cheaper after rewrite" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n0 = db.call("Num", [IntVal(0)])
  let n1 = db.call("Num", [IntVal(1)])
  let add = db.call("Add", [n1, n0])
  db.rebuild()
  // Rewrite rule: Add(?x, Num(0)) => ?x
  let zero_rule : Rule = {
    name: "add-zero",
    query: [
      Fact("Num", [Lit(IntVal(0)), Var("z")]),
      Fact("Add", [Var("x"), Var("z"), Var("out")]),
    ],
    actions: [Union(Var("out"), Var("x"))],
  }
  let _ = db.run_schedule(Saturate(Run([zero_rule]), 10))
  match add {
    IdVal(id) => {
      let (cost, expr) = db.extract(id, ast_size)
      // After rewrite, should prefer Num(1) (cost 1) over Add(Num(1), Num(0)) (cost 3)
      inspect(cost, content="1")
      inspect(expr, content="(Num IntVal(1))")
    }
    _ => abort("expected IdVal")
  }
}
