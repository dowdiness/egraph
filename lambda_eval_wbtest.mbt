///|
/// Values the constant-folding lattice can represent.
enum ValLit {
  VInt(Int)
  VBool(Bool)
} derive(Eq, Show)

///|
/// Combined analysis data per e-class.
///
/// `fv`: free variables (sound over-approximation — set-union on merge).
/// `val`: known constant value if this e-class reduces to a literal.
struct EvalState {
  fv : @hashset.HashSet[String]
  val : ValLit?
}

///|
/// Copy all elements of `src` into `dst`.
fn fv_union(
  dst : @hashset.HashSet[String],
  src : @hashset.HashSet[String],
) -> Unit {
  for x in src {
    dst.add(x)
  }
}
