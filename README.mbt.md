# dowdiness/egraph

An equality graph (e-graph) library in MoonBit. E-graphs compactly represent many equivalent expressions and, combined with equality saturation, find the optimal rewrite without phase-ordering problems.

## Status

Peer library — production dependency of [`canopy`](https://github.com/dowdiness/canopy), declared as a path-dep in the parent's `moon.mod.json`:

```json
"dowdiness/egraph": { "path": "./loom/egraph", "version": "0.1.0" }
```

Not a research sandbox. Breaking changes flow through canopy's submodule pointer bumps; do not rename or delete public symbols without a paired canopy PR.

The working consumer lives at [`examples/lambda-opt/`](examples/lambda-opt/) — a lambda-calculus optimizer built on `egraph`. Treat it as the integration test for the public API: changes that break `lambda-opt` break canopy.

## Documentation

- [Introduction](docs/introduction.md) — what e-graphs are, when to use them, core concepts, quick start
- [Advanced Topics](docs/advanced/README.md) — IR design, conditional rewrites, analysis, growth control, cost functions, multi-language patterns, debugging
- [Design Concerns](docs/design-concerns.md) — deferred decisions with rationale
- [TODO](docs/TODO.md) — future work
