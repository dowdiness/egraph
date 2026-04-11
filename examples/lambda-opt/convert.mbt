// Conversion from RecExpr[LambdaLang] back to @ast.Term.

///|
/// Convert a RecExpr[LambdaLang] back to @ast.Term.
/// The RecExpr is a flat array of nodes; children use Ids indexing into the array.
pub fn rec_expr_to_term(rec : @egraph.RecExpr[LambdaLang]) -> @ast.Term {
  let nodes = rec.nodes
  let terms : Array[@ast.Term] = []
  for node in nodes {
    let term = match node {
      LNum(n) => @ast.Term::Int(n)
      LVar(x) => @ast.Term::Var(x)
      LAdd(a, b) => @ast.Term::Bop(Plus, terms[a.0], terms[b.0])
      LMinus(a, b) => @ast.Term::Bop(Minus, terms[a.0], terms[b.0])
      LLam(x, body) => @ast.Term::Lam(x, terms[body.0])
      LApp(f, a) => @ast.Term::App(terms[f.0], terms[a.0])
      LLet(x, v, body) => @ast.Term::Module([(x, terms[v.0])], terms[body.0])
      LIf(c, t, e) => @ast.Term::If(terms[c.0], terms[t.0], terms[e.0])
      LSubst(_, _, _) =>
        abort("LSubst should not appear in extracted expression")
    }
    terms.push(term)
  }
  terms[terms.length() - 1]
}
