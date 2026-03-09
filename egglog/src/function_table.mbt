///|
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
/// Serialize a key array to a string for map lookup.
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
/// Insert a row. Returns the stored output value.
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
fn FunctionTable::lookup(self : FunctionTable, key : Array[Value]) -> Value? {
  self.rows.get(key_string(key))
}

///|
fn FunctionTable::row_count(self : FunctionTable) -> Int {
  self.rows.length()
}

///|
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
