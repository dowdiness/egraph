///|
/// The egglog database: a collection of function tables + union-find.
priv struct Database {
  uf : UnionFind
  tables : Map[String, FunctionTable]
  pending : Array[(Id, Id)]
}

///|
fn Database::new() -> Database {
  { uf: UnionFind::new(), tables: {}, pending: [] }
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
  arity : Int,
  merge : ((Value, Value) -> Value)?,
) -> Unit {
  self.tables[name] = FunctionTable::new(name, arity, merge)
}

///|
fn Database::canonicalize_value(self : Database, v : Value) -> Value {
  match v {
    IdVal(id) => IdVal(self.uf.find(id))
    _ => v
  }
}

///|
fn Database::call(self : Database, name : String, args : Array[Value]) -> Value {
  let table = match self.tables.get(name) {
    Some(t) => t
    None => abort("unknown function: " + name)
  }
  let canon_args : Array[Value] = args.map(fn(v) { self.canonicalize_value(v) })
  match table.lookup(canon_args) {
    Some(v) => self.canonicalize_value(v)
    None => {
      let output = IdVal(self.alloc_id())
      let _ = table.insert(canon_args, output)
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
  let table = match self.tables.get(name) {
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
      let _ = table.insert(canon_args, canon_val)
      canon_val
    }
  }
}

///|
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
  let canon_args : Array[Value] = args.map(fn(v) { self.canonicalize_value(v) })
  match table.lookup(canon_args) {
    Some(v) => Some(self.canonicalize_value(v))
    None => None
  }
}
