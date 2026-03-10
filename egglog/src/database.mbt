///|
/// Mutable relational e-graph state.
///
/// The database is the bridge between relational storage and equality
/// reasoning: function tables hold rows, union-find holds equivalence classes,
/// and `pending` remembers unions that still need to be propagated.
/// The egglog database: a collection of function tables + union-find.
pub struct Database {
  priv uf : UnionFind
  priv tables : Map[String, FunctionTable]
  priv pending : Array[(Id, Id)]
  priv mut version : Int
}

///|
pub fn Database::new() -> Database {
  { uf: UnionFind::new(), tables: {}, pending: [], version: 0 }
}

///|
fn Database::alloc_id(self : Database) -> Id {
  self.uf.make_set()
}

///|
/// Canonical representative lookup for one e-class id.
pub fn Database::find(self : Database, id : Id) -> Id {
  self.uf.find(id)
}

///|
/// Register a functional table.
///
/// Tables are keyed by canonicalized arguments. Without a merge function, a
/// table behaves like a partial function: each canonical key may have at most
/// one canonical output. Provide `merge` only when conflicting primitive
/// outputs should be combined rather than rejected.
pub fn Database::register(
  self : Database,
  name : String,
  merge? : ((Value, Value) -> Value)? = None,
) -> Unit {
  self.tables[name] = FunctionTable::new(merge)
}

///|
/// Rewrite one value through the current union-find state.
///
/// Primitive values are already canonical, while `IdVal` changes whenever the
/// underlying e-class has been merged.
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
/// Intern a constructor application.
///
/// `call` is the "make an e-node" operation: it returns an existing output if
/// the canonical input tuple was seen before, otherwise it allocates a fresh
/// e-class for this application.
pub fn Database::call(
  self : Database,
  name : String,
  args : Array[Value],
) -> Value {
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
/// Set the output for a functional table row.
///
/// Semantics:
/// - same canonical key + same canonical value: no-op
/// - same canonical key + two `IdVal`s: enqueue a union
/// - same canonical key + primitive conflict + merge fn: resolve with merge
/// - same canonical key + primitive conflict + no merge fn: abort
pub fn Database::set(
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
            let (stored, _) = table.insert(canon, canon_val)
            stored
          }
          _ =>
            match table.merge {
              Some(_) => {
                let (stored, changed) = table.insert(canon, canon_val)
                if changed {
                  self.version = self.version + 1
                }
                stored
              }
              None =>
                abort(
                  "conflicting outputs for " +
                  name +
                  " on " +
                  canon.to_string() +
                  ": " +
                  canon_old.to_string() +
                  " vs " +
                  canon_val.to_string(),
                )
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
/// Request that two e-classes become equal on the next rebuild.
///
/// Union is batched so several rule firings can accumulate before tables are
/// re-canonicalized.
pub fn Database::union(self : Database, a : Id, b : Id) -> Unit {
  let ra = self.uf.find(a)
  let rb = self.uf.find(b)
  if ra == rb {
    return
  }
  self.pending.push((ra, rb))
  self.version = self.version + 1
}

///|
/// Rebuild all tables after pending unions.
///
/// Rebuild re-canonicalizes every stored row. If two rows collapse to the same
/// canonical key, the same functional-table semantics used by `set` apply
/// again: `IdVal` outputs unify, merge tables resolve conflicts, and non-merge
/// primitive conflicts abort.
pub fn Database::rebuild(self : Database) -> Unit {
  while self.pending.length() > 0 {
    let batch = self.pending.copy()
    self.pending.clear()
    for pair in batch {
      let (a, b) = pair
      let _ = self.uf.union(a, b)
    }
    self.tables.each(fn(name, table) { self.rebuild_table(name, table) })
  }
}

///|
/// Reinsert a table under current canonical representatives.
///
/// This is where equality collapse can turn previously distinct rows into a
/// conflict on the same canonical key.
fn Database::rebuild_table(
  self : Database,
  name : String,
  table : FunctionTable,
) -> Unit {
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
            (IdVal(a), IdVal(b)) => {
              self.pending.push((a, b))
              let _ = table.insert(canon_key, canon_val)
            }
            _ =>
              match table.merge {
                Some(_) => {
                  let _ = table.insert(canon_key, canon_val)
                }
                None =>
                  abort(
                    "conflicting outputs for " +
                    name +
                    " on " +
                    canon_key.to_string() +
                    ": " +
                    canon_existing.to_string() +
                    " vs " +
                    canon_val.to_string(),
                  )
              }
          }
        }
      }
      None => {
        let _ = table.insert(canon_key, canon_val)
      }
    }
  }
}

///|
/// Look up a row after canonicalizing the arguments first.
///
/// This gives callers the logical answer for the current e-graph state rather
/// than the answer for some stale pre-rebuild representative.
pub fn Database::lookup(
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
