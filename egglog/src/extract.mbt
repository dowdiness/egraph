///|
/// Output of the extractor.
///
/// Extraction reconstructs a tree from the graph, so each child is either a
/// recursively extracted expression or a primitive leaf that was stored in the
/// table row.
/// An extracted argument, preserving whether it was primitive or an e-class.
pub(all) enum ExtractedArg {
  Expr(ExtractedExpr)
  Primitive(Value)
} derive(Debug)

///|
pub impl Show for ExtractedArg with output(self, logger) {
  match self {
    Expr(expr) => Show::output(expr, logger)
    Primitive(value) => Show::output(value, logger)
  }
}

///|
/// Tree-shaped view of one chosen representative expression.
/// An extracted expression tree.
pub(all) struct ExtractedExpr {
  func_name : String
  args : Array[ExtractedArg]
} derive(Debug)

///|
pub impl Show for ExtractedExpr with output(self, logger) {
  if self.args.is_empty() {
    logger.write_string(self.func_name)
  } else {
    logger.write_string("(")
    logger.write_string(self.func_name)
    for a in self.args {
      logger.write_string(" ")
      Show::output(a, logger)
    }
    logger.write_string(")")
  }
}

///|
/// Default structural cost: one node plus the cost of all e-class children.
pub fn ast_size(_name : String, child_costs : Array[Int]) -> Int {
  let mut total = 1
  for c in child_costs {
    total = total + c
  }
  total
}

///|
/// Recover the cheapest expression currently known for one e-class.
///
/// This is a fixed-point dynamic program over the function tables. A row can be
/// scored only after all of its `IdVal` children already have extracted costs.
pub fn Database::extract(
  self : Database,
  root : Id,
  cost_fn : (String, Array[Int]) -> Int,
) -> (Int, ExtractedExpr) {
  // Best known expression for each canonical e-class.
  let costs : Map[Int, (Int, ExtractedExpr)] = {}
  // Repeatedly relax rows until no cheaper expression appears.
  let mut changed = true
  while changed {
    changed = false
    self.tables.each(fn(name, table) {
      let rows = table.scan()
      for row_pair in rows {
        let (key, value) = row_pair
        let output_id = match self.canonicalize_value(value) {
          IdVal(id) => self.find(id)
          _ => return
        }
        // Score the row only if every e-class child already has a chosen best
        // expression.
        let child_costs : Array[Int] = []
        let child_args : Array[ExtractedArg] = []
        let mut all_available = true
        for k in key {
          match self.canonicalize_value(k) {
            IdVal(child_id) =>
              match costs.get(child_id.0) {
                Some(entry) => {
                  let (c, e) = entry
                  child_costs.push(c)
                  child_args.push(Expr(e))
                }
                None => all_available = false
              }
            v => {
              // Primitive literals are leaves in the reconstructed AST.
              child_costs.push(0)
              child_args.push(Primitive(v))
            }
          }
        }
        if all_available {
          let cost = cost_fn(name, child_costs)
          let expr : ExtractedExpr = { func_name: name, args: child_args }
          let canon_out = output_id.0
          match costs.get(canon_out) {
            Some(entry) => {
              let (old_cost, _) = entry
              if cost < old_cost {
                costs[canon_out] = (cost, expr)
                changed = true
              }
            }
            None => {
              costs[canon_out] = (cost, expr)
              changed = true
            }
          }
        }
      }
    })
  }
  let canon_root = self.find(root)
  match costs.get(canon_root.0) {
    Some(entry) => entry
    None => abort("no extraction found for id " + canon_root.to_string())
  }
}
