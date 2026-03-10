///|
/// Small tests for the equality engine underneath the database.
test "fresh id finds itself" {
  let uf = UnionFind::new()
  let a = uf.make_set()
  inspect(uf.find(a), content="0")
}

///|
test "union makes find agree" {
  let uf = UnionFind::new()
  let a = uf.make_set()
  let b = uf.make_set()
  let _ = uf.union(a, b)
  inspect(uf.find(a) == uf.find(b), content="true")
}

///|
test "transitivity" {
  let uf = UnionFind::new()
  let a = uf.make_set()
  let b = uf.make_set()
  let c = uf.make_set()
  let _ = uf.union(a, b)
  let _ = uf.union(b, c)
  inspect(uf.find(a) == uf.find(c), content="true")
}

///|
test "size tracks elements" {
  let uf = UnionFind::new()
  let _ = uf.make_set()
  let _ = uf.make_set()
  let _ = uf.make_set()
  inspect(uf.size(), content="3")
}
