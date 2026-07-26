// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The render-projection decoder: canonical wire JSON (as read back from the
// Rust reference core's `session_tree_json`) → the sealed Swift tree model.
// Decode-only by design — the native Swift surface renders over the Rust core
// and never canonically *encodes*, so there is no byte-parity leg. Every
// unknown discriminator hard-refuses with a structured error rather than
// falling to a silent fallback arm.

import Foundation

public enum RenderProjection {
  /// Decode a canonical wire `Node` document into the sealed tree model.
  public static func decodeNode(_ json: String) throws -> Node {
    let root = try JSON.parse(json)
    return try Decode.node("$", root)
  }
}

let OPAQUE = "<opaque>"

// ── Primitive accessors ──────────────────────────────────────────────────────

enum Decode {
  static func err(_ code: FuaranDecodeError.Code, _ path: String, _ message: String)
    -> FuaranDecodeError
  {
    FuaranDecodeError(code: code, path: path, message: message)
  }

  static func missing(_ path: String, _ key: String) -> FuaranDecodeError {
    err(.missingField, "\(path).\(key)", "missing required field '\(key)'")
  }

  static func wrongType(_ path: String, _ expected: String) -> FuaranDecodeError {
    err(.wrongType, path, "expected \(expected)")
  }

  static func unknownCase(_ path: String, _ got: String, _ expected: String) -> FuaranDecodeError {
    err(.unknownDuCase, "\(path).$type", "unknown discriminator '\(got)'; expected \(expected)")
  }

  /// Lenient AI-ingest (§3.6, generalised): a `Static` envelope wrapped around
  /// a PLAIN scalar unwraps before the scalar readers — the inverse of the
  /// bare-scalar-in-Binding-slot confusion, applied at every plain-scalar
  /// position in one place. Objects that are NOT a well-formed Static envelope
  /// pass through untouched and fail with the normal error.
  static func unwrapStaticEnvelope(_ j: JSON) -> JSON {
    if case .object(let f) = j, case .string("Static")? = f["$type"], let inner = f["value"] {
      return inner
    }
    return j
  }

  static func object(_ path: String, _ j: JSON) throws -> [String: JSON] {
    guard case .object(let f) = j else { throw wrongType(path, "JSON object") }
    return f
  }

  static func string(_ path: String, _ j: JSON) throws -> String {
    guard case .string(let s) = unwrapStaticEnvelope(j) else {
      throw wrongType(path, "JSON string")
    }
    return s
  }

  static func bool(_ path: String, _ j: JSON) throws -> Bool {
    guard case .bool(let b) = unwrapStaticEnvelope(j) else {
      throw wrongType(path, "JSON boolean")
    }
    return b
  }

  static func float(_ path: String, _ j: JSON) throws -> Double {
    switch unwrapStaticEnvelope(j) {
    case .number(let n): return n
    case .string("NaN"): return Double.nan
    case .string("Infinity"): return Double.infinity
    case .string("-Infinity"): return -Double.infinity
    default: throw wrongType(path, "JSON number (or NaN/Infinity/-Infinity sentinel)")
    }
  }

  static func int(_ path: String, _ j: JSON) throws -> Int {
    guard case .number(let n) = unwrapStaticEnvelope(j) else {
      throw wrongType(path, "JSON number (integer)")
    }
    return Int(n.rounded(.towardZero))
  }

  static func array(_ path: String, _ j: JSON) throws -> [JSON] {
    guard case .array(let a) = j else { throw wrongType(path, "JSON array") }
    return a
  }

  static func req(_ path: String, _ f: [String: JSON], _ key: String) throws -> JSON {
    guard let v = f[key] else { throw missing(path, key) }
    return v
  }

  static func disc(_ path: String, _ f: [String: JSON]) throws -> String {
    guard let v = f["$type"] else { throw missing(path, "$type") }
    guard case .string(let s) = v else {
      throw wrongType("\(path).$type", "JSON string discriminator")
    }
    return s
  }

  static func reqString(_ path: String, _ f: [String: JSON], _ key: String) throws -> String {
    try string("\(path).\(key)", try req(path, f, key))
  }
  static func reqBool(_ path: String, _ f: [String: JSON], _ key: String) throws -> Bool {
    try bool("\(path).\(key)", try req(path, f, key))
  }
  static func reqFloat(_ path: String, _ f: [String: JSON], _ key: String) throws -> Double {
    try float("\(path).\(key)", try req(path, f, key))
  }
  static func reqInt(_ path: String, _ f: [String: JSON], _ key: String) throws -> Int {
    try int("\(path).\(key)", try req(path, f, key))
  }
  static func optString(_ path: String, _ f: [String: JSON], _ key: String) throws -> String? {
    guard let v = f[key] else { return nil }
    return try string("\(path).\(key)", v)
  }
  static func optInt(_ path: String, _ f: [String: JSON], _ key: String) throws -> Int? {
    guard let v = f[key] else { return nil }
    return try int("\(path).\(key)", v)
  }
  static func optFloat(_ path: String, _ f: [String: JSON], _ key: String) throws -> Double? {
    guard let v = f[key] else { return nil }
    return try float("\(path).\(key)", v)
  }
  static func optBool(_ path: String, _ f: [String: JSON], _ key: String) throws -> Bool? {
    guard let v = f[key] else { return nil }
    return try bool("\(path).\(key)", v)
  }
  static func optClosure(_ f: [String: JSON], _ key: String) -> Closure? {
    f[key] != nil ? Closure() : nil
  }

  static func bareEnum<T>(_ path: String, _ j: JSON, _ label: String) throws -> T
  where T: RawRepresentable & CaseIterable, T.RawValue == String {
    try bareEnumAliased(path, j, label, [:])
  }

  /// Bare-string enum decode with a curated lenient-ingest alias table (§3.6).
  /// Canonical wire spellings decode via `init(rawValue:)`; a listed
  /// same-concept synonym maps to a canonical case; any other unknown case
  /// still fails `UNKNOWN_DU_CASE` with the canonical list.
  static func bareEnumAliased<T>(
    _ path: String, _ j: JSON, _ label: String, _ aliases: [String: T]
  ) throws -> T
  where T: RawRepresentable & CaseIterable, T.RawValue == String {
    let s = try string(path, j)
    if let v = T(rawValue: s) { return v }
    if let v = aliases[s] { return v }
    let names = T.allCases.map { $0.rawValue }.joined(separator: " | ")
    throw unknownCase(path, s, "\(label): \(names)")
  }

  // ── Curated lenient enum decoders (mirroring the reference host) ──────────

  /// The CSS flex-direction prior: a row lays out horizontally, a column
  /// vertically.
  static func orientation(_ path: String, _ j: JSON) throws -> Orientation {
    try bareEnumAliased(
      path, j, "Orientation",
      ["Row": .horizontal, "row": .horizontal, "Column": .vertical, "column": .vertical])
  }

  static func toneVariant(_ path: String, _ j: JSON) throws -> ToneVariant {
    try bareEnumAliased(
      path, j, "ToneVariant",
      ["Positive": .success, "Danger": .critical, "Negative": .critical, "Neutral": .default])
  }

  static func badgeVariant(_ path: String, _ j: JSON) throws -> BadgeVariant {
    try bareEnumAliased(path, j, "BadgeVariant", ["Default": .neutral, "Danger": .critical])
  }

  static func buttonVariant(_ path: String, _ j: JSON) throws -> ButtonVariant {
    try bareEnumAliased(path, j, "ButtonVariant", ["Danger": .destructive])
  }

  static func headingVariant(_ path: String, _ j: JSON) throws -> HeadingVariant {
    try bareEnumAliased(path, j, "HeadingVariant", ["Default": .standard])
  }

  /// The `Emphasis` style ENUM. Prominence intent survives cross-vocabulary: a
  /// bool in the enum slot projects one-to-one (true ⇒ Loud, false ⇒ Normal);
  /// Strong/Bold ⇒ Loud, Subtle/Muted ⇒ Quiet.
  static func emphasisEnum(_ path: String, _ j: JSON) throws -> Emphasis {
    switch unwrapStaticEnvelope(j) {
    case .bool(true): return .loud
    case .bool(false): return .normal
    default:
      return try bareEnumAliased(
        path, j, "Emphasis",
        ["Strong": .loud, "Bold": .loud, "Subtle": .quiet, "Muted": .quiet])
    }
  }

  /// The behavioural `emphasis` BOOL (Fact / LabelValueRow) — the other half of
  /// the same-name collision with the `Emphasis` style enum. Booleans pass
  /// through; the enum AND its aliases project one-to-one; any other string is
  /// the didactic reject naming both vocabularies.
  static func emphasisFlag(_ path: String, _ j: JSON) throws -> Bool {
    switch unwrapStaticEnvelope(j) {
    case .bool(let b): return b
    case .string(let s):
      switch s {
      case "Loud", "Strong", "Bold": return true
      case "Normal", "Quiet", "Subtle", "Muted": return false
      default:
        throw err(
          .wrongType, path,
          "expected JSON boolean, got '\(s)' — this `emphasis` is a BOOL (is this an emphasised row/fact?); the Emphasis style enum (Quiet|Normal|Loud) lives on style/Metric.emphasis. Write true or false"
        )
      }
    default: throw wrongType(path, "JSON boolean")
    }
  }

  // ── Lenient-ingest field-name aliases (decode-only; §3.6) ─────────────────
  //
  // A curated set of foreign field names decode to the canonical slot when
  // they denote the same concept at the same semantics. The canonical name
  // always WINS when both are present; the nested path always uses the
  // canonical name.

  static func getAliased(_ f: [String: JSON], _ canonical: String, _ aliases: [String]) -> JSON? {
    f[canonical] ?? aliases.lazy.compactMap { f[$0] }.first
  }

  static func reqAliased(
    _ path: String, _ f: [String: JSON], _ canonical: String, _ aliases: [String]
  ) throws -> JSON {
    guard let v = getAliased(f, canonical, aliases) else { throw missing(path, canonical) }
    return v
  }

  static func reqStringAliased(
    _ path: String, _ f: [String: JSON], _ canonical: String, _ aliases: [String]
  ) throws -> String {
    try string("\(path).\(canonical)", try reqAliased(path, f, canonical, aliases))
  }

  static func reqBindingAliased(
    _ path: String, _ f: [String: JSON], _ canonical: String, _ aliases: [String]
  ) throws -> Binding {
    try binding("\(path).\(canonical)", try reqAliased(path, f, canonical, aliases))
  }

  static func reqBindingSlotAliased(
    _ path: String, _ f: [String: JSON], _ canonical: String, _ aliases: [String],
    _ slot: StaticSlot
  ) throws -> Binding {
    try bindingSlot("\(path).\(canonical)", try reqAliased(path, f, canonical, aliases), slot)
  }

  static func reqTextSourceAliased(
    _ path: String, _ f: [String: JSON], _ canonical: String, _ aliases: [String]
  ) throws -> TextSource {
    try textSource("\(path).\(canonical)", try reqAliased(path, f, canonical, aliases))
  }

  static func optTextSourceAliased(
    _ path: String, _ f: [String: JSON], _ canonical: String, _ aliases: [String]
  ) throws -> TextSource? {
    guard let v = getAliased(f, canonical, aliases) else { return nil }
    return try textSource("\(path).\(canonical)", v)
  }

  // ── Stylistic fields omitted-when-default on decode (§3.6, Phase 460) ─────

  static func optCellFormatDefault(_ path: String, _ f: [String: JSON], _ key: String) throws
    -> CellFormat
  {
    guard let v = f[key] else { return .none }
    return try cellFormat("\(path).\(key)", v)
  }

  static func optToneDefault(_ path: String, _ f: [String: JSON], _ key: String) throws
    -> ToneVariant
  {
    guard let v = f[key] else { return .default }
    return try toneVariant("\(path).\(key)", v)
  }

  static func optWeightDefault(_ path: String, _ f: [String: JSON], _ key: String) throws
    -> StyleWeight
  {
    guard let v = f[key] else { return .standard }
    return try bareEnum("\(path).\(key)", v, "StyleWeight")
  }

  static func optEmphasisDefault(_ path: String, _ f: [String: JSON], _ key: String) throws
    -> Emphasis
  {
    guard let v = f[key] else { return .normal }
    return try emphasisEnum("\(path).\(key)", v)
  }

  static func optColumnWidthDefault(_ path: String, _ f: [String: JSON], _ key: String) throws
    -> ColumnWidth
  {
    guard let v = f[key] else { return .auto }
    return try columnWidth("\(path).\(key)", v)
  }

  // ── JSON value passthrough (structured positions, rule 12) ────────────────

  static func jval(_ path: String, _ j: JSON) -> JSON { j }

  static func jvalMap(_ path: String, _ j: JSON) throws -> [String: JSON] {
    try object(path, j)
  }
}

// ── Typed Static payload slots (Phase 429) ───────────────────────────────────

enum StaticSlot {
  case untyped, options, stringOpt, stringList, floatSeq, markers
  /// The 0.2.0 `FormFieldKind.Range` dual-thumb `(min, max)` pair.
  case floatPair

  func placeholder() -> StaticValue {
    switch self {
    case .untyped: return .ast(.string(OPAQUE))
    case .options:
      return .options([SelectOption(value: OPAQUE, label: .literal(OPAQUE))])
    case .stringOpt: return .stringOpt(OPAQUE)
    case .stringList: return .stringList([OPAQUE])
    case .floatSeq: return .floatSeq([])
    case .markers: return .markers([])
    case .floatPair: return .floatPair(0.0, 0.0)
    }
  }

  func parse(_ path: String, _ v: JSON) throws -> StaticValue {
    switch self {
    case .untyped:
      return .ast(v)
    case .options:
      switch v {
      case .null: return .options([])
      case .string(OPAQUE): return placeholder()
      default:
        let items = try Decode.array(path, v)
        return .options(
          try items.enumerated().map { try Decode.selectOption("\(path)[\($0.0)]", $0.1) })
      }
    case .stringOpt:
      switch v {
      case .null: return .stringOpt(nil)
      case .string(let s): return .stringOpt(s)
      default: throw Decode.wrongType(path, "JSON string or null (string option)")
      }
    case .stringList:
      switch v {
      case .null: return .stringList([])
      case .string(OPAQUE): return placeholder()
      default:
        let items = try Decode.array(path, v)
        return .stringList(
          try items.enumerated().map { try Decode.string("\(path)[\($0.0)]", $0.1) })
      }
    case .floatSeq:
      switch v {
      case .null, .string(OPAQUE): return .floatSeq([])
      default:
        let items = try Decode.array(path, v)
        return .floatSeq(
          try items.enumerated().map { try Decode.float("\(path)[\($0.0)]", $0.1) })
      }
    case .markers:
      switch v {
      case .null, .string(OPAQUE): return .markers([])
      default:
        let items = try Decode.array(path, v)
        return .markers(
          try items.enumerated().map { try Decode.mapMarker("\(path)[\($0.0)]", $0.1) })
      }
    case .floatPair:
      switch v {
      // Canonical: the bare `{min, max}` object; lenient: a two-element
      // `[min, max]` array (§3.6 coercion).
      case .object(let pf):
        guard let minJ = pf["min"], let maxJ = pf["max"] else {
          throw Decode.wrongType(path, "object with min and max numbers")
        }
        return .floatPair(
          try Decode.float("\(path).min", minJ), try Decode.float("\(path).max", maxJ))
      case .array(let items) where items.count == 2:
        return .floatPair(
          try Decode.float("\(path)[0]", items[0]), try Decode.float("\(path)[1]", items[1]))
      default:
        throw Decode.wrongType(path, "range pair ({min, max} object or [min, max] array)")
      }
    }
  }
}

// ── Bindings / text / actions ────────────────────────────────────────────────

extension Decode {
  static func selectOption(_ path: String, _ j: JSON) throws -> SelectOption {
    // Lenient AI-ingest shorthand (§5): a bare JSON string `"A"` reads as
    // `{label: "A", value: "A"}` (the HTML `<select>` prior).
    if case .string(let s) = j { return SelectOption(value: s, label: .literal(s)) }
    let f = try object(path, j)
    let value = try reqString(path, f, "value")
    let label = try textSource("\(path).label", try req(path, f, "label"))
    return SelectOption(value: value, label: label)
  }

  static func mapMarker(_ path: String, _ j: JSON) throws -> MapMarker {
    let f = try object(path, j)
    let label = try textSource("\(path).label", try req(path, f, "label"))
    return MapMarker(
      label: label, latitude: try reqFloat(path, f, "latitude"),
      longitude: try reqFloat(path, f, "longitude"))
  }

  static func localFlush(_ path: String, _ j: JSON) throws -> LocalFlushTrigger {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "OnBlur": return .onBlur
    case "OnSubmit": return .onSubmit
    case "OnCommitAction": return .onCommitAction
    case "OnDebounce": return .onDebounce(milliseconds: try reqInt(path, f, "milliseconds"))
    case let o: throw unknownCase(path, o, "OnBlur | OnSubmit | OnDebounce | OnCommitAction")
    }
  }

  static func format(_ path: String, _ j: JSON) throws -> Format {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Number": return .number(decimals: try optInt(path, f, "decimals"))
    case "Currency": return .currency(isoCode: try reqString(path, f, "isoCode"))
    case "Percent": return .percent(decimals: try optInt(path, f, "decimals"))
    case "Date":
      return .date(
        dateStyle: try bareEnum("\(path).dateStyle", try req(path, f, "dateStyle"), "DateStyle"))
    case "RelativeTime":
      return .relativeTime(
        unit: try bareEnum("\(path).unit", try req(path, f, "unit"), "RelativeTimeUnit"))
    case let o: throw unknownCase(path, o, "Number | Currency | Percent | Date | RelativeTime")
    }
  }

  static func localeSource(_ path: String, _ j: JSON) throws -> LocaleSource {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Ambient": return .ambient
    case "Explicit": return .explicit(tag: try reqString(path, f, "tag"))
    case let o: throw unknownCase(path, o, "Ambient | Explicit")
    }
  }

  static func cellFormat(_ path: String, _ j: JSON) throws -> CellFormat {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "None": return .none
    case "Number": return .number(decimals: try optInt(path, f, "decimals"))
    case "Currency": return .currency(code: try reqString(path, f, "code"))
    case "Percent": return .percent(decimals: try optInt(path, f, "decimals"))
    case "SignificantDigits": return .significantDigits(digits: try reqInt(path, f, "digits"))
    case "Date": return .date(format: try reqString(path, f, "format"))
    case "Custom": return .custom
    case let o:
      throw unknownCase(
        path, o, "None | Number | Currency | Percent | SignificantDigits | Date | Custom")
    }
  }

  static func columnWidth(_ path: String, _ j: JSON) throws -> ColumnWidth {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Auto": return .auto
    case "Fixed": return .fixed(pixels: try reqInt(path, f, "pixels"))
    case "Flex": return .flex(weight: try reqFloat(path, f, "weight"))
    case let o: throw unknownCase(path, o, "Auto | Fixed | Flex")
    }
  }

  static func binding(_ path: String, _ j: JSON) throws -> Binding {
    try bindingSlot(path, j, .untyped)
  }

  static func reqBinding(_ path: String, _ f: [String: JSON], _ key: String) throws -> Binding {
    try binding("\(path).\(key)", try req(path, f, key))
  }

  static func reqBindingSlot(
    _ path: String, _ f: [String: JSON], _ key: String, _ slot: StaticSlot
  ) throws -> Binding {
    try bindingSlot("\(path).\(key)", try req(path, f, key), slot)
  }

  static func optBinding(_ path: String, _ f: [String: JSON], _ key: String) throws -> Binding? {
    guard let v = f[key] else { return nil }
    return try binding("\(path).\(key)", v)
  }

  static func bindingSlot(_ path: String, _ j: JSON, _ slot: StaticSlot) throws -> Binding {
    // Lenient AI-ingest shape coercion (§3.6): a bare JSON array or bare
    // SCALAR where a Binding is expected is accepted as `Static` with that
    // value — unambiguous, since every Binding case is a `$type`-discriminated
    // object. Objects stay strict; `null` stays strict.
    switch j {
    case .array, .string, .number, .bool:
      return .staticValue(try slot.parse(path, j))
    default: break
    }
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Static":
      // Phase 677 — absence is structural: a MISSING `value` means the binding
      // carries none. The legacy `"value": null` spelling still decodes (§16
      // shorthand) by routing to the very same per-slot parse, so the two
      // spellings cannot disagree.
      let v = f["value"] ?? .null
      return .staticValue(try slot.parse("\(path).value", v))
    case "Query":
      let name = try reqString(path, f, "name")
      var dependsOn: [String]? = nil
      // Field aliases: deps / dependencies → dependsOn.
      if let v = getAliased(f, "dependsOn", ["deps", "dependencies"]) {
        let items = try array("\(path).dependsOn", v)
        dependsOn = try items.map { try string("\(path).dependsOn[]", $0) }
      }
      return .query(name: name, dependsOn: dependsOn)
    case "Filter":
      // 0.2.0 — optional `defaultValue`, decoded through the slot's typed
      // static parser; a parse failure reads as absent (reference leniency).
      let name = try reqString(path, f, "name")
      let dv = f["defaultValue"].flatMap { try? slot.parse("\(path).defaultValue", $0) }
      return .filter(name: name, defaultValue: dv)
    case "Selection":
      // 0.2.9 — optional `defaultValue`; 0.2.10 — optional `field`.
      let nodeId = try reqString(path, f, "nodeId")
      let dv = f["defaultValue"].flatMap { try? slot.parse("\(path).defaultValue", $0) }
      let field: String?
      if case .string(let s)? = f["field"] { field = s } else { field = nil }
      return .selection(nodeId: nodeId, defaultValue: dv, field: field)
    case "State":
      let key = try reqString(path, f, "key")
      let dv: StaticValue
      // Field aliases: initialValue / default → defaultValue.
      // Phase 677 — an ABSENT default decodes exactly as the legacy
      // `"defaultValue": null` did, so the omitted canonical form and the
      // legacy spelling project identically.
      let rawDefault = getAliased(f, "defaultValue", ["initialValue", "default"]) ?? .null
      dv = (try? slot.parse("\(path).defaultValue", rawDefault)) ?? slot.placeholder()
      return .state(key: key, defaultValue: dv)
    case "Computed": return .computed
    case "I18n":
      let key = try reqString(path, f, "key")
      var args: [NamedBinding]? = nil
      if let v = f["args"] {
        let af = try object("\(path).args", v)
        args = try af.map {
          NamedBinding(name: $0.key, binding: try binding("\(path).args.\($0.key)", $0.value))
        }
      }
      return .i18n(key: key, args: args)
    case "Local":
      let initial = try bindingSlot(
        "\(path).initialFrom", try req(path, f, "initialFrom"), slot)
      let flush: LocalFlushTrigger
      if let v = f["flushOn"] {
        flush = try localFlush("\(path).flushOn", v)
      } else {
        flush = .onBlur
      }
      return .local(flushOn: flush, initialFrom: initial)
    case "Format":
      let source = try binding("\(path).source", try req(path, f, "source"))
      let fmt = try format("\(path).format", try req(path, f, "format"))
      let loc = try localeSource("\(path).locale", try req(path, f, "locale"))
      return .format(format: fmt, locale: loc, source: source)
    case "Transform":
      let source = try dataSource("\(path).source", try req(path, f, "source"))
      let pipeline = try pipelineSteps("\(path).pipeline", try req(path, f, "pipeline"))
      var params: [TransformParam]? = nil
      if let v = f["params"] {
        // Lenient AI-ingest (§3.6): a `{name: <Binding>}` MAP is accepted
        // alongside the canonical `[{from, name}]` array — normalised sorted
        // by name (the reference host's map iteration order).
        if case .object(let mapFields) = v {
          params = try mapFields.sorted { $0.key < $1.key }.map { (name, fromJ) in
            TransformParam(
              name: name, from: try binding("\(path).params.\(name).from", fromJ))
          }
        } else {
          let items = try array("\(path).params", v)
          params = try items.map { item in
            let pf = try object("\(path).params[]", item)
            return TransformParam(
              name: try reqString("\(path).params[]", pf, "name"),
              from: try binding("\(path).params[].from", try req("\(path).params[]", pf, "from"))
            )
          }
        }
      }
      return .transform(params: params, pipeline: pipeline, source: source)
    case "Invoke":
      return .invoke(
        capabilityId: try reqString(path, f, "capabilityId"),
        args: try invokeArgs("\(path).args", try req(path, f, "args")))
    // Lenient AI-ingest: the `TextSource.Bound` wrapper convention transferred
    // to a bare-Binding slot — `{"$type":"Bound","binding":X}` carries exactly
    // one payload field, so the unwrap is one-to-one. Decode-only.
    case "Bound":
      return try bindingSlot("\(path).binding", try req(path, f, "binding"), slot)
    case let o:
      throw unknownCase(
        path, o,
        "Static | Query | Filter | Selection | State | Computed | I18n | Local | Format | Transform | Invoke"
      )
    }
  }

  static func invokeArgs(_ path: String, _ j: JSON) throws -> [InvokeArg] {
    let items = try array(path, j)
    return try items.enumerated().map { (i, item) in
      let f = try object("\(path)[\(i)]", item)
      return InvokeArg(
        addr: try reqString("\(path)[\(i)]", f, "addr"),
        value: try reqString("\(path)[\(i)]", f, "value"))
    }
  }

  static func textSource(_ path: String, _ j: JSON) throws -> TextSource {
    if case .string(let s) = j { return .literal(s) }  // §16 bare-string shorthand
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Literal": return .literal(try reqString(path, f, "text"))
    case "Bound":
      return .bound(try binding("\(path).binding", try req(path, f, "binding")))
    case "I18n":
      let key = try reqString(path, f, "key")
      let args = try f["args"].map { try jvalMap("\(path).args", $0) } ?? [:]
      return .i18n(key: key, args: args)
    case let o: throw unknownCase(path, o, "Literal | Bound | I18n")
    }
  }

  static func reqTextSource(_ path: String, _ f: [String: JSON], _ key: String) throws
    -> TextSource
  {
    try textSource("\(path).\(key)", try req(path, f, key))
  }
  static func optTextSource(_ path: String, _ f: [String: JSON], _ key: String) throws
    -> TextSource?
  {
    guard let v = f[key] else { return nil }
    return try textSource("\(path).\(key)", v)
  }

  static func action(_ path: String, _ j: JSON) throws -> Action {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Dispatch": return .dispatch
    case "Call":
      // Field alias: url → endpoint.
      let endpoint = try reqStringAliased(path, f, "endpoint", ["url"])
      var into: CallResultTarget? = nil
      if let v = f["into"] {
        let ip = "\(path).into"
        let io = try object(ip, v)
        switch try disc(ip, io) {
        case "State": into = .state(key: try reqString(ip, io, "key"))
        case "Query": into = .query(name: try reqString(ip, io, "name"))
        case let o: throw unknownCase(ip, o, "State | Query")
        }
      }
      return .call(endpoint: endpoint, into: into, onResult: optClosure(f, "onResult"))
    case "Notify":
      return .notify(
        channel: try reqString(path, f, "channel"),
        payload: jval("\(path).payload", try req(path, f, "payload")))
    // Field aliases: href (the dominant web name) / url / to → route.
    case "Navigate":
      return .navigate(route: try reqStringAliased(path, f, "route", ["href", "url", "to"]))
    case "SetState":
      return .setState(
        key: try reqString(path, f, "key"),
        value: jval("\(path).value", try req(path, f, "value")))
    case "AiTool":
      return .aiTool(
        toolName: try reqString(path, f, "toolName"),
        args: jval("\(path).args", try req(path, f, "args")))
    case "Chain":
      let items = try array("\(path).ops", try req(path, f, "ops"))
      return .chain(try items.enumerated().map { try action("\(path).ops[\($0.0)]", $0.1) })
    case "CommitLocal": return .commitLocal(nodeId: try reqString(path, f, "nodeId"))
    case "WriteToClipboard": return .writeToClipboard(text: try reqString(path, f, "text"))
    case "ReadFileBody":
      return .readFileBody(
        fileRef: try reqString(path, f, "fileRef"),
        encoding: try bareEnum(
          "\(path).encoding", try req(path, f, "encoding"), "FileReadEncoding"))
    case "Invoke":
      return .invoke(
        capabilityId: try reqString(path, f, "capabilityId"),
        args: try invokeArgs("\(path).args", try req(path, f, "args")))
    case let o:
      throw unknownCase(
        path, o,
        "Dispatch | Call | Notify | Navigate | SetState | AiTool | Chain | CommitLocal | WriteToClipboard | ReadFileBody | Invoke"
      )
    }
  }

  static func reqAction(_ path: String, _ f: [String: JSON], _ key: String) throws -> Action {
    try action("\(path).\(key)", try req(path, f, key))
  }
}
