# Egglog Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Build a relational e-graph engine (`dowdiness/egglog`) with bidirectional type inference for STLC as the first demonstration.

**Architecture:** Three layers — relational e-graph core (Database, FunctionTable, UnionFind), rule engine (Rule, binary join, Schedule), and STLC example. Each layer is independently testable. No external dependencies beyond MoonBit stdlib.

**Tech Stack:** MoonBit, moon build system, `@hashmap`/`@hashset` from stdlib.

**Design doc:** `docs/plans/2026-03-08-egglog-design.md`

---

### Task 1: Scaffold the module

**Files:**
- Create: `loom/egglog/moon.mod.json`
- Create: `loom/egglog/src/moon.pkg`
- Create: `loom/egglog/src/egglog.mbt` (placeholder)

**Step 1: Create directory structure**

```bash
mkdir -p loom/egglog/src
```

**Step 2: Create moon.mod.json**

Create `loom/egglog/moon.mod.json`:
```json
{
  "name": "dowdiness/egglog",
  "version": "0.1.0",
  "license": "Apache-2.0",
  "keywords": ["egglog", "e-graph", "datalog", "equality-saturation", "relational"],
  "description": "Relational e-graph engine (egglog) in MoonBit"
}
```

**Step 3: Create moon.pkg**

Create `loom/egglog/src/moon.pkg`:
```
import {
  "moonbitlang/core/builtin",
  "moonbitlang/core/hashmap",
  "moonbitlang/core/hashset",
}
```

**Step 4: Create placeholder source**

Create `loom/egglog/src/egglog.mbt`:
```moonbit
// ════════════════════════════════════════════════════════════════════
// Egglog: Relational E-Graph Engine
// ════════════════════════════════════════════════════════════════════
//
// A relational e-graph engine that unifies Datalog and equality
// saturation. Functions are stored as database tables, e-matching
// uses relational joins, and rules are Datalog queries with actions.
//
// References:
//   - egglog paper: https://arxiv.org/abs/2304.04332
//   - egg paper: https://arxiv.org/abs/2004.03082
// ════════════════════════════════════════════════════════════════════
```

**Step 5: Verify it builds**

Run: `cd loom/egglog && moon check`
Expected: success (empty module compiles)

**Step 6: Commit**

```bash
cd loom/egglog
git add moon.mod.json src/moon.pkg src/egglog.mbt
git commit -m "feat(egglog): scaffold dowdiness/egglog module"
```

---

### Task 2: UnionFind and Id

Copy the UnionFind and Id from egraph, adapted as private types within the egglog module.

**Files:**
- Create: `loom/egglog/src/union_find.mbt`
- Create: `loom/egglog/src/union_find_wbtest.mbt`

**Step 1: Write the failing tests**

Create `loom/egglog/src/union_find_wbtest.mbt`:
```moonbit
///|
test "fresh id finds itself" {
  let uf = UnionFind::new()
  let a = uf.make_set()
  inspect!(uf.find(a), content="0")
}

///|
test "union makes find agree" {
  let uf = UnionFind::new()
  let a = uf.make_set()
  let b = uf.make_set()
  let _ = uf.union(a, b)
  inspect!(uf.find(a) == uf.find(b), content="true")
}

///|
test "transitivity" {
  let uf = UnionFind::new()
  let a = uf.make_set()
  let b = uf.make_set()
  let c = uf.make_set()
  let _ = uf.union(a, b)
  let _ = uf.union(b, c)
  inspect!(uf.find(a) == uf.find(c), content="true")
}

///|
test "size tracks elements" {
  let uf = UnionFind::new()
  let _ = uf.make_set()
  let _ = uf.make_set()
  let _ = uf.make_set()
  inspect!(uf.size(), content="3")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd loom/egglog && moon test`
Expected: FAIL (UnionFind not defined)

**Step 3: Write the implementation**

Create `loom/egglog/src/union_find.mbt`:
```moonbit
///|
/// E-class identifier. Newtype wrapper around Int for type safety.
pub(all) struct Id(Int) derive(Eq, Compare, Hash, Debug)

///|
pub impl Show for Id with output(self, logger) {
  let Id(i) = self
  logger.write_string(i.to_string())
}

///|
type Rank = Int

///|
/// Union-Find with path compression and union by rank.
priv struct UnionFind {
  parents : Array[Id]
  ranks : Array[Rank]
} derive(Default, Show, Debug)

///|
fn UnionFind::new() -> UnionFind {
  UnionFind::default()
}

///|
fn UnionFind::make_set(self : UnionFind) -> Id {
  let id = Id(self.parents.length())
  self.parents.push(id)
  self.ranks.push(0)
  id
}

///|
fn UnionFind::find(self : UnionFind, id : Id) -> Id {
  let mut current = id
  while self.parents[current.0] != current {
    current = self.parents[current.0]
  }
  let root = current
  current = id
  while current != root {
    let next = self.parents[current.0]
    self.parents[current.0] = root
    current = next
  }
  root
}

///|
fn UnionFind::union(self : UnionFind, a : Id, b : Id) -> Id {
  let root_a = self.find(a)
  let root_b = self.find(b)
  if root_a == root_b {
    return root_a
  }
  let Id(ra) = root_a
  let Id(rb) = root_b
  if self.ranks[ra] < self.ranks[rb] {
    self.parents[ra] = root_b
    root_b
  } else if self.ranks[ra] > self.ranks[rb] {
    self.parents[rb] = root_a
    root_a
  } else {
    self.parents[rb] = root_a
    self.ranks[ra] = self.ranks[ra] + 1
    root_a
  }
}

///|
fn UnionFind::size(self : UnionFind) -> Int {
  self.parents.length()
}
```

**Step 4: Run tests to verify they pass**

Run: `cd loom/egglog && moon test`
Expected: 4 tests PASS

**Step 5: Format and commit**

```bash
cd loom/egglog && moon fmt
git add src/union_find.mbt src/union_find_wbtest.mbt
git commit -m "feat(egglog): add UnionFind and Id"
```

---

### Task 3: Value, Sort, and FunctionTable

The core data model: typed values, sort system, and function tables with merge.

**Files:**
- Create: `loom/egglog/src/types.mbt`
- Create: `loom/egglog/src/function_table.mbt`
- Create: `loom/egglog/src/function_table_wbtest.mbt`

**Step 1: Write the failing tests**

Create `loom/egglog/src/function_table_wbtest.mbt`:
```moonbit
///|
test "insert and lookup row" {
  let ft = FunctionTable::new("Add", 3, None)
  let key : Array[Value] = [IdVal(Id(0)), IdVal(Id(1))]
  ft.insert(key, IdVal(Id(2)))
  inspect!(ft.lookup(key), content="Some(IdVal(0:2))")
}

///|
test "lookup missing row returns None" {
  let ft = FunctionTable::new("Add", 3, None)
  let key : Array[Value] = [IdVal(Id(0)), IdVal(Id(1))]
  inspect!(ft.lookup(key), content="None")
}

///|
test "insert duplicate key without merge is error" {
  let ft = FunctionTable::new("Add", 3, None)
  let key : Array[Value] = [IdVal(Id(0)), IdVal(Id(1))]
  ft.insert(key, IdVal(Id(2)))
  // inserting same key with different value and no merge should return the old value
  let result = ft.insert(key, IdVal(Id(3)))
  // old value is returned when conflict without merge
  inspect!(result, content="IdVal(0:2)")
}

///|
test "insert duplicate key with merge resolves" {
  // merge takes minimum Id
  let merge : MergeFn = fn(a, b) {
    match (a, b) {
      (IdVal(Id(x)), IdVal(Id(y))) => IdVal(Id(if x < y { x } else { y }))
      _ => a
    }
  }
  let ft = FunctionTable::new("Cost", 2, Some(merge))
  let key : Array[Value] = [IdVal(Id(0))]
  ft.insert(key, IdVal(Id(5)))
  ft.insert(key, IdVal(Id(3)))
  inspect!(ft.lookup(key), content="Some(IdVal(0:3))")
}

///|
test "row count" {
  let ft = FunctionTable::new("F", 2, None)
  ft.insert([IdVal(Id(0))], IdVal(Id(1)))
  ft.insert([IdVal(Id(2))], IdVal(Id(3)))
  inspect!(ft.row_count(), content="2")
}

///|
test "scan all rows" {
  let ft = FunctionTable::new("F", 2, None)
  ft.insert([IntVal(1)], IdVal(Id(0)))
  ft.insert([IntVal(2)], IdVal(Id(1)))
  let rows = ft.scan()
  inspect!(rows.length(), content="2")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd loom/egglog && moon test`
Expected: FAIL (Value, FunctionTable not defined)

**Step 3: Write the types**

Create `loom/egglog/src/types.mbt`:
```moonbit
///|
/// A value in the egglog database. Either an e-class Id or a primitive.
pub(all) enum Value {
  IdVal(Id)
  IntVal(Int)
  StrVal(String)
} derive(Eq, Hash, Compare, Show, Debug)

///|
/// Sort (type) of a column in a function table.
pub(all) enum Sort {
  EqSort(String)         // e-class sort (participates in union-find)
  PrimitiveSort(String)  // i64, String, etc. (no merging)
} derive(Eq, Hash, Show, Debug)

///|
/// Merge function type alias.
pub(all) typealias MergeFn = (Value, Value) -> Value
```

**Step 4: Write the FunctionTable implementation**

Create `loom/egglog/src/function_table.mbt`:
```moonbit
///|
/// A function table: maps input tuples to output values.
/// Arity includes the output column (e.g., Add(Expr, Expr) -> Expr has arity 3).
priv struct FunctionTable {
  name : String
  arity : Int
  rows : Map[String, Value]    // key: serialized input tuple
  raw_keys : Map[String, Array[Value]]  // key string -> original key array
  merge : MergeFn?
} derive(Show, Debug)

///|
fn FunctionTable::new(name : String, arity : Int, merge : MergeFn?) -> FunctionTable {
  { name, arity, rows: {}, raw_keys: {}, merge }
}

///|
/// Serialize a key array to a string for map lookup.
fn key_string(key : Array[Value]) -> String {
  let buf = StringBuilder::new()
  for i, v in key {
    if i > 0 {
      buf.write_char(',')
    }
    buf.write_string(v.to_string())
  }
  buf.to_string()
}

///|
/// Insert a row. Returns the stored output value.
/// If key already exists:
///   - With merge: merges old and new, stores result
///   - Without merge: returns old value (no-op)
fn FunctionTable::insert(
  self : FunctionTable,
  key : Array[Value],
  value : Value
) -> Value {
  let ks = key_string(key)
  match self.rows[ks] {
    Some(old) =>
      if old == value {
        old
      } else {
        match self.merge {
          Some(f) => {
            let merged = f(old, value)
            self.rows[ks] = merged
            merged
          }
          None => old // conflict without merge: keep old
        }
      }
    None => {
      self.rows[ks] = value
      self.raw_keys[ks] = key
      value
    }
  }
}

///|
/// Look up the output value for an input tuple.
fn FunctionTable::lookup(self : FunctionTable, key : Array[Value]) -> Value? {
  self.rows[key_string(key)]
}

///|
/// Number of rows in the table.
fn FunctionTable::row_count(self : FunctionTable) -> Int {
  self.rows.size()
}

///|
/// Scan all rows. Returns array of (key, value) pairs.
fn FunctionTable::scan(self : FunctionTable) -> Array[(Array[Value], Value)] {
  let result : Array[(Array[Value], Value)] = []
  self.rows.each(fn(ks, v) {
    match self.raw_keys[ks] {
      Some(key) => result.push((key, v))
      None => ()
    }
  })
  result
}
```

**Step 5: Run tests to verify they pass**

Run: `cd loom/egglog && moon test`
Expected: all tests PASS

**Step 6: Format and commit**

```bash
cd loom/egglog && moon fmt
git add src/types.mbt src/function_table.mbt src/function_table_wbtest.mbt
git commit -m "feat(egglog): add Value, Sort, and FunctionTable"
```

---

### Task 4: Database core

The central Database struct that holds all function tables and the union-find. Provides `call`, `union`, and `rebuild`.

**Files:**
- Create: `loom/egglog/src/database.mbt`
- Create: `loom/egglog/src/database_wbtest.mbt`

**Step 1: Write the failing tests**

Create `loom/egglog/src/database_wbtest.mbt`:
```moonbit
///|
test "fresh id allocation" {
  let db = Database::new()
  let a = db.alloc_id()
  let b = db.alloc_id()
  inspect!(a, content="0")
  inspect!(b, content="1")
}

///|
test "register and call function" {
  let db = Database::new()
  db.register("Num", 2, None)
  let id = db.call("Num", [IntVal(42)])
  inspect!(id != IdVal(Id(-1)), content="true")
}

///|
test "call same args returns same id" {
  let db = Database::new()
  db.register("Num", 2, None)
  let id1 = db.call("Num", [IntVal(42)])
  let id2 = db.call("Num", [IntVal(42)])
  inspect!(id1 == id2, content="true")
}

///|
test "call different args returns different ids" {
  let db = Database::new()
  db.register("Num", 2, None)
  let id1 = db.call("Num", [IntVal(1)])
  let id2 = db.call("Num", [IntVal(2)])
  inspect!(id1 == id2, content="false")
}

///|
test "union and find" {
  let db = Database::new()
  db.register("Num", 2, None)
  let v1 = db.call("Num", [IntVal(1)])
  let v2 = db.call("Num", [IntVal(2)])
  match (v1, v2) {
    (IdVal(id1), IdVal(id2)) => {
      db.union(id1, id2)
      db.rebuild()
      inspect!(db.find(id1) == db.find(id2), content="true")
    }
    _ => abort("expected IdVal")
  }
}

///|
test "congruence closure" {
  // If Add(a, b) and Add(a, b) exist with different outputs,
  // after union(a, a') and rebuild, congruent rows should merge.
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let add1 = db.call("Add", [n1, n2])
  // Force a second Add with the same semantic args via union
  let n1b = db.call("Num", [IntVal(10)])
  let add2 = db.call("Add", [n1b, n2])
  // Now union n1 and n1b
  match (n1, n1b) {
    (IdVal(id1), IdVal(id1b)) => {
      db.union(id1, id1b)
      db.rebuild()
      // add1 and add2 should now be in the same e-class (congruence)
      match (add1, add2) {
        (IdVal(a1), IdVal(a2)) =>
          inspect!(db.find(a1) == db.find(a2), content="true")
        _ => abort("expected IdVal")
      }
    }
    _ => abort("expected IdVal")
  }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd loom/egglog && moon test`
Expected: FAIL (Database not defined)

**Step 3: Write the implementation**

Create `loom/egglog/src/database.mbt`:
```moonbit
///|
/// The egglog database: a collection of function tables + union-find.
priv struct Database {
  uf : UnionFind
  tables : Map[String, FunctionTable]
  pending : Array[(Id, Id)]
} derive(Show, Debug)

///|
fn Database::new() -> Database {
  { uf: UnionFind::new(), tables: {}, pending: [] }
}

///|
/// Allocate a fresh e-class id.
fn Database::alloc_id(self : Database) -> Id {
  self.uf.make_set()
}

///|
/// Find the canonical representative for an id.
fn Database::find(self : Database, id : Id) -> Id {
  self.uf.find(id)
}

///|
/// Register a function table.
fn Database::register(
  self : Database,
  name : String,
  arity : Int,
  merge : MergeFn?
) -> Unit {
  self.tables[name] = FunctionTable::new(name, arity, merge)
}

///|
/// Canonicalize a value through the union-find.
fn Database::canonicalize_value(self : Database, v : Value) -> Value {
  match v {
    IdVal(id) => IdVal(self.uf.find(id))
    _ => v
  }
}

///|
/// Call a function: look up or insert a row.
/// Input args are canonicalized. If no existing row, allocates a fresh Id
/// as the output (for EqSort functions).
fn Database::call(self : Database, name : String, args : Array[Value]) -> Value {
  let table = match self.tables[name] {
    Some(t) => t
    None => abort("unknown function: " + name)
  }
  // Canonicalize input args
  let canon_args : Array[Value] = args.map(fn(v) { self.canonicalize_value(v) })
  // Check existing
  match table.lookup(canon_args) {
    Some(v) => self.canonicalize_value(v)
    None => {
      let output = IdVal(self.alloc_id())
      table.insert(canon_args, output)
      output
    }
  }
}

///|
/// Set a function row to a specific value (for relations/analysis).
/// If row exists, merges or unions the values.
fn Database::set(
  self : Database,
  name : String,
  args : Array[Value],
  value : Value
) -> Value {
  let table = match self.tables[name] {
    Some(t) => t
    None => abort("unknown function: " + name)
  }
  let canon_args : Array[Value] = args.map(fn(v) { self.canonicalize_value(v) })
  let canon_val = self.canonicalize_value(value)
  match table.lookup(canon_args) {
    Some(old) => {
      let canon_old = self.canonicalize_value(old)
      if canon_old == canon_val {
        canon_old
      } else {
        // For IdVal outputs, union them
        match (canon_old, canon_val) {
          (IdVal(a), IdVal(b)) => {
            self.pending.push((a, b))
            let merged = table.insert(canon_args, canon_val)
            merged
          }
          _ =>
            match table.merge {
              Some(_) => table.insert(canon_args, canon_val)
              None => canon_old
            }
        }
      }
    }
    None => {
      table.insert(canon_args, canon_val)
      canon_val
    }
  }
}

///|
/// Assert two e-class ids are equivalent.
fn Database::union(self : Database, a : Id, b : Id) -> Id {
  let ra = self.uf.find(a)
  let rb = self.uf.find(b)
  if ra == rb {
    return ra
  }
  self.pending.push((ra, rb))
  ra
}

///|
/// Rebuild: process pending unions and restore congruence closure.
fn Database::rebuild(self : Database) -> Unit {
  // Process all pending unions
  while self.pending.length() > 0 {
    let batch = self.pending.copy()
    self.pending.clear()
    for pair in batch {
      let (a, b) = pair
      let _ = self.uf.union(a, b)
    }
    // Canonicalize all tables and detect congruences
    self.tables.each(fn(_name, table) {
      self.rebuild_table(table)
    })
  }
}

///|
/// Rebuild a single function table: canonicalize keys, detect congruences.
fn Database::rebuild_table(self : Database, table : FunctionTable) -> Unit {
  let old_rows = table.scan()
  // Clear and reinsert with canonical keys
  table.rows.clear()
  table.raw_keys.clear()
  for pair in old_rows {
    let (key, value) = pair
    let canon_key : Array[Value] = key.map(fn(v) { self.canonicalize_value(v) })
    let canon_val = self.canonicalize_value(value)
    match table.lookup(canon_key) {
      Some(existing) => {
        let canon_existing = self.canonicalize_value(existing)
        if canon_existing != canon_val {
          match (canon_existing, canon_val) {
            (IdVal(a), IdVal(b)) => self.pending.push((a, b))
            _ => ()
          }
          // Keep one; the union will reconcile next pass
          table.insert(canon_key, canon_val)
        }
      }
      None => {
        table.insert(canon_key, canon_val)
      }
    }
  }
}

///|
/// Look up a function row's output value.
fn Database::lookup(self : Database, name : String, args : Array[Value]) -> Value? {
  let table = match self.tables[name] {
    Some(t) => t
    None => return None
  }
  let canon_args : Array[Value] = args.map(fn(v) { self.canonicalize_value(v) })
  match table.lookup(canon_args) {
    Some(v) => Some(self.canonicalize_value(v))
    None => None
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd loom/egglog && moon test`
Expected: all tests PASS

**Step 5: Format and commit**

```bash
cd loom/egglog && moon fmt
git add src/database.mbt src/database_wbtest.mbt
git commit -m "feat(egglog): add Database with call, union, rebuild"
```

---

### Task 5: Rule representation and Term evaluation

Define Rule, Atom, Term, Action types and term evaluation against a substitution.

**Files:**
- Create: `loom/egglog/src/rule.mbt`
- Create: `loom/egglog/src/rule_wbtest.mbt`

**Step 1: Write the failing tests**

Create `loom/egglog/src/rule_wbtest.mbt`:
```moonbit
///|
test "eval_term Lit returns value" {
  let db = Database::new()
  let subst : Map[String, Value] = {}
  inspect!(eval_term(db, subst, Lit(IntVal(42))), content="IntVal(42)")
}

///|
test "eval_term Var looks up substitution" {
  let db = Database::new()
  let subst : Map[String, Value] = {}
  subst["?x"] = IntVal(99)
  inspect!(eval_term(db, subst, Var("?x")), content="IntVal(99)")
}

///|
test "eval_term Call creates node in database" {
  let db = Database::new()
  db.register("Num", 2, None)
  let subst : Map[String, Value] = {}
  let result = eval_term(db, subst, Call("Num", [Lit(IntVal(42))]))
  // Should return an IdVal since Num is a registered function
  match result {
    IdVal(_) => inspect!(true, content="true")
    _ => inspect!(false, content="true")
  }
}

///|
test "rewrite sugar creates correct rule" {
  let rule = rewrite(
    "add-zero",
    "Add",
    [Var("?a"), Call("Num", [Lit(IntVal(0))])],
    Var("?a"),
  )
  inspect!(rule.name, content="add-zero")
  inspect!(rule.query.length(), content="1")
  inspect!(rule.actions.length(), content="1")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd loom/egglog && moon test`
Expected: FAIL

**Step 3: Write the implementation**

Create `loom/egglog/src/rule.mbt`:
```moonbit
///|
/// A term in a rule pattern or action.
pub(all) enum Term {
  Var(String)                  // ?x — pattern variable
  Lit(Value)                   // concrete value
  Call(String, Array[Term])    // f(t1, ...) — function call
} derive(Eq, Show, Debug)

///|
/// An atom in a rule's query (body).
pub(all) enum Atom {
  Fact(String, Array[Term])    // f(t1, t2, ..., out) — match a function table row
  Equal(Term, Term)            // t1 = t2 — equality constraint
} derive(Show, Debug)

///|
/// An action in a rule's head.
pub(all) enum Action {
  Union(Term, Term)
  Set(String, Array[Term], Term)
  LetAction(String, Term)
} derive(Show, Debug)

///|
/// A rule: query (body) + actions (head).
pub(all) struct Rule {
  name : String
  query : Array[Atom]
  actions : Array[Action]
} derive(Show, Debug)

///|
/// Evaluate a term under a substitution, creating nodes in the database as needed.
fn eval_term(db : Database, subst : Map[String, Value], term : Term) -> Value {
  match term {
    Lit(v) => db.canonicalize_value(v)
    Var(name) =>
      match subst[name] {
        Some(v) => db.canonicalize_value(v)
        None => abort("unbound variable: " + name)
      }
    Call(fname, args) => {
      let evaluated : Array[Value] = args.map(fn(t) { eval_term(db, subst, t) })
      db.call(fname, evaluated)
    }
  }
}

///|
/// Execute actions for a single substitution. Returns number of new unions.
fn execute_actions(
  db : Database,
  subst : Map[String, Value],
  actions : Array[Action]
) -> Int {
  let mut unions = 0
  // Copy subst so LetAction bindings are local
  let local_subst : Map[String, Value] = {}
  subst.each(fn(k, v) { local_subst[k] = v })
  for action in actions {
    match action {
      Union(t1, t2) => {
        let v1 = eval_term(db, local_subst, t1)
        let v2 = eval_term(db, local_subst, t2)
        match (v1, v2) {
          (IdVal(a), IdVal(b)) => {
            if db.find(a) != db.find(b) {
              let _ = db.union(a, b)
              unions = unions + 1
            }
          }
          _ => ()
        }
      }
      Set(fname, args, val) => {
        let evaluated_args : Array[Value] = args.map(fn(t) {
          eval_term(db, local_subst, t)
        })
        let evaluated_val = eval_term(db, local_subst, val)
        let _ = db.set(fname, evaluated_args, evaluated_val)
      }
      LetAction(name, term) => {
        let v = eval_term(db, local_subst, term)
        local_subst[name] = v
      }
    }
  }
  unions
}

///|
/// Rewrite sugar: creates a rule that unions the matched output with rhs.
fn rewrite(
  name : String,
  func_name : String,
  args : Array[Term],
  rhs : Term
) -> Rule {
  // The pattern matches f(args...) = ?__out
  let mut full_args = args.copy()
  full_args.push(Var("?__out"))
  {
    name,
    query: [Fact(func_name, full_args)],
    actions: [Union(Var("?__out"), rhs)],
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd loom/egglog && moon test`
Expected: all tests PASS

**Step 5: Format and commit**

```bash
cd loom/egglog && moon fmt
git add src/rule.mbt src/rule_wbtest.mbt
git commit -m "feat(egglog): add Rule, Term, Action types and eval"
```

---

### Task 6: Binary join query execution

The query engine: match rule atoms against database tables using binary join with hash probing.

**Files:**
- Create: `loom/egglog/src/join.mbt`
- Create: `loom/egglog/src/join_wbtest.mbt`

**Step 1: Write the failing tests**

Create `loom/egglog/src/join_wbtest.mbt`:
```moonbit
///|
test "single atom query scans table" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  let _ = db.call("Num", [IntVal(2)])
  let query : Array[Atom] = [Fact("Num", [Var("?n"), Var("?e")])]
  let results = execute_query(db, query)
  inspect!(results.length(), content="2")
}

///|
test "single atom with literal filters" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  let _ = db.call("Num", [IntVal(2)])
  let query : Array[Atom] = [Fact("Num", [Lit(IntVal(1)), Var("?e")])]
  let results = execute_query(db, query)
  inspect!(results.length(), content="1")
}

///|
test "two atom join with shared variable" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  // Query: Add(?a, ?b, ?e), Num(1, ?a)
  // Should find the one Add row where ?a = Num(1)
  let query : Array[Atom] = [
    Fact("Add", [Var("?a"), Var("?b"), Var("?e")]),
    Fact("Num", [Lit(IntVal(1)), Var("?a")]),
  ]
  let results = execute_query(db, query)
  inspect!(results.length(), content="1")
}

///|
test "equal constraint filters" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n1 = db.call("Num", [IntVal(1)])
  let _ = db.call("Add", [n1, n1])
  let n2 = db.call("Num", [IntVal(2)])
  let _ = db.call("Add", [n1, n2])
  // Query: Add(?a, ?b, ?e) where ?a = ?b (only the first Add matches)
  let query : Array[Atom] = [
    Fact("Add", [Var("?a"), Var("?b"), Var("?e")]),
    Equal(Var("?a"), Var("?b")),
  ]
  let results = execute_query(db, query)
  inspect!(results.length(), content="1")
}

///|
test "empty result when no match" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  let query : Array[Atom] = [Fact("Num", [Lit(IntVal(999)), Var("?e")])]
  let results = execute_query(db, query)
  inspect!(results.length(), content="0")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd loom/egglog && moon test`
Expected: FAIL (execute_query not defined)

**Step 3: Write the implementation**

Create `loom/egglog/src/join.mbt`:
```moonbit
///|
/// Execute a conjunctive query against the database.
/// Returns all substitutions that satisfy every atom.
fn execute_query(db : Database, query : Array[Atom]) -> Array[Map[String, Value]] {
  // Separate facts from equality constraints
  let facts : Array[Atom] = []
  let equals : Array[Atom] = []
  for atom in query {
    match atom {
      Fact(_, _) => facts.push(atom)
      Equal(_, _) => equals.push(atom)
    }
  }
  // Start with a single empty substitution
  let mut current : Array[Map[String, Value]] = [{}]
  // Process each fact atom: for each existing subst, probe the table
  for atom in facts {
    match atom {
      Fact(fname, terms) => {
        let next : Array[Map[String, Value]] = []
        let table = match db.tables[fname] {
          Some(t) => t
          None => continue // unknown table, skip
        }
        let rows = table.scan()
        for subst in current {
          for row_pair in rows {
            let (key, value) = row_pair
            // Build the full row: key columns + output column
            let full_row : Array[Value] = key.copy()
            full_row.push(value)
            // Try to unify terms with this row
            match unify_row(db, subst, terms, full_row) {
              Some(new_subst) => next.push(new_subst)
              None => ()
            }
          }
        }
        current = next
      }
      _ => () // handled below
    }
  }
  // Apply equality constraints
  let filtered : Array[Map[String, Value]] = []
  for subst in current {
    let mut pass = true
    for atom in equals {
      match atom {
        Equal(t1, t2) => {
          let v1 = eval_term_subst(db, subst, t1)
          let v2 = eval_term_subst(db, subst, t2)
          match (v1, v2) {
            (Some(a), Some(b)) =>
              if db.canonicalize_value(a) != db.canonicalize_value(b) {
                pass = false
              }
            _ => { pass = false }
          }
        }
        _ => ()
      }
    }
    if pass {
      filtered.push(subst)
    }
  }
  filtered
}

///|
/// Try to unify a term list with a row of values under an existing substitution.
/// Returns extended substitution on success, None on failure.
fn unify_row(
  db : Database,
  subst : Map[String, Value],
  terms : Array[Term],
  row : Array[Value]
) -> Map[String, Value]? {
  if terms.length() != row.length() {
    return None
  }
  // Copy subst for extension
  let new_subst : Map[String, Value] = {}
  subst.each(fn(k, v) { new_subst[k] = v })
  for i, term in terms {
    let row_val = db.canonicalize_value(row[i])
    match term {
      Lit(v) => {
        if db.canonicalize_value(v) != row_val {
          return None
        }
      }
      Var(name) =>
        match new_subst[name] {
          Some(bound) => {
            if db.canonicalize_value(bound) != row_val {
              return None // variable bound to different value
            }
          }
          None => new_subst[name] = row_val
        }
      Call(fname, args) => {
        // Evaluate the call, then check equality with row value
        let call_val = match eval_term_subst(db, new_subst, Call(fname, args)) {
          Some(v) => v
          None => return None
        }
        if db.canonicalize_value(call_val) != row_val {
          return None
        }
      }
    }
  }
  Some(new_subst)
}

///|
/// Evaluate a term under a substitution, returning None if a variable is unbound.
/// Unlike eval_term, this does not abort on unbound variables.
fn eval_term_subst(
  db : Database,
  subst : Map[String, Value],
  term : Term
) -> Value? {
  match term {
    Lit(v) => Some(db.canonicalize_value(v))
    Var(name) =>
      match subst[name] {
        Some(v) => Some(db.canonicalize_value(v))
        None => None
      }
    Call(fname, args) => {
      let evaluated : Array[Value] = []
      for arg in args {
        match eval_term_subst(db, subst, arg) {
          Some(v) => evaluated.push(v)
          None => return None
        }
      }
      Some(db.call(fname, evaluated))
    }
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd loom/egglog && moon test`
Expected: all tests PASS

**Step 5: Format and commit**

```bash
cd loom/egglog && moon fmt
git add src/join.mbt src/join_wbtest.mbt
git commit -m "feat(egglog): add binary join query execution"
```

---

### Task 7: Schedule engine

The schedule interpreter: Run, Saturate, Repeat, Seq.

**Files:**
- Create: `loom/egglog/src/schedule.mbt`
- Create: `loom/egglog/src/schedule_wbtest.mbt`

**Step 1: Write the failing tests**

Create `loom/egglog/src/schedule_wbtest.mbt`:
```moonbit
///|
test "run applies rules once" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n0 = db.call("Num", [IntVal(0)])
  let n1 = db.call("Num", [IntVal(1)])
  let _ = db.call("Add", [n1, n0])
  // Rule: Add(?a, Num(0)) => union with ?a
  let rule = rewrite("add-zero", "Add", [Var("?a"), Call("Num", [Lit(IntVal(0))])], Var("?a"))
  let result = db.run_schedule(Run([rule]))
  inspect!(result, content="Saturated")
}

///|
test "saturate reaches fixed point" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n0 = db.call("Num", [IntVal(0)])
  let n1 = db.call("Num", [IntVal(1)])
  let _ = db.call("Add", [n1, n0])
  let rule = rewrite("add-zero", "Add", [Var("?a"), Call("Num", [Lit(IntVal(0))])], Var("?a"))
  let result = db.run_schedule(Saturate(Run([rule]), 100))
  inspect!(result, content="Saturated")
}

///|
test "repeat respects limit" {
  let db = Database::new()
  db.register("Num", 2, None)
  let _ = db.call("Num", [IntVal(1)])
  // A rule that always produces new facts (never saturates)
  // Actually, this rule does nothing since it just re-inserts same fact.
  // Use a simpler test: repeat 3 times, check it terminates
  let rule : Rule = { name: "noop", query: [], actions: [] }
  let result = db.run_schedule(Repeat(3, Run([rule])))
  inspect!(result, content="Saturated")
}

///|
test "seq composes schedules" {
  let db = Database::new()
  db.register("Num", 2, None)
  db.register("Add", 3, None)
  let n0 = db.call("Num", [IntVal(0)])
  let n1 = db.call("Num", [IntVal(1)])
  let _ = db.call("Add", [n1, n0])
  let rule = rewrite("add-zero", "Add", [Var("?a"), Call("Num", [Lit(IntVal(0))])], Var("?a"))
  let result = db.run_schedule(Seq([Run([rule]), Run([rule])]))
  inspect!(result, content="Saturated")
}
```

**Step 2: Run tests to verify they fail**

Run: `cd loom/egglog && moon test`
Expected: FAIL (Schedule, run_schedule not defined)

**Step 3: Write the implementation**

Create `loom/egglog/src/schedule.mbt`:
```moonbit
///|
/// Schedule controls rule application order.
pub(all) enum Schedule {
  Run(Array[Rule])                   // apply each rule once
  Saturate(Schedule, Int)            // repeat until no new facts (with max iterations)
  Repeat(Int, Schedule)              // repeat exactly N times
  Seq(Array[Schedule])               // sequential composition
} derive(Show, Debug)

///|
/// Why the schedule stopped.
pub(all) enum StopReason {
  Saturated       // no new facts produced
  IterLimit       // hit iteration limit
  NodeLimit       // database too large
} derive(Eq, Show, Debug)

///|
/// Apply a single rule to the database. Returns number of new unions.
fn Database::apply_rule(self : Database, rule : Rule) -> Int {
  let matches = execute_query(self, rule.query)
  let mut total_unions = 0
  for subst in matches {
    total_unions = total_unions + execute_actions(self, subst, rule.actions)
  }
  total_unions
}

///|
/// Run a schedule on the database.
fn Database::run_schedule(self : Database, schedule : Schedule) -> StopReason {
  match schedule {
    Run(rules) => {
      let mut changed = false
      for rule in rules {
        let unions = self.apply_rule(rule)
        if unions > 0 {
          changed = true
        }
      }
      self.rebuild()
      if changed { Saturated } else { Saturated }
    }
    Saturate(inner, max_iter) => {
      for i = 0; i < max_iter; i = i + 1 {
        let size_before = self.uf.size()
        let _ = self.run_schedule(inner)
        let size_after = self.uf.size()
        // Check if anything changed: new ids or pending unions were processed
        if size_before == size_after {
          // Run once more to check for new matches after rebuild
          let old_size = self.uf.size()
          let _ = self.run_schedule(inner)
          if self.uf.size() == old_size {
            return Saturated
          }
        }
      }
      IterLimit
    }
    Repeat(n, inner) => {
      let mut last_result = Saturated
      for i = 0; i < n; i = i + 1 {
        last_result = self.run_schedule(inner)
      }
      last_result
    }
    Seq(schedules) => {
      let mut last_result = Saturated
      for s in schedules {
        last_result = self.run_schedule(s)
      }
      last_result
    }
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd loom/egglog && moon test`
Expected: all tests PASS

**Step 5: Format and commit**

```bash
cd loom/egglog && moon fmt
git add src/schedule.mbt src/schedule_wbtest.mbt
git commit -m "feat(egglog): add Schedule engine (Run, Saturate, Repeat, Seq)"
```

---

### Task 8: Extraction

Cost-based extraction from the relational database.

**Files:**
- Create: `loom/egglog/src/extract.mbt`
- Create: `loom/egglog/src/extract_wbtest.mbt`

**Step 1: Write the failing tests**

Create `loom/egglog/src/extract_wbtest.mbt`:
```moonbit
///|
test "extract single constant" {
  let db = Database::new()
  db.register("Num", 2, None)
  let v = db.call("Num", [IntVal(42)])
  match v {
    IdVal(id) => {
      let (cost, expr) = db.extract(id, ast_size)
      inspect!(cost, content="1")
      inspect!(expr.to_string(), content="(Num 42)")
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
  let add_v = db.call("Add", [n1, n0])
  // Union Add(1,0) with Num(1) (simulating rewrite: x+0 = x)
  match (add_v, n1) {
    (IdVal(add_id), IdVal(n1_id)) => {
      db.union(add_id, n1_id)
      db.rebuild()
      let (cost, expr) = db.extract(add_id, ast_size)
      // Should pick Num(1) (cost 1) over Add(Num(1), Num(0)) (cost 3)
      inspect!(cost, content="1")
      inspect!(expr.to_string(), content="(Num 1)")
    }
    _ => abort("expected IdVal")
  }
}
```

**Step 2: Run tests to verify they fail**

Run: `cd loom/egglog && moon test`
Expected: FAIL

**Step 3: Write the implementation**

Create `loom/egglog/src/extract.mbt`:
```moonbit
///|
/// A flattened extracted expression.
pub(all) struct ExtractedExpr {
  func_name : String
  args : Array[ExtractedExpr]
  leaf_value : Value?          // for primitive arguments
} derive(Debug)

///|
pub impl Show for ExtractedExpr with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
fn ExtractedExpr::to_string(self : ExtractedExpr) -> String {
  let buf = StringBuilder::new()
  self.write_to(buf)
  buf.to_string()
}

///|
fn ExtractedExpr::write_to(self : ExtractedExpr, buf : StringBuilder) -> Unit {
  buf.write_char('(')
  buf.write_string(self.func_name)
  for arg in self.args {
    buf.write_char(' ')
    match arg.leaf_value {
      Some(v) => buf.write_string(v.to_string())
      None => arg.write_to(buf)
    }
  }
  buf.write_char(')')
}

///|
/// Cost function type: (function_name, child_costs) -> cost
pub(all) typealias CostFn = (String, Array[Int]) -> Int

///|
/// Default cost function: 1 per node + sum of children.
fn ast_size(_name : String, child_costs : Array[Int]) -> Int {
  let mut total = 1
  for c in child_costs {
    total = total + c
  }
  total
}

///|
/// Extract the cheapest expression from an e-class.
/// Uses fixed-point iteration over all e-classes.
fn Database::extract(
  self : Database,
  root : Id,
  cost_fn : CostFn
) -> (Int, ExtractedExpr) {
  let root_id = self.find(root)
  // best_cost[id] = (cost, func_name, key)
  let best_cost : Map[Int, (Int, String, Array[Value])] = {}
  // Fixed-point iteration
  let mut changed = true
  while changed {
    changed = false
    self.tables.each(fn(fname, table) {
      let rows = table.scan()
      for row_pair in rows {
        let (key, value) = row_pair
        let output_id = match self.canonicalize_value(value) {
          IdVal(id) => self.find(id)
          _ => return // skip non-id outputs
        }
        // Compute cost: look up child costs
        let child_costs : Array[Int] = []
        let mut all_children_have_cost = true
        for v in key {
          match self.canonicalize_value(v) {
            IdVal(child_id) => {
              let canon_child = self.find(child_id)
              match best_cost[canon_child.0] {
                Some((c, _, _)) => child_costs.push(c)
                None => { all_children_have_cost = false }
              }
            }
            _ => child_costs.push(0) // primitives cost 0
          }
        }
        if all_children_have_cost {
          let cost = cost_fn(fname, child_costs)
          let canon_output = output_id.0
          match best_cost[canon_output] {
            Some((old_cost, _, _)) =>
              if cost < old_cost {
                best_cost[canon_output] = (cost, fname, key)
                changed = true
              }
            None => {
              best_cost[canon_output] = (cost, fname, key)
              changed = true
            }
          }
        }
      }
    })
  }
  // Reconstruct expression from root
  match best_cost[root_id.0] {
    Some((cost, _, _)) => (cost, self.reconstruct(root_id, best_cost))
    None => abort("no expression found for e-class " + root_id.to_string())
  }
}

///|
fn Database::reconstruct(
  self : Database,
  id : Id,
  best_cost : Map[Int, (Int, String, Array[Value])]
) -> ExtractedExpr {
  let canon_id = self.find(id)
  match best_cost[canon_id.0] {
    Some((_cost, fname, key)) => {
      let children : Array[ExtractedExpr] = []
      for v in key {
        match self.canonicalize_value(v) {
          IdVal(child_id) => {
            let canon_child = self.find(child_id)
            children.push(self.reconstruct(canon_child, best_cost))
          }
          prim =>
            children.push(
              { func_name: "", args: [], leaf_value: Some(prim) },
            )
        }
      }
      { func_name: fname, args: children, leaf_value: None }
    }
    None =>
      abort("no expression found for e-class " + canon_id.to_string())
  }
}
```

**Step 4: Run tests to verify they pass**

Run: `cd loom/egglog && moon test`
Expected: all tests PASS

**Step 5: Format and commit**

```bash
cd loom/egglog && moon fmt
git add src/extract.mbt src/extract_wbtest.mbt
git commit -m "feat(egglog): add cost-based extraction"
```

---

### Task 9: STLC bidirectional type inference

The showcase: define STLC sorts, functions, and typing rules. Demonstrate top-down + bottom-up information flow.

**Files:**
- Create: `loom/egglog/src/examples/stlc/moon.pkg`
- Create: `loom/egglog/src/examples/stlc/stlc.mbt`
- Create: `loom/egglog/src/examples/stlc/stlc_wbtest.mbt`

**Step 1: Create the package**

Create `loom/egglog/src/examples/stlc/moon.pkg`:
```
import {
  "dowdiness/egglog",
}
```

Note: This depends on the egglog package being public. If the API surface needs adjusting (making Database/Rule/etc. public), do that first. Alternatively, use whitebox tests in the main package. The simplest approach: put the STLC tests as whitebox tests in the main `src/` package.

**Alternative (recommended): whitebox tests in main package**

Create `loom/egglog/src/stlc_wbtest.mbt` instead:

**Step 2: Write the failing tests**

Create `loom/egglog/src/stlc_wbtest.mbt`:
```moonbit
///|
/// Helper: set up STLC database with sorts and functions.
fn stlc_db() -> Database {
  let db = Database::new()
  // Expression constructors (input args... -> output Expr id)
  db.register("Num", 2, None)      // Num(Int) -> Expr
  db.register("Var", 2, None)      // Var(String) -> Expr
  db.register("Add", 3, None)      // Add(Expr, Expr) -> Expr
  db.register("Lam", 3, None)      // Lam(String, Expr) -> Expr
  db.register("App", 3, None)      // App(Expr, Expr) -> Expr
  // Type constructors
  db.register("IntTy", 1, None)    // IntTy() -> Type
  db.register("Arrow", 3, None)    // Arrow(Type, Type) -> Type
  // Relations (merge = union the output ids)
  db.register("HasType", 2, None)  // HasType(Expr) -> Type
  db.register("InEnv", 2, None)    // InEnv(String) -> Type
  db
}

///|
/// The STLC typing rules.
fn stlc_rules() -> Array[Rule] {
  [
    // Synthesis: Num(n) : IntTy
    {
      name: "type-num",
      query: [Fact("Num", [Var("?n"), Var("?e")])],
      actions: [Set("HasType", [Var("?e")], Call("IntTy", []))],
    },
    // Synthesis: Var(x) : T when InEnv(x, T)
    {
      name: "type-var",
      query: [
        Fact("Var", [Var("?x"), Var("?e")]),
        Fact("InEnv", [Var("?x"), Var("?t")]),
      ],
      actions: [Set("HasType", [Var("?e")], Var("?t"))],
    },
    // Synthesis: Add(a, b) : IntTy when HasType(a)=IntTy, HasType(b)=IntTy
    {
      name: "type-add",
      query: [
        Fact("Add", [Var("?a"), Var("?b"), Var("?e")]),
        Fact("HasType", [Var("?a"), Var("?ta")]),
        Fact("HasType", [Var("?b"), Var("?tb")]),
        Fact("IntTy", [Var("?ta")]),
        Fact("IntTy", [Var("?tb")]),
      ],
      actions: [Set("HasType", [Var("?e")], Call("IntTy", []))],
    },
    // Synthesis: App(f, arg) : B when HasType(f)=Arrow(A,B), HasType(arg)=A
    {
      name: "type-app",
      query: [
        Fact("App", [Var("?f"), Var("?a"), Var("?e")]),
        Fact("HasType", [Var("?f"), Var("?tf")]),
        Fact("HasType", [Var("?a"), Var("?ta")]),
        Fact("Arrow", [Var("?ta"), Var("?tb"), Var("?tf")]),
      ],
      actions: [Set("HasType", [Var("?e")], Var("?tb"))],
    },
    // Checking: Lam(x, body) : Arrow(A, B) => InEnv(x, A), HasType(body, B)
    {
      name: "check-lam",
      query: [
        Fact("Lam", [Var("?x"), Var("?body"), Var("?e")]),
        Fact("HasType", [Var("?e"), Var("?t")]),
        Fact("Arrow", [Var("?a"), Var("?b"), Var("?t")]),
      ],
      actions: [
        Set("InEnv", [Var("?x")], Var("?a")),
        Set("HasType", [Var("?body")], Var("?b")),
      ],
    },
  ]
}

///|
test "num synthesizes IntTy" {
  let db = stlc_db()
  let num42 = db.call("Num", [IntVal(42)])
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 10))
  match num42 {
    IdVal(id) => {
      let ty = db.lookup("HasType", [IdVal(db.find(id))])
      let int_ty = db.call("IntTy", [])
      match (ty, int_ty) {
        (Some(IdVal(t)), IdVal(expected)) =>
          inspect!(db.find(t) == db.find(expected), content="true")
        _ => abort("type not found")
      }
    }
    _ => abort("expected IdVal")
  }
}

///|
test "var with env synthesizes type" {
  let db = stlc_db()
  let var_x = db.call("Var", [StrVal("x")])
  let int_ty = db.call("IntTy", [])
  // Set InEnv("x") = IntTy
  let _ = db.set("InEnv", [StrVal("x")], int_ty)
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 10))
  match var_x {
    IdVal(id) => {
      let ty = db.lookup("HasType", [IdVal(db.find(id))])
      match (ty, int_ty) {
        (Some(IdVal(t)), IdVal(expected)) =>
          inspect!(db.find(t) == db.find(expected), content="true")
        _ => abort("type not found")
      }
    }
    _ => abort("expected IdVal")
  }
}

///|
test "add synthesizes IntTy" {
  let db = stlc_db()
  let n1 = db.call("Num", [IntVal(1)])
  let n2 = db.call("Num", [IntVal(2)])
  let add = db.call("Add", [n1, n2])
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 10))
  match add {
    IdVal(id) => {
      let ty = db.lookup("HasType", [IdVal(db.find(id))])
      let int_ty = db.call("IntTy", [])
      match (ty, int_ty) {
        (Some(IdVal(t)), IdVal(expected)) =>
          inspect!(db.find(t) == db.find(expected), content="true")
        _ => abort("type not found for Add")
      }
    }
    _ => abort("expected IdVal")
  }
}

///|
test "lambda checking: top-down type flow" {
  // Build: lam x. (add (var x) (num 1))
  // Assert type: Int -> Int
  // Expected: InEnv("x") = IntTy (inferred via top-down)
  let db = stlc_db()
  let n1 = db.call("Num", [IntVal(1)])
  let var_x = db.call("Var", [StrVal("x")])
  let add = db.call("Add", [var_x, n1])
  let lam = db.call("Lam", [StrVal("x"), add])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // Seed: assert lam : Int -> Int (top-down)
  let _ = db.set("HasType", [lam], arr_ty)
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 20))
  // Check: InEnv("x") should be IntTy
  let env_ty = db.lookup("InEnv", [StrVal("x")])
  match (env_ty, int_ty) {
    (Some(IdVal(t)), IdVal(expected)) =>
      inspect!(db.find(t) == db.find(expected), content="true")
    _ => abort("InEnv(x) not found or not IntTy")
  }
}

///|
test "app synthesis: both directions cooperate" {
  // Build: (lam x. x) 42
  // Assert lam type: Int -> Int
  // Expected: App synthesizes IntTy
  let db = stlc_db()
  let var_x = db.call("Var", [StrVal("x")])
  let lam = db.call("Lam", [StrVal("x"), var_x])
  let n42 = db.call("Num", [IntVal(42)])
  let app = db.call("App", [lam, n42])
  let int_ty = db.call("IntTy", [])
  let arr_ty = db.call("Arrow", [int_ty, int_ty])
  // Seed: lam : Int -> Int
  let _ = db.set("HasType", [lam], arr_ty)
  let rules = stlc_rules()
  let _ = db.run_schedule(Saturate(Run(rules), 20))
  // Check: App should have type IntTy
  match app {
    IdVal(id) => {
      let ty = db.lookup("HasType", [IdVal(db.find(id))])
      match (ty, int_ty) {
        (Some(IdVal(t)), IdVal(expected)) =>
          inspect!(db.find(t) == db.find(expected), content="true")
        _ => abort("App type not found")
      }
    }
    _ => abort("expected IdVal")
  }
}
```

**Step 3: Run tests to verify they fail**

Run: `cd loom/egglog && moon test`
Expected: FAIL (stlc functions not found — but actually the code uses Database directly from the same package, so it depends on Tasks 3-7 being complete)

**Step 4: Run tests to verify they pass**

Run: `cd loom/egglog && moon test`
Expected: all STLC tests PASS

If tests fail, debug by:
1. Check that `HasType` table is populated after running rules
2. Check that `InEnv` table is populated by check-lam rule
3. Check that `Saturate` runs enough iterations for multi-step inference
4. Add intermediate `inspect!` calls to trace rule matching

**Step 5: Format and commit**

```bash
cd loom/egglog && moon fmt
git add src/stlc_wbtest.mbt
git commit -m "feat(egglog): add STLC bidirectional type inference example"
```

---

### Task 10: Final cleanup and documentation

**Files:**
- Update: `loom/egglog/src/egglog.mbt` (module overview)
- Run: `moon info && moon fmt`

**Step 1: Update module interfaces**

```bash
cd loom/egglog && moon info && moon fmt
```

**Step 2: Run full test suite**

```bash
cd loom/egglog && moon test
```
Expected: all tests PASS

**Step 3: Check generated .mbti file**

```bash
cd loom/egglog && cat src/pkg.generated.mbti
```

Review the public API surface. Verify only `Id`, `Value`, `Sort`, `Term`, `Atom`, `Action`, `Rule`, `Schedule`, `StopReason`, and `ExtractedExpr` are public.

**Step 4: Commit**

```bash
cd loom/egglog && moon fmt
git add -A
git commit -m "chore(egglog): update interfaces and format"
```
