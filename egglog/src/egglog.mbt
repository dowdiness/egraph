// ════════════════════════════════════════════════════════════════════
// Egglog: Relational E-Graph Engine
// ════════════════════════════════════════════════════════════════════
//
// A relational e-graph engine that unifies Datalog and equality
// saturation. Functions are stored as database tables, e-matching
// uses relational joins, and rules are Datalog queries with actions.
//
// References:
//   - egglog paper: https://arxiv.org/abs/2304.04332
//   - egg paper: https://arxiv.org/abs/2004.03082
//
// Package tour:
//   - `database.mbt` coordinates tables, union-find, and rebuild
//   - `join.mbt` executes rule queries
//   - `rule.mbt` defines the small rule language and action semantics
//   - `schedule.mbt` controls repeated rule application
//   - `extract.mbt` chooses a cheapest tree-shaped representative
// ════════════════════════════════════════════════════════════════════
