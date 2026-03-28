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
// shrink O(n²) to O(n). The large-scale benchmark makes that gap measurable:
// a 2 µs improvement at small scale becomes ~200 µs at large scale.
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
/// Benchmark: rebuild on an already-saturated graph (steady-state).
///
/// Builds 100 Num nodes and 50 Add nodes, runs one rebuild to saturate
/// (constant folding merges Add classes into the corresponding Num classes),
/// then measures repeated rebuild calls on the stable graph. modify hooks
/// fire but produce only no-op unions — no new pending work is enqueued.
/// This is the hot steady-state path that recompute_data early termination
/// (design concern #23) would most improve.
test "rebuild: stable large e-graph — all classes already saturated" (
  b : @bench.T,
) {
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
/// Benchmark: rebuild on a large saturated graph (scale variant, 1000 classes).
///
/// Same structure as the small stable benchmark but 10× larger: 1000 Num nodes
/// and 500 Add nodes. recompute_data runs 1000 passes × 1000 classes = 1M
/// iterations per rebuild call. Early termination (design concern #23) would
/// exit after 1 pass — reducing this to 1000 iterations and making the speedup
/// detectable above the noise floor. Use this benchmark to verify that any
/// recompute_data optimisation actually works at scale.
test "rebuild: stable 1000-class e-graph (scale benchmark)" (b : @bench.T) {
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
/// Benchmark: full setup + one union + rebuild per iteration.
///
/// Each iteration builds a fresh 150-slot e-graph (100 Num + 50 Add),
/// saturates it with one rebuild, then unions Num(0) with Num(50) and
/// calls rebuild again. Measures the incremental rebuild cost on a graph
/// with one newly dirtied class. Includes graph-construction overhead;
/// see the stable benchmark for pure steady-state rebuild cost.
test "rebuild: one union in large e-graph" (b : @bench.T) {
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
