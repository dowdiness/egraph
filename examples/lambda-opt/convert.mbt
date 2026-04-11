// Conversion between @ast.Term and LambdaLang e-graph nodes.

///|
/// Recursively add an @ast.Term to an EGraph, returning the root e-class Id.
pub fn term_add(
  eg : @egraph.EGraph[LambdaLang],
  term : @ast.Term,
) -> @egraph.Id {
  match term {
    Int(n) => eg.add(LNum(n))
    Var(x) | Unbound(x) => eg.add(LVar(x))
    Lam(x, body) => {
      let b = term_add(eg, body)
      eg.add(LLam(x, b))
    }
    App(f, a) => {
      let fi = term_add(eg, f)
      let ai = term_add(eg, a)
      eg.add(LApp(fi, ai))
    }
    Bop(Plus, l, r) => {
      let li = term_add(eg, l)
      let ri = term_add(eg, r)
      eg.add(LAdd(li, ri))
    }
    Bop(Minus, l, r) => {
      let li = term_add(eg, l)
      let ri = term_add(eg, r)
      eg.add(LMinus(li, ri))
    }
    If(c, t, e) => {
      let ci = term_add(eg, c)
      let ti = term_add(eg, t)
      let ei = term_add(eg, e)
      eg.add(LIf(ci, ti, ei))
    }
    Module(defs, body) => {
      let mut result = term_add(eg, body)
      for i = defs.length() - 1; i >= 0; i = i - 1 {
        let (name, val) = defs[i]
        let val_id = term_add(eg, val)
        result = eg.add(LLet(name, val_id, result))
      }
      result
    }
    Unit | Error(_) | Hole(_) => eg.add(LNum(0))
  }
}

///|
/// Convert a RecExpr[LambdaLang] back to @ast.Term.
/// The RecExpr is a flat array of nodes; children use Ids indexing into the array.
pub fn rec_expr_to_term(rec : @egraph.RecExpr[LambdaLang]) -> @ast.Term {
  let nodes = rec.nodes
  // Build terms bottom-up: nodes[i] references earlier indices as children
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
