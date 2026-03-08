///|
/// A schedule controls how rules are applied.
pub(all) enum Schedule {
  Run(Array[Rule])
  Saturate(Schedule, Int)
  Repeat(Int, Schedule)
  Seq(Array[Schedule])
} derive(Show, Debug)

///|
/// Why execution stopped.
pub(all) enum StopReason {
  Saturated
  IterLimit
  NodeLimit
} derive(Eq, Show, Debug)

///|
/// Apply a single rule: execute query, then actions for each match.
fn Database::apply_rule(self : Database, rule : Rule) -> Int {
  let substs = execute_query(self, rule.query)
  let mut total_unions = 0
  for s in substs {
    total_unions = total_unions + execute_actions(self, s, rule.actions)
  }
  self.rebuild()
  total_unions
}

///|
/// Count total rows across all tables.
fn Database::total_rows(self : Database) -> Int {
  let mut count = 0
  self.tables.each(fn(_name, table) { count = count + table.row_count() })
  count
}

///|
/// Run a schedule, returning why it stopped.
fn Database::run_schedule(self : Database, schedule : Schedule) -> StopReason {
  match schedule {
    Run(rules) => {
      for rule in rules {
        let _ = self.apply_rule(rule)
      }
      Saturated
    }
    Saturate(inner, max_iters) => {
      for i = 0; i < max_iters; i = i + 1 {
        let size_before = self.uf.size()
        let rows_before = self.total_rows()
        let _ = self.run_schedule(inner)
        let size_after = self.uf.size()
        let rows_after = self.total_rows()
        if size_before == size_after && rows_before == rows_after {
          return Saturated
        }
      }
      IterLimit
    }
    Repeat(n, inner) => {
      let mut last_reason = Saturated
      for i = 0; i < n; i = i + 1 {
        last_reason = self.run_schedule(inner)
      }
      last_reason
    }
    Seq(schedules) => {
      let mut last_reason = Saturated
      for s in schedules {
        last_reason = self.run_schedule(s)
      }
      last_reason
    }
  }
}
