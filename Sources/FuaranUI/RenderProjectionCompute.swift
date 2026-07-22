// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The dataframe-algebra decode leg of the render projection (Phases 282/284/424):
// `Binding.Transform`'s data source + pipeline. Ported from the reference host.

import Foundation

extension Decode {
  static func enumFrom<T>(_ path: String, _ s: String, _ label: String) throws -> T
  where T: RawRepresentable, T.RawValue == String {
    guard let v = T(rawValue: s) else { throw wrongType(path, "\(label) '\(s)'") }
    return v
  }

  // ── DataSource ────────────────────────────────────────────────────────────

  static func dataSource(_ path: String, _ j: JSON) throws -> DataSource {
    let f = try object(path, j)
    // Lenient-ingest (Core Phase 88): `schema` may be omitted on an EMBEDDED
    // source (inferred per column, key order); a `ref` source still requires
    // it. The canonical encoder always emits the explicit schema.
    let declared: [SchemaEntry]?
    if let s = f["schema"] { declared = try colSchema("\(path).schema", s) } else {
      declared = nil
    }
    if let r = f["ref"] {
      if declared == nil {
        throw wrongType(
          "\(path).schema",
          "a ref source requires an explicit \"schema\" array — there are no cells to infer column types from"
        )
      }
      return .ref(name: try string("\(path).ref", r))
    }
    let colsObj = try object("\(path).columns", try req(path, f, "columns"))
    let schema: [SchemaEntry]
    if let declared {
      schema = declared
    } else {
      schema = try colsObj.keys.sorted().map { name in
        guard let col = colsObj[name] else { throw missing("\(path).columns", name) }
        let (values, _) = try columnParts("\(path).columns.\(name)", col)
        return SchemaEntry(
          name: name, columnType: try inferColumnType("\(path).columns.\(name)", values))
      }
    }
    let columns = try schema.map {
      try dataColumn("\(path).columns", colsObj, $0.name, $0.columnType)
    }
    return .embedded(schema: schema, columns: columns)
  }

  static func colSchema(_ path: String, _ j: JSON) throws -> [SchemaEntry] {
    let items = try array(path, j)
    return try items.enumerated().map { (i, e) in
      let f = try object("\(path)[\(i)]", e)
      let name = try reqString("\(path)[\(i)]", f, "name")
      let ty: ColumnType = try enumFrom(
        "\(path)[\(i)].type", try reqString("\(path)[\(i)]", f, "type"), "column type")
      return SchemaEntry(name: name, columnType: ty)
    }
  }

  /// Lenient-ingest (Core Phases 88 + 94) — the `(values, validity)` parts of a
  /// column element: a BARE JSON array is the "just the data" shorthand (an
  /// all-present mask is synthesised); a wrapped object carrying `values` but
  /// no `validity` is the same all-present statement.
  static func columnParts(_ path: String, _ col: JSON) throws -> ([JSON], [JSON]) {
    if case .array(let xs) = col {
      return (xs, Array(repeating: JSON.bool(true), count: xs.count))
    }
    let f = try object(path, col)
    let values = try array("\(path).values", try req(path, f, "values"))
    guard let v = f["validity"] else {
      return (values, Array(repeating: JSON.bool(true), count: values.count))
    }
    return (values, try array("\(path).validity", v))
  }

  /// Lenient-ingest (Core Phase 88) — infer one column's type from its cells.
  /// Pinned deterministic rules: all-int numerics => int, any fractional =>
  /// float, all-bool => bool, all-string => string — never date/timestamp.
  static func inferColumnType(_ path: String, _ values: [JSON]) throws -> ColumnType {
    if values.isEmpty {
      throw wrongType(
        path,
        "cannot infer a column type from an empty / all-null column — declare it in an explicit \"schema\" array"
      )
    }
    var sawInt = false
    var sawFloat = false
    var sawBool = false
    var sawStr = false
    var sawOther = false
    for v in values {
      switch v {
      case .number(let n) where n == n.rounded(.towardZero): sawInt = true
      case .number: sawFloat = true
      case .bool: sawBool = true
      case .string: sawStr = true
      default: sawOther = true
      }
    }
    switch (sawInt, sawFloat, sawBool, sawStr, sawOther) {
    case (true, false, false, false, false): return .int
    case (_, true, false, false, false): return .float
    case (false, false, true, false, false): return .bool
    case (false, false, false, true, false): return .string
    default:
      throw wrongType(
        path,
        "cannot infer a single column type from mixed cell kinds — declare it in an explicit \"schema\" array"
      )
    }
  }

  static func dataColumn(
    _ path: String, _ cols: [String: JSON], _ name: String, _ ty: ColumnType
  ) throws -> DataColumn {
    guard let col = cols[name] else { throw missing(path, name) }
    let (values, validity) = try columnParts("\(path).\(name)", col)
    guard values.count == validity.count else {
      throw wrongType(
        "\(path).\(name)",
        "values/validity length match (\(values.count) vs \(validity.count))")
    }
    var cells: [Cell] = []
    cells.reserveCapacity(values.count)
    for (v, present) in zip(values, validity) {
      switch present {
      case .bool(false): cells.append(.null)
      case .bool(true): cells.append(try columnCell("\(path).\(name)", ty, v))
      default: throw wrongType("\(path).\(name).validity", "JSON boolean")
      }
    }
    return DataColumn(name: name, columnType: ty, cells: cells)
  }

  static func columnCell(_ path: String, _ ty: ColumnType, _ v: JSON) throws -> Cell {
    switch (ty, v) {
    case (.int, .number(let n)): return .int(Int(n.rounded(.towardZero)))
    case (.float, .number(let n)): return .float(n)
    case (.bool, .bool(let b)): return .bool(b)
    case (.string, .string(let s)): return .str(s)
    case (.date, .string(let s)): return .date(s)
    case (.timestamp, .string(let s)): return .timestamp(s)
    // Lenient-ingest (Core Phase 94): a declared-timestamp column accepts an
    // epoch NUMBER — unit by magnitude (>= 1e11 => milliseconds) — normalised
    // to the canonical ISO string on decode.
    case (.timestamp, .number(let n))
    where n == n.rounded(.towardZero) && abs(n) < 9e15:
      let i = Int64(n)
      let secs = abs(i) >= 100_000_000_000 ? i / 1000 : i
      return .timestamp(isoOfEpochSeconds(secs))
    default: throw wrongType(path, "\(ty.rawValue) cell value")
    }
  }

  /// Render an epoch-seconds instant as the canonical ISO-8601 UTC timestamp
  /// string. Pure integer civil-from-days arithmetic — deterministic and
  /// clock-free; negative epochs (pre-1970) are handled.
  static func isoOfEpochSeconds(_ secs: Int64) -> String {
    var days = secs / 86_400
    if secs % 86_400 < 0 { days -= 1 }
    let sod = secs - days * 86_400
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    func pad2(_ n: Int64) -> String { n < 10 ? "0\(n)" : "\(n)" }
    let y = String(format: "%04d", Int(year))
    return
      "\(y)-\(pad2(month))-\(pad2(day))T\(pad2(sod / 3600)):\(pad2(sod % 3600 / 60)):\(pad2(sod % 60))Z"
  }

  static func cellLit(_ path: String, _ j: JSON) throws -> Cell {
    let f = try object(path, j)
    let tag = try disc(path, f)
    if tag == "Null" { return .null }
    let v = try req(path, f, "value")
    switch (tag, v) {
    case ("Int", .number(let n)): return .int(Int(n.rounded(.towardZero)))
    case ("Float", .number(let n)): return .float(n)
    case ("Bool", .bool(let b)): return .bool(b)
    case ("Str", .string(let s)): return .str(s)
    case ("Date", .string(let s)): return .date(s)
    case ("Timestamp", .string(let s)): return .timestamp(s)
    default: throw wrongType(path, "\(tag) literal value")
    }
  }

  // ── ColExpr ───────────────────────────────────────────────────────────────

  static func colExpr(_ path: String, _ j: JSON) throws -> ColExpr {
    let f = try object(path, j)
    switch try string("\(path).$type", try req(path, f, "$type")) {
    case "col": return .col(name: try reqString(path, f, "name"))
    case "param": return .param(name: try reqString(path, f, "name"))
    case "lit": return .lit(cell: try cellLit("\(path).cell", try req(path, f, "cell")))
    case "binary":
      let op: BinOp = try enumFrom("\(path).op", try reqString(path, f, "op"), "binary op")
      return .binary(
        op: op,
        left: try colExpr("\(path).left", try req(path, f, "left")),
        right: try colExpr("\(path).right", try req(path, f, "right")))
    case "not": return .not(expr: try colExpr("\(path).expr", try req(path, f, "expr")))
    case "coalesce":
      let items = try array("\(path).exprs", try req(path, f, "exprs"))
      return .coalesce(
        exprs: try items.enumerated().map { try colExpr("\(path).exprs[\($0.0)]", $0.1) })
    case "case":
      let items = try array("\(path).cases", try req(path, f, "cases"))
      let arms = try items.enumerated().map { (i, c) -> CaseArm in
        let cf = try object("\(path).cases[\(i)]", c)
        return CaseArm(
          when: try colExpr("\(path).cases[\(i)].when", try req("\(path).cases[\(i)]", cf, "when")),
          then: try colExpr("\(path).cases[\(i)].then", try req("\(path).cases[\(i)]", cf, "then")))
      }
      return .caseExpr(
        cases: arms, elseExpr: try colExpr("\(path).else", try req(path, f, "else")))
    case "cast":
      let ty: ColumnType = try enumFrom(
        "\(path).type", try reqString(path, f, "type"), "column type")
      return .cast(columnType: ty, expr: try colExpr("\(path).expr", try req(path, f, "expr")))
    // Lenient-ingest (Core Phases 93/94): `call` and `fn` alias `apply` (same
    // fn/args fields); an `expr` field stands in for a one-element `args`.
    case "apply", "call", "fn":
      let fn: ScalarFn = try enumFrom("\(path).fn", try reqString(path, f, "fn"), "scalar fn")
      return .apply(fn: fn, args: try exprArgs(path, f))
    case "in":
      // Exactly one of `items` (literal list) / `param` (a bound multi-select
      // list param) — Core Phase 91.
      let subject = try colExpr("\(path).expr", try req(path, f, "expr"))
      switch (f["items"], f["param"]) {
      case (.some(let itemsJ), nil):
        let items = try array("\(path).items", itemsJ)
        return .inList(
          subject: subject,
          items: try items.enumerated().map { try colExpr("\(path).items[\($0.0)]", $0.1) })
      case (nil, .some(let p)):
        return .inParam(subject: subject, name: try string("\(path).param", p))
      case (.some, .some):
        throw wrongType(
          path,
          "exactly ONE of \"items\" (a literal list) or \"param\" (a multi-select list param), not both"
        )
      case (nil, nil):
        throw missing(path, "items")
      }
    case "isNull":
      return .isNull(expr: try colExpr("\(path).expr", try req(path, f, "expr")))
    // Lenient-ingest (Core Phase 93): expression-level string-predicate
    // spellings — {"$type":"contains","expr":X,"other":Y} (also left/right)
    // denotes exactly the canonical binary form.
    case "contains", "startsWith", "endsWith":
      let tag = try string("\(path).$type", try req(path, f, "$type"))
      let op: BinOp = tag == "contains" ? .contains : (tag == "startsWith" ? .startsWith : .endsWith)
      return .binary(
        op: op,
        left: try colExpr("\(path).left", try reqAliased(path, f, "left", ["expr"])),
        right: try colExpr("\(path).right", try reqAliased(path, f, "right", ["other"])))
    // Lenient-ingest (Core Phase 94): flat logical spellings — a variadic
    // `exprs` list left-folds into the nested binary form; the two-operand
    // left/right form maps one-to-one.
    case "and", "or":
      let tag = try string("\(path).$type", try req(path, f, "$type"))
      let op: BinOp = tag == "and" ? .and : .or
      if let exprsJ = f["exprs"] {
        let exprs = try array("\(path).exprs", exprsJ).enumerated()
          .map { try colExpr("\(path).exprs[\($0.0)]", $0.1) }
        guard let first = exprs.first else {
          throw wrongType("\(path).exprs", "a non-empty array")
        }
        return exprs.dropFirst().reduce(first) { acc, e in
          .binary(op: op, left: acc, right: e)
        }
      }
      return .binary(
        op: op,
        left: try colExpr("\(path).left", try reqAliased(path, f, "left", ["expr"])),
        right: try colExpr("\(path).right", try reqAliased(path, f, "right", ["other"])))
    // Lenient-ingest (Core Phase 94): flat comparison spellings.
    case "eq", "ne", "lt", "le", "gt", "ge":
      let tag = try string("\(path).$type", try req(path, f, "$type"))
      let op = BinOp(rawValue: tag)!
      return .binary(
        op: op,
        left: try colExpr("\(path).left", try reqAliased(path, f, "left", ["expr"])),
        right: try colExpr("\(path).right", try reqAliased(path, f, "right", ["other"])))
    case let o:
      // Lenient-ingest (Core Phase 94): flat scalar-fn spellings — a bare
      // fn-name node ({"$type":"lower","expr":X}) denotes Apply.
      if let fn = ScalarFn(rawValue: o) {
        return .apply(fn: fn, args: try exprArgs(path, f))
      }
      throw wrongType("\(path).$type", "column expr '\(o)'")
    }
  }

  /// The `args` of an apply-shaped node: the canonical array, or a lone `expr`
  /// field standing in for a one-element list (Core Phase 94).
  static func exprArgs(_ path: String, _ f: [String: JSON]) throws -> [ColExpr] {
    if let argsJ = f["args"] {
      return try array("\(path).args", argsJ).enumerated()
        .map { try colExpr("\(path).args[\($0.0)]", $0.1) }
    }
    return [try colExpr("\(path).expr", try req(path, f, "expr"))]
  }

  static func colPair(_ path: String, _ j: JSON) throws -> ColPair {
    let f = try object(path, j)
    return ColPair(a: try reqString(path, f, "a"), b: try reqString(path, f, "b"))
  }

  static func agg(_ path: String, _ j: JSON) throws -> Agg {
    let f = try object(path, j)
    // Lenient-ingest (Core Phase 92) — entry aliases: `as` for `name`, `op`
    // for `fn`, `column` for `of`; `avg` aliases `mean` (the SQL prior).
    let name = try string("\(path).name", try reqAliased(path, f, "name", ["as"]))
    let fnStr = try string("\(path).fn", try reqAliased(path, f, "fn", ["op"]))
    let fn: AggFn
    if fnStr == "avg" { fn = .mean } else { fn = try enumFrom("\(path).fn", fnStr, "agg fn") }
    let of = try string("\(path).of", try reqAliased(path, f, "of", ["column"]))
    return Agg(name: name, fn: fn, of: of)
  }

  static func sortKey(_ path: String, _ j: JSON) throws -> SortKey {
    let f = try object(path, j)
    // Lenient-ingest (Core Phases 92/93) — `column` aliases `col`; direction is
    // one of `dir` (canonical asc|desc), boolean `descending`, or `direction`;
    // a directionless entry is the SQL default (asc). Only "desc" sorts
    // descending.
    let col = try string("\(path).col", try reqAliased(path, f, "col", ["column"]))
    let dir: SortDir
    if let d = f["dir"] ?? f["direction"] {
      dir = try string("\(path).dir", d) == "desc" ? .desc : .asc
    } else if let d = f["descending"] {
      guard case .bool(let b) = d else {
        throw wrongType("\(path).descending", "JSON boolean")
      }
      dir = b ? .desc : .asc
    } else {
      dir = .asc
    }
    return SortKey(col: col, dir: dir)
  }

  static func strList(_ path: String, _ j: JSON) throws -> [String] {
    try array(path, j).enumerated().map { try string("\(path)[\($0.0)]", $0.1) }
  }

  // ── TransformStep + pipeline ───────────────────────────────────────────────

  static func pipelineSteps(_ path: String, _ j: JSON) throws -> [TransformStep] {
    try array(path, j).enumerated().map { try transformStep("\(path)[\($0.0)]", $0.1) }
  }

  static func transformStep(_ path: String, _ j: JSON) throws -> TransformStep {
    let f = try object(path, j)
    switch try string("\(path).$type", try req(path, f, "$type")) {
    case "filter":
      // Lenient-ingest (Core Phases 89/93): `predicate` aliases `pred`; the
      // flat prior {"$type":"filter","column":C,"op":O,"param":P | "value":V}
      // coerces to the canonical nested predicate.
      if let predJ = f["pred"] ?? f["predicate"] {
        return .filter(pred: try colExpr("\(path).pred", predJ))
      }
      guard let colJ = f["column"], let opJ = f["op"] else {
        throw wrongType(
          path,
          "a filter step carries \"pred\" (a $type-discriminated expression) — or the flat short form {\"column\":…,\"op\":…,\"param\":…|\"value\":…}"
        )
      }
      let col = try string("\(path).column", colJ)
      let op: BinOp = try enumFrom("\(path).op", try string("\(path).op", opJ), "binary op")
      let right: ColExpr
      switch (f["param"], f["value"]) {
      case (.some(let p), nil):
        right = .param(name: try string("\(path).param", p))
      case (nil, .some(let v)):
        switch v {
        case .string(let s): right = .lit(cell: .str(s))
        case .number(let n) where n == n.rounded(.towardZero):
          right = .lit(cell: .int(Int(n)))
        case .number(let n): right = .lit(cell: .float(n))
        case .bool(let b): right = .lit(cell: .bool(b))
        default:
          throw wrongType(
            "\(path).value", "a scalar (string/int/float/bool) in a flat filter step")
        }
      default:
        throw wrongType(
          path,
          "flat filter step: {column, op} needs \"param\" (a pipeline param name) or \"value\" (a scalar literal) as the right-hand side"
        )
      }
      return .filter(pred: .binary(op: op, left: .col(name: col), right: right))
    case "project":
      let items = try array("\(path).cols", try req(path, f, "cols"))
      return .project(
        cols: try items.enumerated().map { try colPair("\(path).cols[\($0.0)]", $0.1) })
    case "derive":
      return .derive(
        name: try reqString(path, f, "name"),
        expr: try colExpr("\(path).expr", try req(path, f, "expr")))
    case "groupBy":
      // Lenient-ingest (Core Phase 92): `by` aliases `keys`; `aggregations`
      // aliases `aggs`.
      let keys = try strList("\(path).keys", try reqAliased(path, f, "keys", ["by"]))
      let aggs = try array("\(path).aggs", try reqAliased(path, f, "aggs", ["aggregations"]))
        .enumerated()
        .map { try agg("\(path).aggs[\($0.0)]", $0.1) }
      return .groupBy(keys: keys, aggs: aggs)
    case "join":
      let source = try dataSource("\(path).source", try req(path, f, "source"))
      let on = try array("\(path).on", try req(path, f, "on")).enumerated()
        .map { try colPair("\(path).on[\($0.0)]", $0.1) }
      let how: JoinKind = try enumFrom("\(path).how", try reqString(path, f, "how"), "join kind")
      return .join(source: source, on: on, how: how)
    case "window":
      let partitionBy = try strList("\(path).partitionBy", try req(path, f, "partitionBy"))
      let orderBy = try array("\(path).orderBy", try req(path, f, "orderBy")).enumerated()
        .map { try sortKey("\(path).orderBy[\($0.0)]", $0.1) }
      // Legacy alias: `cumSum` is the pre-rename wire tag for `cumulSum`.
      let fnStr = try reqString(path, f, "fn")
      let fn: WindowFn
      if fnStr == "cumSum" { fn = .cumulSum } else {
        fn = try enumFrom("\(path).fn", fnStr, "window fn")
      }
      return .window(
        partitionBy: partitionBy, orderBy: orderBy, fn: fn,
        of: try reqString(path, f, "of"), alias: try reqString(path, f, "as"))
    case "pivot":
      let agg: AggFn = try enumFrom("\(path).agg", try reqString(path, f, "agg"), "agg fn")
      return .pivot(
        index: try strList("\(path).index", try req(path, f, "index")),
        on: try reqString(path, f, "on"), values: try reqString(path, f, "values"), agg: agg)
    case "unpivot":
      return .unpivot(
        idVars: try strList("\(path).idVars", try req(path, f, "idVars")),
        valueVars: try strList("\(path).valueVars", try req(path, f, "valueVars")))
    case "sort":
      // Lenient-ingest (Core Phase 92): `keys` aliases `by`.
      let by = try array("\(path).by", try reqAliased(path, f, "by", ["keys"])).enumerated()
        .map { try sortKey("\(path).by[\($0.0)]", $0.1) }
      return .sort(by: by)
    case "distinct": return .distinct
    case "limit":
      // Lenient-ingest (Core Phase 92): `count` aliases `n`; an absent
      // `offset` is unambiguously 0.
      return .limit(
        n: try int("\(path).n", try reqAliased(path, f, "n", ["count"])),
        offset: try optInt(path, f, "offset") ?? 0)
    case "union":
      return .union(source: try dataSource("\(path).source", try req(path, f, "source")))
    case let o:
      throw wrongType("\(path).$type", "transform step '\(o)'")
    }
  }
}
