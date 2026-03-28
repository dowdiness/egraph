// Benchmarks for AnalyzedEGraph::rebuild.
//
// These benchmarks measure rebuild cost on a constant-folding e-graph
// built from 100 Num nodes and 50 Add nodes. After the initial rebuild,
// constant folding merges each Add(Num(i), Num(i+1)) class into Num(2i+1),
// leaving ~100 canonical live classes (50 odd Num classes absorb the 50 Add
// classes; even Num classes remain separate).
//
// modify hooks run on every rebuild call but produce no-op unions on a
// saturated graph — add() returns an existing Id, union() finds the classes
// already merged, and no pending work is enqueued.
//
// These numbers serve as the baseline for design concern #23
// (recompute_data early termination).
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
