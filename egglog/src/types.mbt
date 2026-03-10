///|
/// Core runtime values shared by the whole package.
///
/// `IdVal` points at an e-class managed by union-find. Primitive cases are the
/// leaves that can appear in tables without introducing a new equivalence class.
/// A value in the egglog database. Either an e-class Id or a primitive.
pub(all) enum Value {
  IdVal(Id)
  IntVal(Int)
  StrVal(String)
} derive(Eq, Hash, Compare, Show, Debug)

///|
/// Column metadata for future schema-aware table definitions.
///
/// The current prototype does not enforce sorts yet, but keeping the concept in
/// the surface language makes later validation and optimization easier to add.
/// Sort (type) of a column in a function table.
pub(all) enum Sort {
  EqSort(String)
  PrimitiveSort(String)
} derive(Eq, Hash, Show, Debug)
