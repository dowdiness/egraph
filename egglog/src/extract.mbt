///|
/// An extracted expression tree.
pub(all) struct ExtractedExpr {
  func_name : String
  args : Array[ExtractedExpr]
  leaf_value : Value?
} derive(Debug)

///|
pub impl Show for ExtractedExpr with output(self, logger) {
  match self.leaf_value {
    Some(v) =>
      if self.args.is_empty() {
        logger.write_string("(")
        logger.write_string(self.func_name)
        logger.write_string(" ")
        Show::output(v, logger)
        logger.write_string(")")
      } else {
        logger.write_string("(")
        logger.write_string(self.func_name)
        for a in self.args {
          logger.write_string(" ")
          Show::output(a, logger)
        }
        logger.write_string(")")
      }
    None =>
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
}

///|
/// Default cost function: 1 + sum of children.
fn ast_size(_name : String, child_costs : Array[Int]) -> Int {
  let mut total = 1
  for c in child_costs {
    total = total + c
  }
  total
}

///|
/// Extract the cheapest expression from an e-class.
fn Database::extract(
  self : Database,
  root : Id,
  cost_fn : (String, Array[Int]) -> Int,
) -> (Int, ExtractedExpr) {
  // Build a cost map: canonical Id -> (cost, ExtractedExpr)
  let costs : Map[Int, (Int, ExtractedExpr)] = {}
  // Fixed-point iteration
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
        // Compute cost for this row
        let child_costs : Array[Int] = []
        let child_exprs : Array[ExtractedExpr] = []
        let prim_values : Array[Value] = []
        let mut all_available = true
        let mut all_primitive = true
        for k in key {
          match self.canonicalize_value(k) {
            IdVal(child_id) => {
              all_primitive = false
              let canon_child = self.find(child_id)
              match costs.get(canon_child.0) {
                Some(entry) => {
                  let (c, e) = entry
                  child_costs.push(c)
                  child_exprs.push(e)
                }
                None => all_available = false
              }
            }
            v => {
              prim_values.push(v)
              // Primitive values don't contribute to child cost
              child_costs.push(0)
            }
          }
        }
        if all_available {
          let cost = cost_fn(name, child_costs)
          let expr : ExtractedExpr = if all_primitive {
            // All args are primitives: leaf node like Num(42)
            match prim_values {
              [single] =>
                { func_name: name, args: [], leaf_value: Some(single) }
              _ => { func_name: name, args: [], leaf_value: None }
            }
          } else {
            { func_name: name, args: child_exprs, leaf_value: None }
          }
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
