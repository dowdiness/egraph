///|
/// Small STLC example built on top of the egglog package.
///
/// The point of this file is educational: it shows how constructors become
/// tables, how typing judgments become functional facts, and how typing rules
/// become relational rewrites.
/// Helper: unwrap a Value to an Id, aborting if not an IdVal.
fn unwrap_id(v : @egglog.Value) -> @egglog.Id {
  match v {
    @egglog.IdVal(id) => id
    _ => abort("expected IdVal")
  }
}

///|
/// Helper: check if two values refer to the same e-class.
pub fn same_class(
  db : @egglog.Database,
  a : @egglog.Value,
  b : @egglog.Value,
) -> Bool {
  db.find(unwrap_id(a)) == db.find(unwrap_id(b))
}

///|
/// Create a database with STLC expression and type constructors.
pub fn stlc_db() -> @egglog.Database {
  let db = @egglog.Database::new()
  // Expression constructors intern syntax into e-classes.
  db.register("Num") // Num(int_value) -> expr_id
  db.register("Var") // Var(name) -> expr_id
  db.register("Add") // Add(left, right) -> expr_id
  db.register("Lam") // Lam(param, body) -> expr_id
  db.register("App") // App(func, arg) -> expr_id
  // Type constructors are also just function tables.
  db.register("IntTy") // IntTy() -> type_id
  db.register("Arrow") // Arrow(domain, codomain) -> type_id
  // Typing relations are modeled as partial functions on canonical arguments.
  db.register("HasType")
  db.register("InEnv")
  db
}

///|
/// Create STLC bidirectional typing rules.
///
/// Each rule mirrors a familiar typing judgment, but encoded as:
/// - a query over existing rows
/// - a set of actions that write new facts
///
/// **Limitation:** `InEnv` is keyed by variable name globally, so nested
/// lambdas that shadow the same name (e.g. `λx. λx. x`) cannot receive
/// different types for each binding. A production encoding would thread an
/// explicit environment id or use de Bruijn indices.
pub fn stlc_rules() -> Array[@egglog.Rule] {
  [
    // type-num: Num(?n, ?e) => Set HasType(?e) = IntTy()
    {
      name: "type-num",
      query: [@egglog.Fact("Num", [@egglog.Var("n"), @egglog.Var("e")])],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("e")], @egglog.Call("IntTy", [])),
      ],
    },
    // type-var: Var(?x, ?e), InEnv(?x, ?t) => Set HasType(?e) = ?t
    {
      name: "type-var",
      query: [
        @egglog.Fact("Var", [@egglog.Var("x"), @egglog.Var("e")]),
        @egglog.Fact("InEnv", [@egglog.Var("x"), @egglog.Var("t")]),
      ],
      actions: [@egglog.Set("HasType", [@egglog.Var("e")], @egglog.Var("t"))],
    },
    // type-add: Add(?a, ?b, ?e), HasType(?a, ?ta), HasType(?b, ?tb),
    //           IntTy(?ta), IntTy(?tb) => Set HasType(?e) = IntTy()
    {
      name: "type-add",
      query: [
        @egglog.Fact("Add", [
          @egglog.Var("a"),
          @egglog.Var("b"),
          @egglog.Var("e"),
        ]),
        @egglog.Fact("HasType", [@egglog.Var("a"), @egglog.Var("ta")]),
        @egglog.Fact("HasType", [@egglog.Var("b"), @egglog.Var("tb")]),
        @egglog.Fact("IntTy", [@egglog.Var("ta")]),
        @egglog.Fact("IntTy", [@egglog.Var("tb")]),
      ],
      actions: [
        @egglog.Set("HasType", [@egglog.Var("e")], @egglog.Call("IntTy", [])),
      ],
    },
    // type-app: App(?f, ?a, ?e), HasType(?f, ?tf), HasType(?a, ?ta),
    //           Arrow(?ta, ?tb, ?tf) => Set HasType(?e) = ?tb
    {
      name: "type-app",
      query: [
        @egglog.Fact("App", [
          @egglog.Var("f"),
          @egglog.Var("a"),
          @egglog.Var("e"),
        ]),
        @egglog.Fact("HasType", [@egglog.Var("f"), @egglog.Var("tf")]),
        @egglog.Fact("HasType", [@egglog.Var("a"), @egglog.Var("ta")]),
        @egglog.Fact("Arrow", [
          @egglog.Var("ta"),
          @egglog.Var("tb"),
          @egglog.Var("tf"),
        ]),
      ],
      actions: [@egglog.Set("HasType", [@egglog.Var("e")], @egglog.Var("tb"))],
    },
    // check-lam: Lam(?x, ?body, ?e), HasType(?e, ?t), Arrow(?a, ?b, ?t)
    //            => Set InEnv(?x) = ?a, Set HasType(?body) = ?b
    {
      name: "check-lam",
      query: [
        @egglog.Fact("Lam", [
          @egglog.Var("x"),
          @egglog.Var("body"),
          @egglog.Var("e"),
        ]),
        @egglog.Fact("HasType", [@egglog.Var("e"), @egglog.Var("t")]),
        @egglog.Fact("Arrow", [
          @egglog.Var("a"),
          @egglog.Var("b"),
          @egglog.Var("t"),
        ]),
      ],
      actions: [
        @egglog.Set("InEnv", [@egglog.Var("x")], @egglog.Var("a")),
        @egglog.Set("HasType", [@egglog.Var("body")], @egglog.Var("b")),
      ],
    },
  ]
}
