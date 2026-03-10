///|
/// Extraction tests explain how graph-shaped data turns back into a tree.
test "extract single constant" {
  let db = Database::new()
  db.register("Num")
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
  db.register("Num")
  db.register("Add")
  let n0 = db.call("Num", [IntVal(0)])
  let n1 = db.call("Num", [IntVal(1)])
  let add = db.call("Add", [n1, n0])
  db.rebuild()
  // Canonical algebraic simplification: x + 0 rewrites to x.
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
      // Extraction should now prefer the rewritten leaf over the larger tree.
      inspect(cost, content="1")
      inspect(expr, content="(Num IntVal(1))")
    }
    _ => abort("expected IdVal")
  }
}

///|
test "extract preserves primitive arguments alongside child expressions" {
  let db = Database::new()
  db.register("Var")
  db.register("Lam")
  let var_x = db.call("Var", [StrVal("x")])
  let lam = db.call("Lam", [StrVal("x"), var_x])
  db.rebuild()
  match lam {
    IdVal(id) => {
      let (cost, expr) = db.extract(id, ast_size)
      inspect(cost, content="2")
      inspect(expr, content="(Lam StrVal(\"x\") (Var StrVal(\"x\")))")
    }
    _ => abort("expected IdVal")
  }
}

///|
test "extract preserves multiple primitive arguments" {
  let db = Database::new()
  db.register("Pair")
  let pair = db.call("Pair", [StrVal("left"), StrVal("right")])
  db.rebuild()
  match pair {
    IdVal(id) => {
      let (cost, expr) = db.extract(id, ast_size)
      inspect(cost, content="1")
      inspect(expr, content="(Pair StrVal(\"left\") StrVal(\"right\"))")
    }
    _ => abort("expected IdVal")
  }
}
