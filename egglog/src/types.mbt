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
  EqSort(String)
  PrimitiveSort(String)
} derive(Eq, Hash, Show, Debug)
