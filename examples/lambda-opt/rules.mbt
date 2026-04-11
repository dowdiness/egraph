// Rewrite rules for lambda calculus optimization.

///|
/// Arithmetic identity rules: x+0→x, 0+x→x, x-0→x.
pub fn arith_rules() -> Array[@egraph.Rewrite] raise {
  [
    @egraph.rewrite("add-0", "(Add ?x (Num:0))", "?x"),
    @egraph.rewrite("0-add", "(Add (Num:0) ?x)", "?x"),
    @egraph.rewrite("sub-0", "(Minus ?x (Num:0))", "?x"),
  ]
}
