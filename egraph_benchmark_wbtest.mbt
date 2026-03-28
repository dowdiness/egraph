// Benchmarks for AnalyzedEGraph::rebuild.
//
// Two scales of a constant-folding e-graph are benchmarked:
//   small:  100 Num + 50 Add  → ~100 canonical classes → 100×100  = 10,000 iterations
//   large: 1000 Num + 500 Add → ~1000 canonical classes → 1000×1000 = 1,000,000 iterations
//
// After the initial rebuild, constant folding merges each Add(Num(i), Num(i+1))
// class into Num(2i+1). modify hooks fire on every subsequent rebuild but
// produce no-op unions (add() returns existing Id; union() is already merged).
//
// recompute_data always runs class_ids.length() relaxation passes (design
// concern #23). For a flat graph the fixed point is reached after 1 pass, so
// all remaining passes are redundant. Early termination (concern #23) would
// shrink O(n²) to O(n). Measured baseline:
//   small: ~738 µs  → early termination expected ~7 µs  (savings ~730 µs)
//   large: ~124 ms  → early termination expected ~124 µs (savings ~124 ms)
// The large benchmark makes the savings impossible to miss.
//
// Run with: moon bench --release

///|
/// Constant-folding analysis for TestLang (mirrors egraph_wbtest.mbt).
fn cf_analysis() -> Analysis[TestLang, Int?] {
  {
    make: fn(node, get_data) {
      match node {
        Num(n) => Some(n)
        Add(a, b) =>
          match (get_data(a), get_data(b)) {
            (Some(x), Some(y)) => Some(x + y)
            _ => None
          }
      }
    },
    merge: fn(a, b) {
      let result = match (a, b) {
        (Some(x), Some(y)) => if x == y { Some(x) } else { None }
        (Some(x), None) | (None, Some(x)) => Some(x)
        _ => None
      }
      (result, { a_changed: a != result, b_changed: b != result })
    },
    modify: fn(eg, id) {
      match eg.get_data(id) {
        Some(n) => eg.union(id, eg.add(Num(n))) |> ignore
        None => ()
      }
    },
  }
}

///|
/// Benchmark: rebuild on an already-saturated graph — small scale (100 classes).
///
/// Builds 100 Num nodes and 50 Add nodes, runs one rebuild to saturate
/// (constant folding merges Add classes into the corresponding Num classes),
/// then measures repeated rebuild calls on the stable graph. modify hooks
/// fire but produce only no-op unions — no new pending work is enqueued.
/// Baseline: ~738 µs. Expected after early termination (concern #23): ~7 µs.
test "rebuild: stable e-graph (100 classes)" (b : @bench.T) {
  let eg : AnalyzedEGraph[TestLang, Int?] = AnalyzedEGraph::new(cf_analysis())
  let nums : Array[Id] = []
  for i = 0; i < 100; i = i + 1 {
    nums.push(eg.add(Num(i)))
  }
  for i = 0; i < 50; i = i + 1 {
    let _ = eg.add(Add(nums[i], nums[i + 1]))
    ()
  }
  eg.rebuild()
  b.bench(fn() {
    eg.rebuild()
    b.keep(eg.size())
  })
}

///|
/// Benchmark: rebuild on an already-saturated graph — large scale (1000 classes).
///
/// Same structure as the small variant but 10× larger. recompute_data runs
/// 1000 passes × 1000 classes = 1M iterations per rebuild call. The harness
/// gets 10 single-call samples (~124 ms each); σ ≈ 3 ms. Early termination
/// (design concern #23) would exit after 1 pass, cutting time to ~124 µs —
/// a ~124 ms improvement that is unambiguous at 10 samples.
/// Baseline: ~124 ms. Expected after early termination: ~124 µs.
test "rebuild: stable e-graph (1000 classes)" (b : @bench.T) {
  let eg : AnalyzedEGraph[TestLang, Int?] = AnalyzedEGraph::new(cf_analysis())
  let nums : Array[Id] = []
  for i = 0; i < 1000; i = i + 1 {
    nums.push(eg.add(Num(i)))
  }
  for i = 0; i < 500; i = i + 1 {
    let _ = eg.add(Add(nums[i], nums[i + 1]))
    ()
  }
  eg.rebuild()
  b.bench(fn() {
    eg.rebuild()
    b.keep(eg.size())
  })
}

///|
/// Benchmark: full graph setup + one union + rebuild per iteration.
///
/// Each iteration builds a fresh e-graph (100 Num + 50 Add), runs one
/// rebuild to saturate, unions two previously-distinct classes, then
/// rebuilds again. Includes graph-construction overhead — this is not an
/// isolated rebuild measurement. See the stable benchmarks above for
/// pure recompute_data cost. Useful as an end-to-end reference.
/// Baseline: ~1.49 ms (dominated by construction + first rebuild).
test "rebuild: setup + one union + rebuild" (b : @bench.T) {
  b.bench(fn() {
    let eg : AnalyzedEGraph[TestLang, Int?] = AnalyzedEGraph::new(
      cf_analysis(),
    )
    let nums : Array[Id] = []
    for i = 0; i < 100; i = i + 1 {
      nums.push(eg.add(Num(i)))
    }
    for i = 0; i < 50; i = i + 1 {
      let _ = eg.add(Add(nums[i], nums[i + 1]))
      ()
    }
    eg.rebuild()
    eg.union(nums[0], nums[50]) |> ignore
    eg.rebuild()
    b.keep(eg.size())
  })
}
