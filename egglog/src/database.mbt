///|
/// The egglog database: a collection of function tables + union-find.
priv struct Database {
  uf : UnionFind
  tables : Map[String, FunctionTable]
  pending : Array[(Id, Id)]
  mut version : Int
}

///|
fn Database::new() -> Database {
  { uf: UnionFind::new(), tables: {}, pending: [], version: 0 }
}

///|
fn Database::alloc_id(self : Database) -> Id {
  self.uf.make_set()
}

///|
fn Database::find(self : Database, id : Id) -> Id {
  self.uf.find(id)
}

///|
fn Database::register(
  self : Database,
  name : String,
  merge? : ((Value, Value) -> Value)? = None,
) -> Unit {
  self.tables[name] = FunctionTable::new(merge)
}

///|
fn Database::canonicalize_value(self : Database, v : Value) -> Value {
  match v {
    IdVal(id) => IdVal(self.uf.find(id))
    _ => v
  }
}

///|
/// Canonicalize an array of values through the union-find.
fn Database::canon_args(self : Database, args : Array[Value]) -> Array[Value] {
  args.map(fn(v) { self.canonicalize_value(v) })
}

///|
/// Get a table by name, aborting if not found.
fn Database::get_table(self : Database, name : String) -> FunctionTable {
  match self.tables.get(name) {
    Some(t) => t
    None => abort("unknown function: " + name)
  }
}

///|
fn Database::call(self : Database, name : String, args : Array[Value]) -> Value {
  let table = self.get_table(name)
  let canon = self.canon_args(args)
  match table.lookup(canon) {
    Some(v) => self.canonicalize_value(v)
    None => {
      let output = IdVal(self.alloc_id())
      let _ = table.insert(canon, output)
      self.version = self.version + 1
      output
    }
  }
}

///|
fn Database::set(
  self : Database,
  name : String,
  args : Array[Value],
  value : Value,
) -> Value {
  let table = self.get_table(name)
  let canon = self.canon_args(args)
  let canon_val = self.canonicalize_value(value)
  match table.lookup(canon) {
    Some(old) => {
      let canon_old = self.canonicalize_value(old)
      if canon_old == canon_val {
        canon_old
      } else {
        match (canon_old, canon_val) {
          (IdVal(a), IdVal(b)) => {
            self.pending.push((a, b))
            self.version = self.version + 1
            table.insert(canon, canon_val)
          }
          _ =>
            match table.merge {
              Some(_) => {
                self.version = self.version + 1
                table.insert(canon, canon_val)
              }
              None => canon_old
            }
        }
      }
    }
    None => {
      let _ = table.insert(canon, canon_val)
      self.version = self.version + 1
      canon_val
    }
  }
}

///|
fn Database::union(self : Database, a : Id, b : Id) -> Unit {
  let ra = self.uf.find(a)
  let rb = self.uf.find(b)
  if ra == rb {
    return
  }
  self.pending.push((ra, rb))
  self.version = self.version + 1
}

///|
fn Database::rebuild(self : Database) -> Unit {
  while self.pending.length() > 0 {
    let batch = self.pending.copy()
    self.pending.clear()
    for pair in batch {
      let (a, b) = pair
      let _ = self.uf.union(a, b)
    }
    self.tables.each(fn(_name, table) { self.rebuild_table(table) })
  }
}

///|
fn Database::rebuild_table(self : Database, table : FunctionTable) -> Unit {
  let old_rows = table.scan()
  table.rows.clear()
  table.raw_keys.clear()
  for pair in old_rows {
    let (key, value) = pair
    let canon_key = self.canon_args(key)
    let canon_val = self.canonicalize_value(value)
    match table.lookup(canon_key) {
      Some(existing) => {
        let canon_existing = self.canonicalize_value(existing)
        if canon_existing != canon_val {
          match (canon_existing, canon_val) {
            (IdVal(a), IdVal(b)) => self.pending.push((a, b))
            _ => ()
          }
          let _ = table.insert(canon_key, canon_val)
        }
      }
      None => {
        let _ = table.insert(canon_key, canon_val)
      }
    }
  }
}

///|
fn Database::lookup(
  self : Database,
  name : String,
  args : Array[Value],
) -> Value? {
  let table = match self.tables.get(name) {
    Some(t) => t
    None => return None
  }
  let canon = self.canon_args(args)
  match table.lookup(canon) {
    Some(v) => Some(self.canonicalize_value(v))
    None => None
  }
}
