///|
/// Helper: unwrap a Value to an Id, aborting if not an IdVal.
fn unwrap_id(v : Value) -> Id {
  match v {
    IdVal(id) => id
    _ => abort("expected IdVal")
  }
}

///|
/// Helper: check if two values refer to the same e-class.
fn same_class(db : Database, a : Value, b : Value) -> Bool {
  db.find(unwrap_id(a)) == db.find(unwrap_id(b))
}

///|
/// Helper: create a database with STLC expression and type constructors.
fn stlc_db() -> Database {
  let db = Database::new()
  // Expression constructors
  db.register("Num") // Num(int_value) -> expr_id
  db.register("Var") // Var(name) -> expr_id
  db.register("Add") // Add(left, right) -> expr_id
  db.register("Lam") // Lam(param, body) -> expr_id
  db.register("App") // App(func, arg) -> expr_id
  // Type constructors
  db.register("IntTy") // IntTy() -> type_id
  db.register("Arrow") // Arrow(domain, codomain) -> type_id
  // Relations (merge = keep newer, unification handled by Database::set pending)
  db.register("HasType")
  db.register("InEnv")
  db
}

///|
/// Helper: create STLC bidirectional typing rules.
fn stlc_rules() -> Array[Rule] {
  [
    // type-num: Num(?n, ?e) => Set HasType(?e) = IntTy()
    {
      name: "type-num",
      query: [Fact("Num", [Var("n"), Var("e")])],
      actions: [Set("HasType", [Var("e")], Call("IntTy", []))],
    },
    // type-var: Var(?x, ?e), InEnv(?x, ?t) => Set HasType(?e) = ?t
    {
      name: "type-var",
      query: [
        Fact("Var", [Var("x"), Var("e")]),
        Fact("InEnv", [Var("x"), Var("t")]),
      ],
      actions: [Set("HasType", [Var("e")], Var("t"))],
    },
    // type-add: Add(?a, ?b, ?e), HasType(?a, ?ta), HasType(?b, ?tb),
    //           IntTy(?ta), IntTy(?tb) => Set HasType(?e) = IntTy()
    {
      name: "type-add",
      query: [
        Fact("Add", [Var("a"), Var("b"), Var("e")]),
        Fact("HasType", [Var("a"), Var("ta")]),
        Fact("HasType", [Var("b"), Var("tb")]),
        Fact("IntTy", [Var("ta")]),
        Fact("IntTy", [Var("tb")]),
      ],
      actions: [Set("HasType", [Var("e")], Call("IntTy", []))],
    },
    // type-app: App(?f, ?a, ?e), HasType(?f, ?tf), HasType(?a, ?ta),
    //           Arrow(?ta, ?tb, ?tf) => Set HasType(?e) = ?tb
    {
      name: "type-app",
      query: [
        Fact("App", [Var("f"), Var("a"), Var("e")]),
        Fact("HasType", [Var("f"), Var("tf")]),
        Fact("HasType", [Var("a"), Var("ta")]),
        Fact("Arrow", [Var("ta"), Var("tb"), Var("tf")]),
      ],
      actions: [Set("HasType", [Var("e")], Var("tb"))],
    },
    // check-lam: Lam(?x, ?body, ?e), HasType(?e, ?t), Arrow(?a, ?b, ?t)
    //            => Set InEnv(?x) = ?a, Set HasType(?body) = ?b
    {
      name: "check-lam",
      query: [
        Fact("Lam", [Var("x"), Var("body"), Var("e")]),
        Fact("HasType", [Var("e"), Var("t")]),
        Fact("Arrow", [Var("a"), Var("b"), Var("t")]),
      ],
      actions: [
        Set("InEnv", [Var("x")], Var("a")),
        Set("HasType", [Var("body")], Var("b")),
      ],
    },
  ]
}

///|
test "num synthesizes IntTy" {
  let db = stlc_db()
  let num_e = db.call("Num", [IntVal(42)])
  let _ = db.run_schedule(Saturate(Run(stlc_rules()), 20))
  let int_ty = db.call("IntTy", [])
  let has_type = db.lookup("HasType", [num_e])
  inspect(same_class(db, has_type.unwrap(), int_ty), content="true")
}

///|
test "var with env synthesizes type" {
  let db = stlc_db()
  let var_e = db.call("Var", [StrVal("x")])
  let int_ty = db.call("IntTy", [])
  let _ = db.set("InEnv", [StrVal("x")], int_ty)
  let _ = db.run_schedule(Saturate(Run(stlc_rules()), 20))
  let has_type = db.lookup("HasType", [var_e])
  inspect(same_class(db, has_type.unwrap(), int_ty), content="true")
}

///|
test "add synthesizes IntTy" {
  let db = stlc_db()
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let add_e = db.call("Add", [n1, n2])
  let _ = db.run_schedule(Saturate(Run(stlc_rules()), 20))
  let int_ty = db.call("IntTy", [])
  let has_type = db.lookup("HasType", [add_e])
  inspect(same_class(db, has_type.unwrap(), int_ty), content="true")
}

///|
test "lambda checking: top-down type flow" {
  let db = stlc_db()
  let var_x = db.call("Var", [StrVal("x")])
  let num_1 = db.call("Num", [IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [StrVal("x"), body])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  let _ = db.set("HasType", [lam_e], arr_ty)
  let _ = db.run_schedule(Saturate(Run(stlc_rules()), 20))
  let env_type = db.lookup("InEnv", [StrVal("x")])
  inspect(same_class(db, env_type.unwrap(), int_ty), content="true")
}

///|
test "app synthesis: both directions cooperate" {
  let db = stlc_db()
  let var_x = db.call("Var", [StrVal("x")])
  let lam_e = db.call("Lam", [StrVal("x"), var_x])
  let num_42 = db.call("Num", [IntVal(42)])
  let app_e = db.call("App", [lam_e, num_42])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  let _ = db.set("HasType", [lam_e], arr_ty)
  let _ = db.run_schedule(Saturate(Run(stlc_rules()), 20))
  let has_type = db.lookup("HasType", [app_e])
  inspect(same_class(db, has_type.unwrap(), int_ty), content="true")
}
