///|
/// Low-level storage for one functional symbol.
///
/// Each table maps canonicalized input tuples to exactly one output value.
/// Conflict policy lives here: duplicate rows are ignored, merge tables combine
/// competing values, and plain tables leave conflict detection to higher-level
/// database logic.
/// A function table: maps input tuples to output values.
/// Arity includes the output column (e.g., Add(Expr, Expr) -> Expr has arity 3).
priv struct FunctionTable {
  rows : Map[String, Value]
  raw_keys : Map[String, Array[Value]]
  merge : ((Value, Value) -> Value)?
}

///|
fn FunctionTable::new(merge : ((Value, Value) -> Value)?) -> FunctionTable {
  { rows: {}, raw_keys: {}, merge }
}

///|
/// Serialize a key array to a stable string for map lookup.
///
/// The NUL separator prevents accidental collisions between adjacent printed
/// values such as `["ab", "c"]` and `["a", "bc"]`.
fn key_string(key : Array[Value]) -> String {
  let buf = StringBuilder::new()
  for i, v in key {
    if i > 0 {
      buf.write_char('\u0000')
    }
    buf.write_string(v.to_string())
  }
  buf.to_string()
}

///|
/// Insert or merge one row.
///
/// Returns `(stored_value, changed)` where `changed` tells callers whether the
/// table's semantic content changed. That signal feeds scheduling and rebuild.
fn FunctionTable::insert(
  self : FunctionTable,
  key : Array[Value],
  value : Value,
) -> (Value, Bool) {
  let ks = key_string(key)
  match self.rows.get(ks) {
    Some(old) =>
      if old == value {
        (old, false)
      } else {
        match self.merge {
          Some(f) => {
            let merged = f(old, value)
            if merged == old {
              (old, false)
            } else {
              self.rows[ks] = merged
              (merged, true)
            }
          }
          None => (old, false)
        }
      }
    None => {
      self.rows[ks] = value
      self.raw_keys[ks] = key
      (value, true)
    }
  }
}

///|
/// Look up the output for one canonical key.
fn FunctionTable::lookup(self : FunctionTable, key : Array[Value]) -> Value? {
  self.rows.get(key_string(key))
}

///|
/// Count materialized rows in the table.
#warnings("-unused_value")
fn FunctionTable::row_count(self : FunctionTable) -> Int {
  self.rows.length()
}

///|
/// Scan every row while recovering the original structured key.
///
/// `rows` stores only serialized keys for indexing, so `raw_keys` keeps a copy
/// that higher layers can rebuild and pattern-match against.
fn FunctionTable::scan(self : FunctionTable) -> Array[(Array[Value], Value)] {
  let result : Array[(Array[Value], Value)] = []
  self.rows.each(fn(ks, v) {
    match self.raw_keys.get(ks) {
      Some(key) => result.push((key, v))
      None => ()
    }
  })
  result
}
