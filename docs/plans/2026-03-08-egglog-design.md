# Egglog Design Proposal

**Date:** 2026-03-08
**Status:** Draft
**Module:** `dowdiness/egglog`

## Goal

Build a relational e-graph engine (egglog) as a new MoonBit module. First target: bidirectional type inference for simply-typed lambda calculus (STLC), demonstrating multi-directional information flow that standard egg-style e-graphs cannot support.

## Key Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Primary use case | Bidirectional type inference (STLC) | Exercises egglog's unique strength (top-down + bottom-up flow) |
| Relationship to egraph | Copy UnionFind/Id, no dependency | Architectures diverge; egglog's UF may need proof-producing union later |
| DSL parser | Programmatic MoonBit API only (initially) | Engine first; parser can be added as separate package via loom later |
| Incremental evaluation | Naive (full-rescan) first, incr later | Correctness before optimization; table design supports delta tracking |
| Join algorithm | Binary join with hash index | Sufficient for 2-3 way joins in type inference; upgradeable to WCOJ |
| Type system target | STLC (Int, Arrow) | Simplest system demonstrating bidirectional checking |

## Architecture

```
+-------------------------------------+
|  Lambda Type Inference Example       |  <-- demonstrates the engine
|  (sorts, functions, rules for STLC)  |
+-------------------------------------+
|  Rule Engine                         |  <-- search (binary join),
|  (Schedule, Rule, Action)            |     apply, rebuild loop
+-------------------------------------+
|  Relational E-Graph Core             |  <-- FunctionTable, UnionFind,
|  (Database, Sort, Function, Merge)   |     congruence closure
+-------------------------------------+
```

Three layers, each independently testable. The example layer validates the engine; the engine validates the core.

## Layer 1: Relational E-Graph Core

### Data Model

The e-graph is a **database of function tables**. Each function `f(x, y) -> z` is stored as a table with rows `(x, y, z)`.

```moonbit
struct Database {
  uf: UnionFind
  functions: Map[String, FunctionTable]
  sorts: Map[String, Sort]
  pending: Array[(Id, Id)]      // deferred unions for rebuild
  id_counter: Int
}

struct FunctionTable {
  name: String
  schema: Array[Sort]           // column sorts (inputs + output)
  rows: Map[Array[Value], Value] // (args...) -> result
  index: Map[ColumnKey, Map[Value, Array[Array[Value]]]]  // column index for join
  merge: ((Value, Value) -> Value)?  // lattice merge for conflicts
}
```

### Value and Sort System

```moonbit
enum Value {
  IdVal(Id)        // e-class reference
  IntVal(Int)      // primitive integer
  StrVal(String)   // primitive string
}

enum Sort {
  EqSort(String)        // e-class sort (participates in union-find)
  PrimitiveSort(String) // i64, String, etc. (no merging)
}
```

`EqSort` values are `Id`s managed by the union-find. `PrimitiveSort` values are concrete and immutable.

### Core Operations

**`Database::new_function(name, schema, merge?)`**
Register a function table with its sort schema and optional merge function.

**`Database::call(name, args) -> Value`**
Look up or create a row. If the function has an EqSort output and no existing row, allocate a fresh `Id`. If a row exists with a different output value:
- No merge function: error (conflict)
- Has merge function: call `merge(old, new)`, update row

**`Database::union(a, b) -> Id`**
Assert two e-class ids are equivalent. Adds to `pending` for deferred processing.

**`Database::rebuild()`**
Restore congruence closure:
1. Process all pending unions via union-find
2. Canonicalize all function table keys (remap Ids through find)
3. Detect congruences: rows that become identical after canonicalization
4. Union their output values, add to pending
5. Repeat until `pending` is empty (fixed point)
6. Rebuild column indexes

### Column Index

Each function table maintains per-column indexes for efficient join probing:

```moonbit
// ColumnKey identifies which column(s) are indexed
// index[col][value] = array of rows where column col == value
type ColumnKey (String, Int)  // (function_name, column_index)
```

When executing a join with some variables already bound, we probe the index on the bound column instead of scanning all rows.

## Layer 2: Rule Engine

### Rule Representation

```moonbit
struct Rule {
  name: String
  query: Array[Atom]       // body: conjunctive query (all must match)
  actions: Array[Action]   // head: executed for each match
}

enum Atom {
  Fact(String, Array[Term])    // f(t1, t2, ...) — match a function table row
  Equal(Term, Term)            // t1 = t2 — equality constraint
}

enum Term {
  Var(String)                  // ?x — pattern variable (binds to Value)
  Lit(Value)                   // concrete value
  Call(String, Array[Term])    // f(t1, ...) — nested function call
}

enum Action {
  Union(Term, Term)                     // merge two e-classes
  Set(String, Array[Term], Term)        // insert/update function row
  LetAction(String, Term)               // bind local variable for subsequent actions
}
```

### Rewrite Sugar

```moonbit
fn rewrite(name: String, lhs: Atom, rhs: Term) -> Rule
// rewrite("add-zero", Fact("Add", [Var("?a"), Call("Num", [Lit(0)])]), Var("?a"))
// desugars to:
// Rule {
//   name: "add-zero",
//   query: [Fact("Add", [Var("?a"), Call("Num", [Lit(IntVal(0))])])],
//   actions: [Union(Fact-output, Var("?a"))]
// }
```

### Query Execution (Binary Join)

For a rule with atoms `[A1, A2, A3]`:

1. **Seed selection**: Pick the atom whose function table has the fewest rows
2. **Scan seed**: For each row in the seed table, create initial `Subst` binding variables
3. **Probe remaining atoms** (one at a time):
   - For bound variables: use column index to look up matching rows (O(1))
   - For unbound variables: bind them from the matched row
   - For literals: filter rows that don't match
4. **Check Equal constraints**: Verify all equality atoms hold under current substitution
5. **Flatten nested Calls**: Before matching, desugar `Call(f, args)` in patterns into auxiliary `Fact` atoms with fresh variables
6. Output `Array[Subst]` of all complete bindings

### Rule Application

For each `Subst` from query execution:
1. Evaluate `Action`s left-to-right
2. `Union(t1, t2)`: resolve both terms under subst, call `Database::union`
3. `Set(f, args, val)`: resolve all terms, call `Database::call` to insert/update
4. `LetAction(x, t)`: resolve term, add binding to subst for subsequent actions

Return count of new unions performed.

### Schedule System

```moonbit
enum Schedule {
  Run(Array[Rule])              // apply each rule once
  Saturate(Schedule)            // repeat until no new unions/insertions
  Repeat(Int, Schedule)         // repeat at most N times
  Seq(Array[Schedule])          // sequential composition
}

enum StopReason {
  Saturated       // no new facts produced
  IterLimit       // hit Repeat limit
  NodeLimit       // database too large
}

fn Database::run_schedule(self, schedule: Schedule) -> StopReason
```

Each `Run` step: search all rules -> apply all matches -> rebuild. Same read-apply-rebuild cadence as egg's Runner but with configurable composition via `Seq`/`Saturate`/`Repeat`.

## Layer 3: STLC Bidirectional Type Inference

### Schema Definition

```moonbit
fn stlc_database() -> Database {
  let db = Database::new()

  // Sorts
  db.add_sort(EqSort("Expr"))
  db.add_sort(EqSort("Type"))
  db.add_sort(PrimitiveSort("Int"))
  db.add_sort(PrimitiveSort("String"))

  // Expression constructors
  db.new_function("Num",    [PrimitiveSort("Int")], EqSort("Expr"))
  db.new_function("Var",    [PrimitiveSort("String")], EqSort("Expr"))
  db.new_function("Add",    [EqSort("Expr"), EqSort("Expr")], EqSort("Expr"))
  db.new_function("Lam",    [PrimitiveSort("String"), EqSort("Expr")], EqSort("Expr"))
  db.new_function("App",    [EqSort("Expr"), EqSort("Expr")], EqSort("Expr"))

  // Type constructors
  db.new_function("IntTy",  [], EqSort("Type"))
  db.new_function("Arrow",  [EqSort("Type"), EqSort("Type")], EqSort("Type"))

  // Relations (functions with no meaningful output — output is unit/bool)
  db.new_function("HasType", [EqSort("Expr")], EqSort("Type"), merge=union_merge)
  db.new_function("InEnv",   [PrimitiveSort("String")], EqSort("Type"), merge=union_merge)

  db
}
```

`HasType` and `InEnv` use `union_merge` — when two types are assigned to the same expression or variable, they are unified (union'd in the e-graph). This implements type unification as a merge function.

### Typing Rules

```moonbit
fn stlc_rules() -> Array[Rule] {
  [
    // --- Synthesis (bottom-up) ---

    // Num(n) : IntTy
    Rule { name: "type-num", query: [
      Fact("Num", [Var("?n"), Var("?e")])       // ?e = Num(?n)
    ], actions: [
      Set("HasType", [Var("?e")], Call("IntTy", []))
    ]},

    // Var(x) : T  when  InEnv(x, T)
    Rule { name: "type-var", query: [
      Fact("Var", [Var("?x"), Var("?e")]),      // ?e = Var(?x)
      Fact("InEnv", [Var("?x"), Var("?t")])     // InEnv(?x) = ?t
    ], actions: [
      Set("HasType", [Var("?e")], Var("?t"))
    ]},

    // Add(a, b) : IntTy  when  a:IntTy, b:IntTy
    Rule { name: "type-add", query: [
      Fact("Add", [Var("?a"), Var("?b"), Var("?e")]),
      Fact("HasType", [Var("?a"), Var("?ta")]),
      Fact("HasType", [Var("?b"), Var("?tb")]),
      Equal(Var("?ta"), Call("IntTy", [])),
      Equal(Var("?tb"), Call("IntTy", []))
    ], actions: [
      Set("HasType", [Var("?e")], Call("IntTy", []))
    ]},

    // App(f, arg) : B  when  f:(A->B), arg:A
    Rule { name: "type-app", query: [
      Fact("App", [Var("?f"), Var("?a"), Var("?e")]),
      Fact("HasType", [Var("?f"), Var("?tf")]),
      Fact("HasType", [Var("?a"), Var("?ta")]),
      Fact("Arrow", [Var("?ta"), Var("?tb"), Var("?tf")])
    ], actions: [
      Set("HasType", [Var("?e")], Var("?tb"))
    ]},

    // --- Checking (top-down) ---

    // Lam(x, body) : Arrow(A, B)  =>  InEnv(x, A), HasType(body, B)
    Rule { name: "check-lam", query: [
      Fact("Lam", [Var("?x"), Var("?body"), Var("?e")]),
      Fact("HasType", [Var("?e"), Var("?t")]),
      Fact("Arrow", [Var("?a"), Var("?b"), Var("?t")])
    ], actions: [
      Set("InEnv", [Var("?x")], Var("?a")),
      Set("HasType", [Var("?body")], Var("?b"))
    ]},
  ]
}
```

### Usage Example

```moonbit
let db = stlc_database()

// Build: (lam x (add (var x) (num 1)))
let one = db.call("Num", [IntVal(1)])
let x = db.call("Var", [StrVal("x")])
let add = db.call("Add", [x, one])
let lam = db.call("Lam", [StrVal("x"), add])

// Assert: the lambda has type Int -> Int
let int_ty = db.call("IntTy", [])
let arr_ty = db.call("Arrow", [int_ty, int_ty])
db.call("HasType", [lam, arr_ty])  // top-down seed

// Run type inference
let rules = stlc_rules()
db.run_schedule(Saturate(Run(rules)))

// Query: what type does x have?
let x_type = db.lookup("HasType", [x])
// x_type = IntTy  (inferred via top-down flow from Arrow(Int, Int))
```

The checking rule for `Lam` pushes `Int` down into `InEnv("x", Int)`, which the synthesis rule for `Var` picks up to type `x` as `Int`. This bidirectional flow is the key demonstration.

## Package Structure

```
loom/egglog/
  moon.mod.json                   "dowdiness/egglog" v0.1.0
  src/
    moon.pkg                      depends on stdlib only
    database.mbt                  Database, FunctionTable, Sort, Value
    union_find.mbt                UnionFind, Id (copied from egraph, ~80 lines)
    rule.mbt                      Rule, Atom, Term, Action, rewrite sugar
    join.mbt                      binary join query execution + column index
    schedule.mbt                  Schedule enum + interpreter
    extract.mbt                   cost-based extraction over database
    congruence.mbt                rebuild / congruence closure over tables
  src/examples/stlc/
    moon.pkg                      depends on dowdiness/egglog
    stlc.mbt                      STLC schema + rules
    stlc_wbtest.mbt               type inference tests
  docs/
    design.md                     this document
```

## Test Plan

### Unit Tests (per file)

**database_wbtest.mbt**
- Create database, add sorts, register functions
- Insert rows, lookup existing rows
- Merge conflict without merge function -> error
- Merge conflict with merge function -> resolved
- Union two ids, verify find

**union_find_wbtest.mbt**
- (Copied from egraph: path compression, union by rank, transitivity)

**congruence_wbtest.mbt**
- Union two ids, rebuild, verify table canonicalization
- Congruence detection: f(a) and f(b) after union(a, b)
- Fixed-point: congruence triggering further congruence

**join_wbtest.mbt**
- Single-atom query (table scan)
- Two-atom join with shared variable
- Three-atom join with shared variable across all three
- Literal filtering
- Equal constraint enforcement
- Empty result when no match

**rule_wbtest.mbt**
- Single rule application with union action
- Single rule application with set action
- Rewrite sugar desugaring
- Rule producing no matches (no-op)
- Action evaluation order (let bindings used by subsequent actions)

**schedule_wbtest.mbt**
- Run once
- Saturate reaches fixed point
- Repeat respects iteration limit
- Seq composes correctly

**extract_wbtest.mbt**
- Extract single constant
- Extract cheapest after rewrite
- DAG sharing in extracted term

### Integration Tests (STLC)

**stlc_wbtest.mbt**
- `Num(42)` synthesizes `IntTy`
- `Var("x")` with `InEnv("x", IntTy)` synthesizes `IntTy`
- `Add(Num(1), Num(2))` synthesizes `IntTy`
- `App(f, arg)` with `f : Int -> Int` and `arg : Int` synthesizes `IntTy`
- `Lam("x", Var("x"))` checked against `Int -> Int` infers `InEnv("x", Int)` (top-down)
- `Lam("x", Add(Var("x"), Num(1)))` checked against `Int -> Int` succeeds
- `App(Lam("x", Var("x")), Num(42))` synthesizes `IntTy` (both directions cooperate)
- Type error: `Add(Num(1), Lam("x", Var("x")))` — cannot unify `Arrow` with `IntTy`

## Future Extensions

These are explicitly **out of scope** for the initial implementation but the design accommodates them:

- **Semi-naive evaluation via incr**: Track per-table deltas with `Signal[Array[Row]]`, only match rules against new facts
- **WCOJ generic join**: Replace binary join with worst-case optimal join for complex multi-way patterns
- **DSL parser via loom**: Parse egglog s-expression syntax into Rule/Action structs
- **Proof production**: Record which rule justified each union/insertion for explanation extraction
- **Hindley-Milner**: Extend STLC with forall, instantiation, generalization
- **DOT visualization**: Render database state as GraphViz graph
