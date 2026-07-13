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
    let schema = try colSchema("\(path).schema", try req(path, f, "schema"))
    if let r = f["ref"] {
      return .ref(name: try string("\(path).ref", r))
    }
    let colsObj = try object("\(path).columns", try req(path, f, "columns"))
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

  static func dataColumn(
    _ path: String, _ cols: [String: JSON], _ name: String, _ ty: ColumnType
  ) throws -> DataColumn {
    guard let col = cols[name] else { throw missing(path, name) }
    let f = try object("\(path).\(name)", col)
    let values = try array("\(path).\(name).values", try req("\(path).\(name)", f, "values"))
    let validity = try array("\(path).\(name).validity", try req("\(path).\(name)", f, "validity"))
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
    default: throw wrongType(path, "\(ty.rawValue) cell value")
    }
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
    case "apply":
      let fn: ScalarFn = try enumFrom("\(path).fn", try reqString(path, f, "fn"), "scalar fn")
      let items = try array("\(path).args", try req(path, f, "args"))
      return .apply(
        fn: fn, args: try items.enumerated().map { try colExpr("\(path).args[\($0.0)]", $0.1) })
    case let o:
      throw wrongType("\(path).$type", "column expr '\(o)'")
    }
  }

  static func colPair(_ path: String, _ j: JSON) throws -> ColPair {
    let f = try object(path, j)
    return ColPair(a: try reqString(path, f, "a"), b: try reqString(path, f, "b"))
  }

  static func agg(_ path: String, _ j: JSON) throws -> Agg {
    let f = try object(path, j)
    let fn: AggFn = try enumFrom("\(path).fn", try reqString(path, f, "fn"), "agg fn")
    return Agg(name: try reqString(path, f, "name"), fn: fn, of: try reqString(path, f, "of"))
  }

  static func sortKey(_ path: String, _ j: JSON) throws -> SortKey {
    let f = try object(path, j)
    let dirStr = try reqString(path, f, "dir")
    return SortKey(col: try reqString(path, f, "col"), dir: dirStr == "desc" ? .desc : .asc)
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
    case "filter": return .filter(pred: try colExpr("\(path).pred", try req(path, f, "pred")))
    case "project":
      let items = try array("\(path).cols", try req(path, f, "cols"))
      return .project(
        cols: try items.enumerated().map { try colPair("\(path).cols[\($0.0)]", $0.1) })
    case "derive":
      return .derive(
        name: try reqString(path, f, "name"),
        expr: try colExpr("\(path).expr", try req(path, f, "expr")))
    case "groupBy":
      let keys = try strList("\(path).keys", try req(path, f, "keys"))
      let aggs = try array("\(path).aggs", try req(path, f, "aggs")).enumerated()
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
      let fn: WindowFn = try enumFrom("\(path).fn", try reqString(path, f, "fn"), "window fn")
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
      let by = try array("\(path).by", try req(path, f, "by")).enumerated()
        .map { try sortKey("\(path).by[\($0.0)]", $0.1) }
      return .sort(by: by)
    case "distinct": return .distinct
    case "limit":
      return .limit(n: try reqInt(path, f, "n"), offset: try reqInt(path, f, "offset"))
    case "union":
      return .union(source: try dataSource("\(path).source", try req(path, f, "source")))
    case let o:
      throw wrongType("\(path).$type", "transform step '\(o)'")
    }
  }
}
