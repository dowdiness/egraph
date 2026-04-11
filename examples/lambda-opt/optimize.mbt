// Tier 3: EGraph-based algebraic optimizer for lambda calculus.
//
// Takes a Term, runs equality saturation with arithmetic identity rules
// and analysis-driven beta reduction + constant folding, then extracts
// the cheapest equivalent expression.

///|
/// Optimize a lambda calculus term via equality saturation.
///
/// Applies arithmetic identities (x+0→x, 0+x→x, x-0→x) and
/// analysis-driven constant folding + beta reduction. Returns the
/// simplest equivalent term by AST size.
pub fn optimize(term : @ast.Term) -> @ast.Term {
  let analyzed = @egraph.AnalyzedEGraph::new(eval_analysis())
  let root = analyzed_term_add(analyzed, term)
  analyzed.rebuild()
  let rules = arith_rules() catch { _ => [] }
  let runner = @egraph.Runner::new(
    analyzed.egraph,
    roots=[root],
    node_limit=5000,
  )
  let _ = runner.run(rules)
  analyzed.rebuild()
  let (_, rec) = analyzed.extract(root, @egraph.ast_size())
  rec_expr_to_term(rec)
}

///|
/// Add a Term to an AnalyzedEGraph (with analysis tracking).
fn analyzed_term_add(
  eg : @egraph.AnalyzedEGraph[LambdaLang, EvalState],
  term : @ast.Term,
) -> @egraph.Id {
  match term {
    Int(n) => eg.add(LNum(n))
    Var(x) | Unbound(x) => eg.add(LVar(x))
    Lam(x, body) => {
      let b = analyzed_term_add(eg, body)
      eg.add(LLam(x, b))
    }
    App(f, a) => {
      let fi = analyzed_term_add(eg, f)
      let ai = analyzed_term_add(eg, a)
      eg.add(LApp(fi, ai))
    }
    Bop(Plus, l, r) => {
      let li = analyzed_term_add(eg, l)
      let ri = analyzed_term_add(eg, r)
      eg.add(LAdd(li, ri))
    }
    Bop(Minus, l, r) => {
      let li = analyzed_term_add(eg, l)
      let ri = analyzed_term_add(eg, r)
      eg.add(LMinus(li, ri))
    }
    If(c, t, e) => {
      let ci = analyzed_term_add(eg, c)
      let ti = analyzed_term_add(eg, t)
      let ei = analyzed_term_add(eg, e)
      eg.add(LIf(ci, ti, ei))
    }
    Module(defs, body) => {
      let mut result = analyzed_term_add(eg, body)
      for i = defs.length() - 1; i >= 0; i = i - 1 {
        let (name, val) = defs[i]
        let val_id = analyzed_term_add(eg, val)
        result = eg.add(LLet(name, val_id, result))
      }
      result
    }
    Unit | Error(_) | Hole(_) => eg.add(LNum(0))
  }
}
