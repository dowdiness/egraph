///|
/// Black-box smoke test showing the public API is sufficient for a tiny use
/// case without white-box helpers.
test "public database api is usable from blackbox tests" {
  let db = Database::new()
  db.register("Num")
  let value = db.call("Num", [IntVal(7)])
  db.rebuild()
  inspect(db.lookup("Num", [IntVal(7)]) is Some(_), content="true")
  inspect(db.run_schedule(Run([])), content="Saturated")
  match value {
    IdVal(id) => {
      let (cost, expr) = db.extract(id, ast_size)
      inspect(cost, content="1")
      inspect(expr, content="(Num IntVal(7))")
    }
    _ => abort("expected IdVal")
  }
}
