///|
/// Executable walkthrough of the STLC example rules.
test "num synthesizes IntTy" {
  let db = stlc_db()
  let num_e = db.call("Num", [@egglog.IntVal(42)])
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(stlc_rules()), 20))
  let int_ty = db.call("IntTy", [])
  let has_type = db.lookup("HasType", [num_e])
  inspect(same_class(db, has_type.unwrap(), int_ty), content="true")
}

///|
test "var with env synthesizes type" {
  let db = stlc_db()
  let var_e = db.call("Var", [@egglog.StrVal("x")])
  let int_ty = db.call("IntTy", [])
  // Seed the environment, then let the typing rule derive the variable type.
  let _ = db.set("InEnv", [@egglog.StrVal("x")], int_ty)
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(stlc_rules()), 20))
  let has_type = db.lookup("HasType", [var_e])
  inspect(same_class(db, has_type.unwrap(), int_ty), content="true")
}

///|
test "add synthesizes IntTy" {
  let db = stlc_db()
  let n1 = db.call("Num", [@egglog.IntVal(1)])
  let n2 = db.call("Num", [@egglog.IntVal(2)])
  let add_e = db.call("Add", [n1, n2])
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(stlc_rules()), 20))
  let int_ty = db.call("IntTy", [])
  let has_type = db.lookup("HasType", [add_e])
  inspect(same_class(db, has_type.unwrap(), int_ty), content="true")
}

///|
test "lambda checking: top-down type flow" {
  let db = stlc_db()
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let num_1 = db.call("Num", [@egglog.IntVal(1)])
  let body = db.call("Add", [var_x, num_1])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), body])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // Bidirectional typing starts from the expected lambda type.
  let _ = db.set("HasType", [lam_e], arr_ty)
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(stlc_rules()), 20))
  let env_type = db.lookup("InEnv", [@egglog.StrVal("x")])
  inspect(same_class(db, env_type.unwrap(), int_ty), content="true")
}

///|
test "app synthesis: both directions cooperate" {
  let db = stlc_db()
  let var_x = db.call("Var", [@egglog.StrVal("x")])
  let lam_e = db.call("Lam", [@egglog.StrVal("x"), var_x])
  let num_42 = db.call("Num", [@egglog.IntVal(42)])
  let app_e = db.call("App", [lam_e, num_42])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // Once the function type is known, application can synthesize its result.
  let _ = db.set("HasType", [lam_e], arr_ty)
  let _ = db.run_schedule(@egglog.Saturate(@egglog.Run(stlc_rules()), 20))
  let has_type = db.lookup("HasType", [app_e])
  inspect(same_class(db, has_type.unwrap(), int_ty), content="true")
}
