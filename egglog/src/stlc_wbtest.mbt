///|
/// Helper: create a database with STLC expression and type constructors.
fn stlc_db() -> Database {
  let db = Database::new()
  // Expression constructors
  db.register("Num", 2, None) // Num(int_value) -> expr_id
  db.register("Var", 2, None) // Var(name) -> expr_id
  db.register("Add", 3, None) // Add(left, right) -> expr_id
  db.register("Lam", 3, None) // Lam(param, body) -> expr_id
  db.register("App", 3, None) // App(func, arg) -> expr_id
  // Type constructors
  db.register("IntTy", 1, None) // IntTy() -> type_id
  db.register("Arrow", 3, None) // Arrow(domain, codomain) -> type_id
  // Relations (merge = keep newer, unification handled by Database::set pending)
  db.register("HasType", 2, None)
  db.register("InEnv", 2, None)
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
  // Create Num(42)
  let num_e = db.call("Num", [IntVal(42)])
  db.rebuild()
  // Run typing rules
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 20))
  // Check HasType(num_e) = IntTy()
  let int_ty = db.call("IntTy", [])
  let has_type = db.lookup("HasType", [num_e])
  match has_type {
    Some(ty) =>
      inspect(
        db.find(
          match ty {
            IdVal(id) => id
            _ => abort("expected id")
          },
        ) ==
        db.find(
          match int_ty {
            IdVal(id) => id
            _ => abort("expected id")
          },
        ),
        content="true",
      )
    None => inspect(false, content="true")
  }
}

///|
test "var with env synthesizes type" {
  let db = stlc_db()
  // Create Var("x")
  let var_e = db.call("Var", [StrVal("x")])
  // Set InEnv("x") = IntTy()
  let int_ty = db.call("IntTy", [])
  let _ = db.set("InEnv", [StrVal("x")], int_ty)
  db.rebuild()
  // Run typing rules
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 20))
  // Check HasType(var_e) = IntTy()
  let has_type = db.lookup("HasType", [var_e])
  match has_type {
    Some(IdVal(ty_id)) => {
      let int_id = match int_ty {
        IdVal(id) => id
        _ => abort("expected id")
      }
      inspect(db.find(ty_id) == db.find(int_id), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "add synthesizes IntTy" {
  let db = stlc_db()
  // Create Add(Num(1), Num(2))
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let add_e = db.call("Add", [n1, n2])
  db.rebuild()
  // Run typing rules
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 20))
  // Check HasType(add_e) = IntTy()
  let int_ty = db.call("IntTy", [])
  let has_type = db.lookup("HasType", [add_e])
  match has_type {
    Some(IdVal(ty_id)) => {
      let int_id = match int_ty {
        IdVal(id) => id
        _ => abort("expected id")
      }
      inspect(db.find(ty_id) == db.find(int_id), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "lambda checking: top-down type flow" {
  let db = stlc_db()
  // Create Lam("x", Add(Var("x"), Num(1)))
  let var_x = db.call("Var", [StrVal("x")])
  let num_1 = db.call("Num", [IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [StrVal("x"), body])
  // Seed HasType(lam_e) = Arrow(IntTy, IntTy)
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  let _ = db.set("HasType", [lam_e], arr_ty)
  db.rebuild()
  // Run typing rules
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 20))
  // Check InEnv("x") = IntTy
  let env_type = db.lookup("InEnv", [StrVal("x")])
  match env_type {
    Some(IdVal(ty_id)) => {
      let int_id = match int_ty {
        IdVal(id) => id
        _ => abort("expected id")
      }
      inspect(db.find(ty_id) == db.find(int_id), content="true")
    }
    _ => inspect(false, content="true")
  }
}

///|
test "app synthesis: both directions cooperate" {
  let db = stlc_db()
  // Create App(Lam("x", Var("x")), Num(42))
  let var_x = db.call("Var", [StrVal("x")])
  let lam_body = var_x // identity function body
  let lam_e = db.call("Lam", [StrVal("x"), lam_body])
  let num_42 = db.call("Num", [IntVal(42)])
  let app_e = db.call("App", [lam_e, num_42])
  // Seed lam type as Arrow(IntTy, IntTy)
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  let _ = db.set("HasType", [lam_e], arr_ty)
  db.rebuild()
  // Run typing rules
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 20))
  // Check HasType(app_e) = IntTy
  let has_type = db.lookup("HasType", [app_e])
  match has_type {
    Some(IdVal(ty_id)) => {
      let int_id = match int_ty {
        IdVal(id) => id
        _ => abort("expected id")
      }
      inspect(db.find(ty_id) == db.find(int_id), content="true")
    }
    _ => inspect(false, content="true")
  }
}
