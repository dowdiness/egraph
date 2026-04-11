///|
test "optimize: literal unchanged" {
  let result = optimize(@ast.Term::Int(42))
  inspect(result, content="Int(42)")
}

///|
test "optimize: constant fold 2 + 3 = 5" {
  let term = @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3))
  let result = optimize(term)
  inspect(result, content="Int(5)")
}

///|
test "optimize: identity x + 0 = x" {
  let term = @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(0))
  let result = optimize(term)
  inspect(result, content="Var(\"x\")")
}

///|
test "optimize: identity 0 + x = x" {
  let term = @ast.Term::Bop(Plus, @ast.Term::Int(0), @ast.Term::Var("x"))
  let result = optimize(term)
  inspect(result, content="Var(\"x\")")
}

///|
test "optimize: identity x - 0 = x" {
  let term = @ast.Term::Bop(Minus, @ast.Term::Var("x"), @ast.Term::Int(0))
  let result = optimize(term)
  inspect(result, content="Var(\"x\")")
}

///|
test "optimize: beta reduction (λx. x + 1) 5 = 6" {
  let term = @ast.Term::App(
    @ast.Term::Lam(
      "x",
      @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Int(1)),
    ),
    @ast.Term::Int(5),
  )
  let result = optimize(term)
  inspect(result, content="Int(6)")
}

///|
test "optimize: let binding preserved (let-inlining is future work)" {
  // Let-inlining requires LLet → LApp(LLam(...)) desugaring or
  // dedicated let-substitution rules. Currently the optimizer preserves
  // let bindings structurally; constant folding only fires on arithmetic.
  let term = @ast.Term::Module(
    [("x", @ast.Term::Int(2))],
    @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("x")),
  )
  let result = optimize(term)
  inspect(
    result,
    content="Module([(\"x\", Int(2))], Bop(Plus, Var(\"x\"), Var(\"x\")))",
  )
}

///|
test "optimize: nested (2 + 3) + (4 - 1) = 8" {
  let term = @ast.Term::Bop(
    Plus,
    @ast.Term::Bop(Plus, @ast.Term::Int(2), @ast.Term::Int(3)),
    @ast.Term::Bop(Minus, @ast.Term::Int(4), @ast.Term::Int(1)),
  )
  let result = optimize(term)
  inspect(result, content="Int(8)")
}

///|
test "optimize: free variable preserved" {
  let term = @ast.Term::Bop(Plus, @ast.Term::Var("x"), @ast.Term::Var("y"))
  let result = optimize(term)
  inspect(result, content="Bop(Plus, Var(\"x\"), Var(\"y\"))")
}
