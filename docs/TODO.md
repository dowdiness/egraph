# E-Graph Module TODOs

## Implementation Progress

- [x] Step 1: Union-Find
- [x] Step 2: EGraph core (add, union, rebuild)
- [x] Step 3: E-Matching (ENodeRepr, Pat, ematch, search, instantiate)
- [x] Step 4: Rewrite Rules (Rewrite, apply_rewrite)
- [x] Step 5: Extraction (CostFn, RecExpr, extract)
- [x] Step 6: Runner (equality saturation loop)
- [x] Step 7: lambda-opt example
- [x] Step 8: E-Class Analysis

## Future Work

### API Design

- [ ] **Pattern helper functions**: Add `var()`, `node()`, `atom()` constructors for programmatic Pat building without s-expression parsing
- [ ] **Labelled arguments for `rewrite()`**: Use `rewrite(name~, lhs~, rhs~)` to prevent parameter transposition
- [ ] **Richer `apply_rewrite` return type**: Consider struct/enum with match count, filtered count, and union count instead of raw `Int`

### Missing Features (vs egg)

#### High Priority

- [ ] **Explanations / Proof Production**: Produce `Explanation`, `TreeExplanation`, `FlatExplanation` that explain *why* two terms are equivalent — which rewrite rules or congruence steps were used. Essential for debugging and formal verification.
- [ ] **Multi-pattern rules**: Rules that match multiple patterns simultaneously across different e-classes (e.g., "if A=B AND C=D, then E=F"). egg's `MultiPattern`.
- [ ] **Rewrite Scheduling**: `BackoffScheduler` (exponential backoff for unproductive rules), `SimpleScheduler`, and a `RewriteScheduler` trait for custom strategies. Currently every rule runs every iteration.
- [ ] **LP-based Extraction**: Integer linear programming extraction (`LpExtractor`) for globally optimal results, vs current greedy fixed-point which can get stuck in local optima.

#### Medium Priority

- [ ] **`AstDepth` cost function**: Measure maximum AST depth (complement to existing `ast_size`).
- [ ] **DOT visualization**: Built-in GraphViz DOT output for e-graphs (egg's `Dot` wrapper).
- [ ] **`LanguageMapper`**: Cross-language e-graph translation — convert between different Language types.
- [ ] **Language definition macro/codegen**: Equivalent of egg's `define_language!` macro to auto-derive `ENode`/`ENodeRepr` from an enum, reducing boilerplate.
- [ ] **`Iteration` statistics**: Per-iteration stats in Runner (time, match count, union count, e-class count) and a `Report` summary.
- [ ] **`SearchMatches` struct**: Structured match results with metadata instead of raw `Array[(Id, Subst)]`.

#### Lower Priority

- [ ] **`Symbol` (interned strings)**: String interning for efficient variable/operator name comparison.
- [ ] **Analysis merge helpers**: `merge_max`, `merge_min`, `merge_option` utility functions for common analysis merge patterns.
- [ ] **`DidMerge` tracking**: Fine-grained tracking of whether a union actually changed the e-graph (useful for scheduling and termination).
- [ ] **Time limit in Runner**: Requires cross-platform clock support in MoonBit.
- [ ] **Dynamic rewrite generation**: Custom `Applier` implementations that compute right-hand sides programmatically, beyond pattern-based rewrites.
- [ ] **Serialization**: Serialize/deserialize e-graphs for persistence and debugging.

### Performance

- [ ] **`merge_substs` allocation**: Replace `a_map.copy()` with mutable substitution + backtracking or persistent map with structural sharing
- [ ] **`ematch` array allocations**: Pre-allocate buffers or use stack-based approach instead of fresh `Array[Subst]` per recursion level
- [ ] **`search` visited set**: Evaluate whether `HashSet` dedup is needed if `search` is always called post-rebuild
- [ ] **Benchmark suite**: Add benchmarks for `add` throughput, `rebuild` scaling, `ematch` per rule, saturation time (Step 7)
- [ ] **Extraction: Dijkstra worklist**: Replace full-scan fixed-point with priority-queue approach for O(n log n) extraction
- [ ] **Extraction: lazy map_children**: Avoid materializing canonical nodes until cost improves, reducing N×P allocations
- [ ] **Extraction: array-indexed costs**: Replace `Map[Id, Int]` with `Array[Int?]` for O(1) dense-integer lookup
- [ ] **`recompute_data` early termination**: Track whether data changed per pass and break when stable, avoiding O(n) worst-case passes
- [ ] **Pat::parse error positions**: Include character offset in error messages for easier debugging
