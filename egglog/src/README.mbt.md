# `egglog/src`

This package implements a small relational e-graph engine in MoonBit.

The core idea is:

- `call(name, args)` interns an application and returns an `IdVal` for its e-class.
- `set(name, args, value)` stores a functional fact.
- `union(a, b)` states that two e-classes are equal.
- `rebuild()` propagates those equalities through every table.

## Functional Table Semantics

Every registered table is treated as a function on canonicalized arguments.
That means the key is not the raw argument tuple you inserted, but the tuple
after every `IdVal` has been replaced by its current union-find representative.

For one canonical key, there are only three legal outcomes:

1. The outputs are canonically equal, so the duplicate row is ignored.
2. The outputs are both `IdVal`, so the engine unifies those e-classes.
3. The table has a merge function, so the merge function resolves the conflict.

If none of those apply, the program aborts. In particular, two different
primitive outputs for the same canonical key are an error for non-merged
tables. This avoids silent first-writer-wins behavior after equality collapse.

## Choosing Between A Function, A Merge Table, And A Relation

- Use `call` for constructors and pure function symbols that produce e-classes.
- Use `set` without `merge` when the symbol should be a partial function and
  conflicting primitive outputs indicate inconsistent facts.
- Use `set` with `merge` when conflicts are expected and there is a principled
  join operation.
- If you want multiple primitive outputs for the same key, model that as a
  relation instead of a functional table.

## Example: Constructors And Lookup

```mbt check
test "interning constructors returns one canonical row per key" {
  let db = Database::new()
  db.register("Num")
  let n1 = db.call("Num", [IntVal(7)])
  let n2 = db.call("Num", [IntVal(7)])
  assert_eq(n1, n2)
  assert_true(db.lookup("Num", [IntVal(7)]) is Some(_))
}
```

## Example: Merge Tables Resolve Primitive Conflicts

```mbt check
fn max_int_value(old : Value, new : Value) -> Value {
  match (old, new) {
    (IntVal(lhs), IntVal(rhs)) => IntVal(if lhs >= rhs { lhs } else { rhs })
    _ => old
  }
}

test "merge tables combine conflicting primitive outputs" {
  let db = Database::new()
  db.register("Score", merge=Some(max_int_value))
  let _ = db.set("Score", [StrVal("alice")], IntVal(3))
  let _ = db.set("Score", [StrVal("alice")], IntVal(5))
  assert_eq(db.lookup("Score", [StrVal("alice")]), Some(IntVal(5)))
}
```

## Example: Equality Collapse Can Reveal Conflicts

```mbt nocheck
let db = Database::new()
db.register("Num")
db.register("Color")

let red = db.call("Num", [IntVal(1)])
let blue = db.call("Num", [IntVal(2)])
let _ = db.set("Color", [red], StrVal("red"))
let _ = db.set("Color", [blue], StrVal("blue"))

// Once the two numbers become equal, both Color rows collapse to the same key.
// Because Color has no merge function and the primitive outputs disagree,
// rebuild aborts instead of silently choosing one.
match (red, blue) {
  (IdVal(a), IdVal(b)) => {
    db.union(a, b)
    db.rebuild()
  }
  _ => abort("expected ids")
}
```
