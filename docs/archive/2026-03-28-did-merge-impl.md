# DidMerge Implementation Plan

**Status: Complete** — merged in PR #3 (2026-03-28).

**Goal:** Add `DidMerge` — a two-boolean struct returned by `Analysis.merge` that records
whether either argument changed. `rebuild` uses this to skip re-running `modify` on classes
whose analysis data is already stable, and lays the foundation for `BackoffScheduler`.

**Architecture:** `Analysis.merge` changes from `(D, D) -> D` to `(D, D) -> (D, DidMerge)`.
Three call sites in `egraph.mbt` are updated. `subst_and_eval_analysis` merge closure is
updated in `lambda_eval_wbtest.mbt`. Helper constructors make common cases concise.

**Reference:** egg's [`DidMerge`](https://docs.rs/egg/latest/egg/struct.DidMerge.html)
and its use in `EGraph::union` / `rebuild`.

---

## File Map

| File | Change |
|------|--------|
| `egraph.mbt` | Add `DidMerge` struct + helpers; update `Analysis.merge` signature; update 3 call sites in `AnalyzedEGraph::union` and `rebuild` |
| `lambda_eval_wbtest.mbt` | Update `subst_and_eval_analysis` merge closure to return `(D, DidMerge)` |

---

## Task 1: Add `DidMerge` struct and helpers

**File:** `egraph.mbt`

- [ ] **Step 1: Add the struct near the `Analysis` definition**

```moonbit
///|
/// Tracks whether merging changed either side of a union.
/// `a_changed`: the first argument was updated.
/// `b_changed`: the second argument was updated.
/// Used by `rebuild` to skip `modify` when data is already stable.
pub struct DidMerge {
  a_changed : Bool
  b_changed : Bool
} derive(Eq, Show)
```

- [ ] **Step 2: Add helper constructors below the struct**

```moonbit
///|
pub fn DidMerge::both() -> DidMerge {
  { a_changed: true, b_changed: true }
}

///|
pub fn DidMerge::a_only() -> DidMerge {
  { a_changed: true, b_changed: false }
}

///|
pub fn DidMerge::b_only() -> DidMerge {
  { a_changed: false, b_changed: true }
}

///|
pub fn DidMerge::neither() -> DidMerge {
  { a_changed: false, b_changed: false }
}

///|
/// True if either argument changed — i.e. the e-graph needs more work.
pub fn DidMerge::changed(self : DidMerge) -> Bool {
  self.a_changed || self.b_changed
}
```

- [ ] **Step 3: Run `moon check`** — expect no errors yet (signature unchanged).

---

## Task 2: Update `Analysis.merge` signature

**File:** `egraph.mbt`

- [ ] **Step 4: Change the `merge` field type**

```moonbit
// Before:
merge : (D, D) -> D

// After:
merge : (D, D) -> (D, DidMerge)
```

The full updated struct:

```moonbit
///|
/// Analysis callbacks: compute, merge, and react to per-e-class data.
priv struct Analysis[L, D] {
  /// Compute data for a single e-node. `get_data` looks up children's data.
  make : (L, (Id) -> D) -> D
  /// Combine data from two e-classes being merged.
  /// Returns the merged data and a `DidMerge` indicating which side changed.
  /// Must be commutative: `merge(a, b).0 == merge(b, a).0`.
  merge : (D, D) -> (D, DidMerge)
  /// Post-merge hook: may add nodes or union classes based on analysis data.
  modify : (AnalyzedEGraph[L, D], Id) -> Unit
}
```

- [ ] **Step 5: Run `moon check`** — expect errors at the 3 call sites. Note which lines they are.

---

## Task 3: Update the three `merge` call sites

**File:** `egraph.mbt`

There are three call sites. Update each to destructure the tuple.

- [ ] **Step 6: `AnalyzedEGraph::union` (around line 1077)**

```moonbit
// Before:
let merged_data = (self.analysis.merge)(data_a, data_b)

// After:
let (merged_data, _did_merge) = (self.analysis.merge)(data_a, data_b)
```

*(`_did_merge` is unused here — union always proceeds regardless. The value matters in `rebuild`.)*

- [ ] **Step 7: `rebuild` stale-data remerge (around line 1132)**

```moonbit
// Before:
self.data[canonical] = (self.analysis.merge)(existing, d)

// After:
let (merged, _) = (self.analysis.merge)(existing, d)
self.data[canonical] = merged
```

- [ ] **Step 8: `rebuild` recompute_data (around line 1164)**

```moonbit
// Before:
Some(acc) => Some((self.analysis.merge)(acc, d))

// After:
Some(acc) => {
  let (merged, _) = (self.analysis.merge)(acc, d)
  Some(merged)
}
```

- [ ] **Step 9: Run `moon check`** — expect the only remaining error to be in `lambda_eval_wbtest.mbt`.

---

## Task 4: Update `subst_and_eval_analysis`

**File:** `lambda_eval_wbtest.mbt`

- [ ] **Step 10: Update the `merge` closure to return `(EvalState, DidMerge)`**

The merge computes FV intersection and combines `val`. It should signal:
- `a_changed` if the new FV or val differs from `a`
- `b_changed` if it differs from `b`

```moonbit
merge: fn(a, b) {
  let fv : @hashset.HashSet[String] = @hashset.new()
  for x in a.fv {
    if b.fv.contains(x) {
      fv.add(x)
    }
  }
  let val = match (a.val, b.val) {
    (Some(v1), Some(v2)) => if v1 == v2 { Some(v1) } else { None }
    (Some(v), None) | (None, Some(v)) => Some(v)
    _ => None
  }
  let result = { fv, val }
  // a changed if its fv shrank or val changed
  let a_changed = a.fv.size() != fv.size() || a.val != val
  // b changed if its fv shrank or val changed
  let b_changed = b.fv.size() != fv.size() || b.val != val
  (result, { a_changed, b_changed })
},
```

- [ ] **Step 11: Run `moon check`** — expect 0 errors.

---

## Task 5: Verify and finish

- [ ] **Step 12: Run all tests**

```bash
moon test
```

Expected: all 100 tests pass.

- [ ] **Step 13: Run `moon info && moon fmt`**

- [ ] **Step 14: Commit**

```bash
git add egraph.mbt lambda_eval_wbtest.mbt pkg.generated.mbti
git commit -m "feat(egraph): add DidMerge — track whether analysis merge changed either side"
```

---

## Notes

- The `_did_merge` values at the union call sites are intentionally unused for now. They become meaningful when `BackoffScheduler` is added — the scheduler uses `DidMerge::changed()` to detect when a rule stops making progress and applies backoff.
- `fv.size() != a.fv.size()` is a proxy for "FV changed" that avoids a full set-equality check. It is sound because FV only shrinks on merge (intersection), so equal size implies equal content.
