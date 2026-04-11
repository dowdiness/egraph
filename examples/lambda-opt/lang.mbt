// Lambda calculus e-node language for equality saturation optimization.

///|
pub enum LambdaLang {
  LNum(Int)
  LVar(String)
  LAdd(@egraph.Id, @egraph.Id)
  LMinus(@egraph.Id, @egraph.Id)
  LLam(String, @egraph.Id)
  LApp(@egraph.Id, @egraph.Id)
  LLet(String, @egraph.Id, @egraph.Id)
  LIf(@egraph.Id, @egraph.Id, @egraph.Id)
  LSubst(String, @egraph.Id, @egraph.Id) // internal: explicit substitution
} derive(Eq, Hash, Debug)

///|
pub impl Show for LambdaLang with output(self, logger) {
  logger.write_string(@debug.to_string(self))
}

///|
pub impl @egraph.ENode for LambdaLang with arity(self) {
  match self {
    LNum(_) | LVar(_) => 0
    LLam(_, _) => 1
    LAdd(_, _) | LMinus(_, _) | LApp(_, _) | LSubst(_, _, _) | LLet(_, _, _) =>
      2
    LIf(_, _, _) => 3
  }
}

///|
pub impl @egraph.ENode for LambdaLang with child(self, i) {
  match self {
    LAdd(a, b) | LMinus(a, b) | LApp(a, b) => if i == 0 { a } else { b }
    LLam(_, body) => body
    LLet(_, value, body) | LSubst(_, value, body) =>
      if i == 0 {
        value
      } else {
        body
      }
    LIf(c, t, e) => if i == 0 { c } else if i == 1 { t } else { e }
    _ => abort("no children")
  }
}

///|
pub impl @egraph.ENode for LambdaLang with map_children(self, f) {
  match self {
    LNum(_) | LVar(_) => self
    LAdd(a, b) => LAdd(f(a), f(b))
    LMinus(a, b) => LMinus(f(a), f(b))
    LApp(a, b) => LApp(f(a), f(b))
    LLam(name, body) => LLam(name, f(body))
    LLet(name, value, body) => LLet(name, f(value), f(body))
    LSubst(name, value, expr) => LSubst(name, f(value), f(expr))
    LIf(c, t, e) => LIf(f(c), f(t), f(e))
  }
}

///|
pub impl @egraph.ENodeRepr for LambdaLang with op_tag(self) {
  match self {
    LNum(_) => "Num"
    LVar(_) => "Var"
    LAdd(_, _) => "Add"
    LMinus(_, _) => "Minus"
    LLam(_, _) => "Lam"
    LApp(_, _) => "App"
    LLet(_, _, _) => "Let"
    LIf(_, _, _) => "If"
    LSubst(_, _, _) => "Subst"
  }
}

///|
pub impl @egraph.ENodeRepr for LambdaLang with payload(self) {
  match self {
    LNum(n) => Some(n.to_string())
    LVar(name) | LLam(name, _) | LLet(name, _, _) | LSubst(name, _, _) =>
      Some(name)
    _ => None
  }
}

///|
pub impl @egraph.ENodeRepr for LambdaLang with from_op(tag, payload, children) {
  match (tag, payload, children.length()) {
    ("Num", Some(s), 0) => Some(LNum(@string.parse_int(s))) catch { _ => None }
    ("Var", Some(s), 0) => Some(LVar(s))
    ("Add", None, 2) => Some(LAdd(children[0], children[1]))
    ("Minus", None, 2) => Some(LMinus(children[0], children[1]))
    ("App", None, 2) => Some(LApp(children[0], children[1]))
    ("Lam", Some(name), 1) => Some(LLam(name, children[0]))
    ("Let", Some(name), 2) => Some(LLet(name, children[0], children[1]))
    ("If", None, 3) => Some(LIf(children[0], children[1], children[2]))
    ("Subst", Some(name), 2) => Some(LSubst(name, children[0], children[1]))
    _ => None
  }
}
