// Benchmarks for AnalyzedEGraph::rebuild.
//
// These benchmarks isolate the steady-state rebuild cost and the one-union
// incremental rebuild cost on a 150-class constant-folding e-graph.
// They serve as a baseline for future optimisations to recompute_data
// (design concern #23: early termination).
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
/// Benchmark: rebuild on an already-saturated large e-graph.
///
/// Builds 100 Num nodes and 50 Add nodes, saturates fully, then measures
/// repeated rebuild calls. All classes are stable — no modify calls are
/// needed. This is the hot steady-state path that recompute_data early
/// termination (design concern #23) would most improve.
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
/// Benchmark: rebuild after one union in a large stable e-graph.
///
/// Same 150-class saturated e-graph. Each iteration unions two distinct
/// classes then calls rebuild. This measures the incremental rebuild cost
/// and is the scenario where DidMerge-aware modify would theoretically help —
/// but recompute_data still dominates.
test "rebuild: one union in large e-graph" (b : @bench.T) {
  let eg : AnalyzedEGraph[TestLang, Int?] = AnalyzedEGraph::new(cf_analysis())
  let nums : Array[Id] = []
  for i = 0; i < 100; i = i + 1 {
    nums.push(eg.add(Num(i)))
  }
  let adds : Array[Id] = []
  for i = 0; i < 50; i = i + 1 {
    adds.push(eg.add(Add(nums[i], nums[i + 1])))
  }
  eg.rebuild()
  let mut counter = 0
  b.bench(fn() {
    let i = counter % 49
    counter = counter + 1
    eg.union(nums[i], adds[i]) |> ignore
    eg.rebuild()
    b.keep(eg.size())
  })
}
