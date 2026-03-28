// Benchmarks for AnalyzedEGraph::rebuild.
//
// Two scales of a constant-folding e-graph are benchmarked:
//   small:  100 Num + 50 Add  → ~100 canonical classes
//   large: 1000 Num + 500 Add → ~1000 canonical classes
//
// After the initial rebuild, constant folding merges each Add(Num(i), Num(i+1))
// class into Num(2i+1). modify hooks fire on every subsequent rebuild but
// produce no-op unions (add() returns existing Id; union() is already merged).
//
// Optimization history (stable 1000-class benchmark):
//   pre-#23 (no early termination): ~124 ms — 1000 passes × 1000 classes = 1M ops
//   post-#23 (early termination):    ~338 µs — exits after 1 pass for flat graphs
//   post-#26 (scratch map + swap):   ~264 µs — eliminates per-pass alloc + copy-back
//
// Isolation microbenchmark confirms the alloc+copy overhead was ~81 µs
// (24% of the pre-#26 stable cost). The scratch swap saves ~74 µs in practice.
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
/// Post-#23 baseline: ~20 µs. Post-#26 (scratch swap): ~17 µs.
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
/// Same structure as the small variant but 10× larger.
/// Post-#23 baseline (early termination, 1 pass): ~338 µs.
/// Post-#26 (scratch map + O(1) swap): ~264 µs — saves ~74 µs (22%).
/// The 22% reduction matches the isolation microbenchmark's ~81 µs alloc cost.
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
/// Post-#23 baseline: ~119 µs. Post-#26: ~112 µs.
test "rebuild: setup + one union + rebuild" (b : @bench.T) {
  b.bench(fn() {
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
    eg.union(nums[0], nums[50]) |> ignore
    eg.rebuild()
    b.keep(eg.size())
  })
}

///|
/// Microbenchmark: isolate the OLD map-swap pattern (pre-#26 baseline).
///
/// Measures the per-pass cost before the scratch optimization: allocate a
/// fresh Map[Id, Int?], populate it, clear the live map, copy entries back.
/// This quantifies the allocation overhead that concern #26 targeted.
/// Result: ~81 µs (24% of the pre-#26 stable 1000-class cost of ~338 µs).
/// After the fix, recompute_data uses scratch.clear() + populate + O(1) swap,
/// saving ~74 µs per stable rebuild (matches isolation cost, as expected).
test "isolate: map alloc + populate + swap at 1000 entries" (b : @bench.T) {
  // Pre-build a realistic set of Id keys (same as a 1000-class e-graph)
  let ids : Array[Id] = []
  for i = 0; i < 1000; i = i + 1 {
    ids.push(Id(i))
  }
  let store : Map[Id, Int?] = {}
  for id in ids {
    store[id] = Some(id.0)
  }
  b.bench(fn() {
    // Exactly what recompute_data does each pass: alloc fresh map, populate,
    // clear the live map, copy entries back.
    let next_data : Map[Id, Int?] = {}
    for id in ids {
      next_data[id] = store[id]
    }
    store.clear()
    for id, d in next_data {
      store[id] = d
    }
    b.keep(store.size())
  })
}
