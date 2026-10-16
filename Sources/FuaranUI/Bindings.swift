// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The hand-written payload types beneath the value-binding vocabulary, and the
// dataframe compute layer. `TextSource`, `Binding`, `Action` and the other
// tagged unions the IDL declares are GENERATED into `Model.generated.swift`
// (Phase 2299); the types here are what those generated cases carry but the IDL
// does not declare as wire vocabulary — the presence-only `Closure`, the typed
// static payload, the named i18n argument, and the compute layer decoded out of
// host-declared transform payloads. Each is an `enum` with associated values
// where it is a closed set, so a per-case `switch` over it is compile-time
// exhaustive.

import Foundation

/// Marks a closure-bearing slot whose function value was present on the wire.
/// The value itself is unobservable (§4); only presence is modelled.
public struct Closure: Equatable, Sendable {
  public init() {}
}

/// A `Binding.Static` / `Binding.State` payload. The language-enumerated slot
/// shapes (Phase 429) are typed cases; everything else rides the faithful
/// parsed value (`.ast`).
public enum StaticValue: Equatable, Sendable {
  case ast(JSON)
  case options([SelectOption])
  case stringOpt(String?)
  case stringList([String])
  case floatSeq([Double])
  case markers([MapMarker])
  /// The 0.2.0 `FormFieldKind.Range` dual-thumb `(min, max)` pair.
  case floatPair(Double, Double)
  /// The 0.7.0 `FormFieldKind.DateRange` ordered `(from, to)` ISO-8601 pair.
  /// Rides as the BARE `{"from":…,"to":…}` object — no `Static` envelope,
  /// exactly the `floatPair` posture above.
  case stringPair(String, String)
}

/// A named `Binding` entry (the `I18n` per-argument bindings map). A named
/// struct rather than a `(String, Binding)` tuple so `Equatable` synthesis
/// works (tuples do not conform to `Equatable`).
public struct NamedBinding: Equatable, Sendable {
  public var name: String
  public var binding: Binding
  public init(name: String, binding: Binding) {
    self.name = name
    self.binding = binding
  }
}

// ── Compute layer (Phases 282/284/424) ───────────────────────────────────────

public enum Cell: Equatable, Sendable {
  case null
  case int(Int)
  case float(Double)
  case bool(Bool)
  case str(String)
  case date(String)
  case timestamp(String)
}

public struct SchemaEntry: Equatable, Sendable {
  public var name: String
  public var columnType: ColumnType
  public init(name: String, columnType: ColumnType) {
    self.name = name
    self.columnType = columnType
  }
}

public struct DataColumn: Equatable, Sendable {
  public var name: String
  public var columnType: ColumnType
  public var cells: [Cell]
  public init(name: String, columnType: ColumnType, cells: [Cell]) {
    self.name = name
    self.columnType = columnType
    self.cells = cells
  }
}

public enum DataSource: Equatable, Sendable {
  case ref(name: String)
  case embedded(schema: [SchemaEntry], columns: [DataColumn])
}

public indirect enum ColExpr: Equatable, Sendable {
  case col(name: String)
  case param(name: String)
  case lit(cell: Cell)
  case binary(op: BinOp, left: ColExpr, right: ColExpr)
  case not(expr: ColExpr)
  case coalesce(exprs: [ColExpr])
  case caseExpr(cases: [CaseArm], elseExpr: ColExpr)
  case cast(columnType: ColumnType, expr: ColExpr)
  case apply(fn: ScalarFn, args: [ColExpr])
  /// SQL three-valued membership over a literal list.
  case inList(subject: ColExpr, items: [ColExpr])
  /// Membership over a bound multi-select list param.
  case inParam(subject: ColExpr, name: String)
  case isNull(expr: ColExpr)
}

public struct CaseArm: Equatable, Sendable {
  public var when: ColExpr
  public var then: ColExpr
  public init(when: ColExpr, then: ColExpr) {
    self.when = when
    self.then = then
  }
}

public struct ColPair: Equatable, Sendable {
  public var a: String
  public var b: String
  public init(a: String, b: String) {
    self.a = a
    self.b = b
  }
}

public struct Agg: Equatable, Sendable {
  public var name: String
  public var fn: AggFn
  public var of: String
  public init(name: String, fn: AggFn, of: String) {
    self.name = name
    self.fn = fn
    self.of = of
  }
}

/// A sort key, used by both the `sort` step's `by` and the `window` step's
/// `orderBy`.
///
/// The WIRE member is `column` (canonical since substrate 0.28.0), with the
/// pre-rename `col` as its decode alias and a key carrying both refused. The
/// IN-MEMORY member below deliberately keeps the name `col`: this surface
/// decodes and never encodes, so the stored name binds no wire contract, while
/// renaming a public member of a shipped library IS a source break for every
/// consumer — and this phase's stability impact is additive. The wire
/// vocabulary lives at the decode site (`Decode.sortKey`), which is also where
/// the alias and the both-present refusal are; `ColPair`'s `a` / `b` already
/// read this way.
public struct SortKey: Equatable, Sendable {
  /// The column this key orders by — decoded from the wire's `column` (or its
  /// `col` alias).
  public var col: String
  public var dir: SortDir
  public init(col: String, dir: SortDir) {
    self.col = col
    self.dir = dir
  }
}

public enum TransformStep: Equatable, Sendable {
  case filter(pred: ColExpr)
  /// A projection. The WIRE member is `columns` (canonical since substrate
  /// 0.28.0), with the pre-rename `cols` as its decode alias and a step
  /// carrying both refused; the label below keeps its shipped spelling for the
  /// reason given on `SortKey`.
  case project(cols: [ColPair])
  case derive(name: String, expr: ColExpr)
  case groupBy(keys: [String], aggs: [Agg])
  case join(source: DataSource, on: [ColPair], how: JoinKind)
  case window(
    partitionBy: [String], orderBy: [SortKey], fn: WindowFn, of: String, alias: String)
  case pivot(index: [String], on: String, values: String, agg: AggFn)
  case unpivot(idVars: [String], valueVars: [String])
  case sort(by: [SortKey])
  case distinct
  case limit(n: Int, offset: Int)
  case union(source: DataSource)
}
