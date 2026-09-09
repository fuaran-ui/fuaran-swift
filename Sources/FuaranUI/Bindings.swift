// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The closed value-binding, text-source, action, and compute-layer wire DUs,
// each modelled as a Swift `enum` with associated values — one case per wire
// `$type`. A per-case `switch` over these is compile-time exhaustive, so a new
// wire case that misses an arm is a build error, not a silent fallback.

import Foundation

/// Marks a closure-bearing slot whose function value was present on the wire.
/// The value itself is unobservable (§4); only presence is modelled.
public struct Closure: Equatable, Sendable {
  public init() {}
}

/// A text-producing position (§3.3). A bare wire string decodes to `.literal`
/// (the §16 AI-ingest shorthand).
public enum TextSource: Equatable, Sendable {
  case literal(String)
  case bound(Binding)
  case i18n(key: String, args: [String: JSON])
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

/// A value binding (§3.3), one case per wire `$type`.
public indirect enum Binding: Equatable, Sendable {
  case staticValue(StaticValue)
  case query(name: String, dependsOn: [String]?)
  /// 0.2.0 — optional `defaultValue` (the `State.defaultValue` convention).
  case filter(name: String, defaultValue: StaticValue?)
  /// 0.2.9 — optional `defaultValue`; 0.2.10 — optional `field` (the
  /// declarative row-field projection).
  case selection(nodeId: String, defaultValue: StaticValue?, field: String?)
  case state(key: String, defaultValue: StaticValue)
  case computed
  /// The host-furnished instant. Carries no payload: the value is supplied at resolve
  /// time by the host clock, which is why it is a `Clock`-determinism source, not wire data.
  ///
  /// Phase 1533 — the declared GRAIN truncates the instant BEFORE it is read.
  /// Absent is `second`, which is the identity; a present value outside the
  /// four is refused rather than silently read at a neighbouring resolution.
  case now(grain: TimeGrain?)
  case i18n(key: String, args: [NamedBinding]?)
  /// Phase 1534 (§3.3.3) — `codec` declares the buffer's OWN codec and replaces
  /// the identity on both sides; `commitTo` declares the State key the flush
  /// writes to. `commitTo` and the `onCommit` closure are mutually exclusive,
  /// because the wire cannot carry the closure and two hosts would otherwise
  /// write to different places from identical bytes.
  case local(
    codec: Format?, commitTo: String?, flushOn: LocalFlushTrigger, initialFrom: Binding,
    onCommit: Closure?)
  case format(format: Format, locale: LocaleSource, source: Binding)
  case transform(params: [TransformParam]?, pipeline: [TransformStep], source: DataSource)
  /// Phase 1534 (§3.3.2) — ONE scalar expression evaluated to ONE value over
  /// the SAME `ColExpr` algebra a `transform` pipeline step carries. The case
  /// introduces no operator and no expression language of its own, so an
  /// expression means here exactly what it means inside a `derive`.
  ///
  /// Two DECODE refusals, both because an `expr` has no row: a `col` reference
  /// anywhere in the expression, and a `param` the binding's own list does not
  /// bind. Left admitted, each would decode to an expression whose evaluation
  /// could only ever fail, once per render, on every host.
  case expr(expr: ColExpr, params: [TransformParam]?)
  case invoke(capabilityId: String, args: [InvokeArg])
}

public enum LocalFlushTrigger: Equatable, Sendable {
  case onBlur
  case onSubmit
  case onCommitAction
  case onDebounce(milliseconds: Int)
}

public enum Format: Equatable, Sendable {
  case number(decimals: Int?)
  case currency(isoCode: String)
  case percent(decimals: Int?)
  case date(dateStyle: DateStyle)
  case relativeTime(unit: RelativeTimeUnit)
  /// Phase 1533 — the elapsed-time rendition. Distinct from `relativeTime`:
  /// this one is a function of the HOST instant as well as of its source, so a
  /// host with no instant renders nothing rather than an invented delta.
  case since(unit: RelativeTimeUnit?)
  /// Phase 819 — the numeric source counts `unit`s, rendered per the bounded
  /// `style`.
  case duration(unit: DurationUnit, style: DurationStyle)
}

public enum LocaleSource: Equatable, Sendable {
  case ambient
  case explicit(tag: String)
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

public struct TransformParam: Equatable, Sendable {
  public var name: String
  public var from: Binding
  public init(name: String, from: Binding) {
    self.name = name
    self.from = from
  }
}

public struct InvokeArg: Equatable, Sendable {
  public var addr: String
  public var value: String
  public init(addr: String, value: String) {
    self.addr = addr
    self.value = value
  }
}

/// The declarative result target of an `Action.Call` (Phase 428).
public enum CallResultTarget: Equatable, Sendable {
  case state(key: String)
  case query(name: String)
}

/// A user-interaction action (§3.3), one case per wire `$type`.
public indirect enum Action: Equatable, Sendable {
  case dispatch
  case call(endpoint: String, into: CallResultTarget?, onResult: Closure?)
  case notify(channel: String, payload: JSON)
  /// Phase 1536 — `route` is a `TextSource`, not a bare string, so a tree can
  /// name a destination it computes from what the reader is looking at. The
  /// bare JSON string IS `Literal`'s canonical form, so every document written
  /// before the widening decodes exactly as it did. `target` is the CLOSED
  /// `Self | Blank` enum, omitted at `Self`.
  case navigate(route: TextSource, target: NavigateTarget)
  /// Exactly ONE of `value` (a literal payload) and `valueFrom` (a binding resolved at
  /// dispatch time) is present - the schema states it as a `oneOf`, so both-present is a
  /// reject rather than a precedence question.
  case setState(key: String, value: JSON?, valueFrom: Binding?)
  case aiTool(toolName: String, args: JSON)
  case chain([Action])
  case commitLocal(nodeId: String)
  /// Phase 1126 — the payload is a `TextSource`. A `text` that is neither a
  /// string nor a `$type`-tagged `TextSource` is `WRONG_TYPE` and is never
  /// coerced: a host reading the widening as "this member is now open" would
  /// put a JSON literal on the reader's clipboard, and a clipboard is a channel
  /// the reader later pastes somewhere with authority.
  case writeToClipboard(text: TextSource)
  /// Phase 1124 — the payload-free print, and the ONE action case strict about
  /// unrecognised members: page range, size, margins and copies are the host's
  /// page setup and the reader's dialogue, so accepting a member here would
  /// leave the emitter believing it had constrained a printing it had not.
  case print
  /// Phase 1537 — ask, then act. Confirmation is bounded at ONE question: a
  /// `confirm` reachable from either continuation is refused, and the check
  /// walks the DECODED continuation so a `chain` cannot hide the nesting.
  case confirm(prompt: TextSource, onConfirm: Action, onCancel: Action?)
  /// Phase 1537 — a bare node id, the `commitLocal` shape. It addresses a node
  /// in THIS document, so there is nothing for a binding to compute.
  case focus(nodeId: String)
  case readFileBody(fileRef: String, encoding: FileReadEncoding)
  case invoke(capabilityId: String, args: [InvokeArg])
}

public struct SelectOption: Equatable, Sendable {
  public var value: String
  public var label: TextSource
  public init(value: String, label: TextSource) {
    self.value = value
    self.label = label
  }
}

public struct MapMarker: Equatable, Sendable {
  public var label: TextSource
  public var latitude: Double
  public var longitude: Double
  public init(label: TextSource, latitude: Double, longitude: Double) {
    self.label = label
    self.latitude = latitude
    self.longitude = longitude
  }
}

public enum CellFormat: Equatable, Sendable {
  case none
  case number(decimals: Int?)
  case currency(code: String)
  case percent(decimals: Int?)
  case significantDigits(digits: Int)
  case date(format: String)
  case duration(unit: DurationUnit, style: DurationStyle)
  /// A relative-time CELL format ("3 minutes ago"). Distinct from the `Format` DU's own
  /// `relativeTime`: the wire carries two format DUs and a case in one is not a case in
  /// the other.
  case relativeTime(unit: RelativeTimeUnit)
  case custom
}

public enum ColumnWidth: Equatable, Sendable {
  case auto
  case fixed(pixels: Int)
  case flex(weight: Double)
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

public struct SortKey: Equatable, Sendable {
  public var col: String
  public var dir: SortDir
  public init(col: String, dir: SortDir) {
    self.col = col
    self.dir = dir
  }
}

public enum TransformStep: Equatable, Sendable {
  case filter(pred: ColExpr)
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
