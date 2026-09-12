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
    // The §21 walk state is created HERE, per call, and threaded down — see the note on
    // `WireWalkState`. One document, one budget; nothing survives between decodes.
    return try Decode.node("$", root, WireWalkState())
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

  /// An unrecognised `$type` DISCRIMINATOR on a `$type`-tagged union. The
  /// document literally carries a `"$type"` member at this position, so the
  /// reject path names it — `WIRE_FORMAT.md` §6: "`$type` appears literally in
  /// the path when the discriminator is at fault (e.g. `$.kind.$type`)".
  ///
  /// Use `unknownEnumCase` for a BARE enum instead — see the note there.
  static func unknownCase(_ path: String, _ got: String, _ expected: String) -> FuaranDecodeError {
    err(.unknownDuCase, "\(path).$type", "unknown discriminator '\(got)'; expected \(expected)")
  }

  /// An unrecognised case of a BARE enum — a plain JSON string in a named field
  /// (`style.tone`, `kind.trendPolarity`, `kind.protection`,
  /// `accessibility.liveRegion`, a `defaultSort.direction`, a
  /// `channel.direction`), with NO `$type` member in the document at that
  /// position. Same `UNKNOWN_DU_CASE` code; the path is the FIELD's own.
  ///
  /// The `.$type` suffix is deliberately absent, and that is the whole point of
  /// this being a second helper (Phase 1073). §6's sentence above is conditioned
  /// on the discriminator being at fault; a bare enum has no discriminator on
  /// the wire, so `$.style.tone.$type` names a JSON member the document does not
  /// contain — an author reading the refusal has nowhere to go and edits a key
  /// that is not there. The conformance corpus already records the distinction
  /// correctly; this host emitted one shape for both populations and the
  /// divergence survived only because the reject harness matches the expected
  /// path by PREFIX, under which a spurious suffix reads as a pass.
  static func unknownEnumCase(_ path: String, _ got: String, _ expected: String)
    -> FuaranDecodeError
  {
    err(.unknownDuCase, path, "unknown discriminator '\(got)'; expected \(expected)")
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
    // §7.1 — the integer-slot accept set is a FINITE JSON number with NO
    // fractional part, inside the signed 32-bit range.
    //
    // `2.0` decodes as `2`: the two denote the same integer, and refusing the
    // first would refuse a document whose intent is unambiguous, for its
    // spelling. `2.5` is a WRONG_TYPE rather than a truncation, which silently
    // discarded the author's value at a slot the author chose to type as an
    // integer. And `1e10` is a WRONG_TYPE rather than a cast: that is the row
    // that was measured across hosts, since a saturating cast on one runtime
    // and an implementation-defined one on another turned the same bytes into
    // two different integers.
    //
    // `Int(Double)` also TRAPS on a non-finite value or one outside `Int`'s
    // range, and a Swift trap is not catchable — `1e999` in any integer slot
    // ended the host process before a guard existed here (found by the decoder
    // fuzz leg). The range check below subsumes that.
    guard n.isFinite else {
      throw wrongType(
        path,
        "JSON number (integer — an integer slot has no non-finite form)")
    }
    guard n.rounded(.towardZero) == n else {
      throw wrongType(
        path,
        "JSON number (integer — an integer slot holds no fraction, and truncating would discard "
          + "a value the author typed)")
    }
    guard n >= -2_147_483_648.0, n <= 2_147_483_647.0 else {
      throw wrongType(
        path,
        "JSON number (integer — within the signed 32-bit range; a value the slot cannot hold is "
          + "not a value to be reinterpreted)")
    }
    return Int(n)
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
    // A bare enum, by construction — this reader consumes a plain string, never
    // a `$type` object — so the refusal reports at the FIELD's own path.
    throw unknownEnumCase(path, s, "\(label): \(names)")
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

  /// §3.6.1 — absent is `HigherIsBetter`. An unrecognised spelling (`Neutral`
  /// included, and on purpose) still fails `UNKNOWN_DU_CASE` with the canonical
  /// two-name list, because `bareEnum` builds its expected list from the case
  /// set and the case set is the accepted wire set.
  static func optTrendPolarityDefault(_ path: String, _ f: [String: JSON], _ key: String) throws
    -> TrendPolarity
  {
    guard let v = f[key] else { return .higherIsBetter }
    return try bareEnum("\(path).\(key)", v, "TrendPolarity")
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

  /// A host-opaque JSON payload slot (`SetState.value`, `Notify.payload`,
  /// `AiTool.args`, a `Custom` prop). The value is held raw — the projection
  /// never interprets it — but an explicit `null` is NOT a payload. The wire
  /// spells absence by omitting the key, so a `null` here is a malformed
  /// document, and accepting it hands the embedding app a slot that claims to
  /// carry a value and does not. The corpus pins this as the
  /// `reject-null-action-*` / `reject-null-custom-prop` / `reject-null-i18n-arg`
  /// family.
  static func jval(_ path: String, _ j: JSON) throws -> JSON {
    guard case .null = j else { return j }
    throw wrongType(
      path, "a JSON value (an explicit null is not a payload — omit the key instead)")
  }

  /// A string-keyed map of host-opaque payload values (`Custom.props`). The
  /// same rule, applied per ENTRY so the refusal names the offending key rather
  /// than the whole map.
  static func jvalMap(_ path: String, _ j: JSON) throws -> [String: JSON] {
    let f = try object(path, j)
    for (key, v) in f.sorted(by: { $0.key < $1.key }) {
      _ = try jval("\(path).\(key)", v)
    }
    return f
  }

  /// A `TextSource.I18n` argument bag — discriminated BY INSPECTION (§5, Phase
  /// 1661). An argument is a `Binding<JSON>`, not a bare value, and the wire
  /// carries no tag saying which of the two arms one is:
  ///
  ///  * an object carrying a `$type` member is the BINDING form;
  ///  * every other JSON value is the LITERAL form, governed by rule 12 exactly
  ///    as the whole bag was before the slot widened.
  ///
  /// This projection still holds the bag RAW, and that is a statement about
  /// what a render projection over the Rust reference core needs rather than a
  /// shortcut: it never resolves an argument, and a bound one has no value on
  /// the wire to hold. What inspecting the `$type` buys is the REFUSALS — an
  /// unrecognised binding case, or a known case with a required member missing
  /// — reported at the ARGUMENT's own path, which is where an author reading
  /// the refusal has to go.
  ///
  /// `jvalMap` could raise neither, because it only ever asked whether an entry
  /// was an explicit null: `{"$type":"Nope"}` and a `{"$type":"State"}` with no
  /// `key` both decoded here while every codec host refused the document.
  /// Falling back to the literal reading for an unknown case is not an option
  /// the format leaves open — it would substitute a discriminator's own text
  /// into a sentence a reader reads.
  static func i18nArgs(_ path: String, _ j: JSON) throws -> [String: JSON] {
    let f = try object(path, j)
    // Sorted by name, as the `Binding.I18n` arm already is: a Swift dictionary's
    // iteration order is not a property of the document, so with two invalid
    // entries an unsorted walk reports a different REFUSAL on every call.
    for (key, v) in f.sorted(by: { $0.key < $1.key }) {
      let argPath = "\(path).\(key)"
      if case .object(let arg) = v, arg["$type"] != nil {
        // Decoded for its refusals; the raw entry is what the bag keeps.
        _ = try binding(argPath, v)
      } else {
        _ = try jval(argPath, v)
      }
    }
    return f
  }
}

// ── Typed Static payload slots (Phase 429) ───────────────────────────────────

enum StaticSlot {
  case untyped, options, stringOpt, stringList, floatSeq, markers
  /// A `Binding<string>` slot. The parsed payload still rides as `.ast`, so no
  /// projected value and no decoded shape changes — what the slot adds is the
  /// TYPE CHECK the reference host has always applied. §3.6's bare-scalar
  /// coercion is about SHAPE; the slot's own `'T` still governs the value,
  /// which is why `"hidden": "yes"` must be refused even though
  /// `"label": "Home"` is sanctioned shorthand.
  case str
  /// A `Binding<bool>` slot — the `.str` reasoning at the other scalar type.
  case bool
  /// A `Binding<float>` slot. §7's float admits `{ JSON number }` ∪ the three
  /// sentinel spellings `"NaN"` / `"Infinity"` / `"-Infinity"` — those tokens
  /// EXACTLY, case-sensitive — and nothing else. The exactness is the whole
  /// content of the rule: `"nan"` is a WRONG_TYPE, not a lenient spelling, and
  /// a boolean is one too. (This surface parses JSON with its own hand parser,
  /// so a `true` arrives as `.bool` and can never answer a numeric test — the
  /// `NSNumber` trap a `JSONSerialization` decoder would carry does not exist
  /// here.)
  case float
  /// A `Binding<int>` slot. §7's integer admits `{ JSON number }` ONLY,
  /// truncating via an integer cast. It has **no** non-finite form, so `"NaN"`
  /// at an int slot is a WRONG_TYPE even though the identical token is
  /// admissible one slot type over — which is exactly why `.int` cannot be
  /// `.float`'s alias.
  case int
  /// The 0.2.0 `FormFieldKind.Range` dual-thumb `(min, max)` pair.
  case floatPair
  /// The 0.7.0 `FormFieldKind.DateRange` ordered `(from, to)` ISO-8601 pair.
  case stringPair

  func placeholder() -> StaticValue {
    switch self {
    case .untyped: return .ast(.string(OPAQUE))
    // The reference host's typed fallbacks (`""` / `false`), so an absent
    // `State.defaultValue` at a scalar slot agrees with it.
    case .str: return .ast(.string(""))
    case .bool: return .ast(.bool(false))
    // The reference host's typed numeric fallbacks (`0.0` / `0`).
    case .float, .int: return .ast(.number(0))
    case .options:
      return .options([SelectOption(value: OPAQUE, label: .literal(OPAQUE))])
    case .stringOpt: return .stringOpt(OPAQUE)
    case .stringList: return .stringList([OPAQUE])
    case .floatSeq: return .floatSeq([])
    case .markers: return .markers([])
    case .floatPair: return .floatPair(0.0, 0.0)
    case .stringPair: return .stringPair("", "")
    }
  }

  func parse(_ path: String, _ v: JSON) throws -> StaticValue {
    switch self {
    case .untyped:
      return .ast(v)
    case .str:
      return .ast(.string(try Decode.string(path, v)))
    case .bool:
      return .ast(.bool(try Decode.bool(path, v)))
    // `.float` / `.int` validate through the reference host's `requireFloat` /
    // `requireInt`, then ride the AUTHORED payload unchanged — the slot adds a
    // type check, not a normalisation, exactly as `.str` / `.bool` do. Riding
    // it raw is what keeps a sentinel a sentinel: `"NaN"` stays
    // `.string("NaN")` in the projection rather than collapsing to a
    // `.number(nan)` the renderer's number paths would then have to
    // special-case. Truncation of an int slot likewise stays where it already
    // happens — at the point of consumption.
    case .float:
      _ = try Decode.float(path, v)
      return .ast(v)
    case .int:
      _ = try Decode.int(path, v)
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
    case .stringPair:
      // Didactic domain rule: a LITERAL pair must be ordered. Same-variant
      // ISO-8601 strings sort lexicographically in chronological order, so
      // Swift's `>` on String — which compares Unicode scalar values — is an
      // ordinal compare, total for every variant with no date parsing and no
      // locale. Only a literal pair is checked; a bound pair's ordering is a
      // runtime concern.
      func ordered(_ from: String, _ to: String) throws -> StaticValue {
        if from > to {
          throw Decode.err(
            .wrongType, path,
            "date-range start '\(from)' is after end '\(to)' — a DateRange pair is ordered "
              + "(from <= to); ISO-8601 strings of one variant compare lexicographically, "
              + "so swap the two values")
        }
        return .stringPair(from, to)
      }
      switch v {
      // Canonical: the bare `{from, to}` object; lenient: a two-element
      // `[from, to]` array (§3.6 coercion).
      case .object(let pf):
        guard let fromJ = pf["from"], let toJ = pf["to"] else {
          throw Decode.wrongType(path, "object with from and to ISO-8601 strings")
        }
        return try ordered(
          try Decode.string("\(path).from", fromJ), try Decode.string("\(path).to", toJ))
      case .array(let items) where items.count == 2:
        return try ordered(
          try Decode.string("\(path)[0]", items[0]), try Decode.string("\(path)[1]", items[1]))
      default:
        throw Decode.wrongType(path, "date-range pair ({from, to} object or [from, to] array)")
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
    // Phase 1533 — `unit` is OPTIONAL here and its absence is the
    // auto-selection request, not a default. Present-but-unreadable is still a
    // refusal.
    case "Since":
      var sinceUnit: RelativeTimeUnit? = nil
      if let u = f["unit"] {
        sinceUnit = try bareEnum("\(path).unit", u, "RelativeTimeUnit")
      }
      return .since(unit: sinceUnit)
    case "Duration":
      return .duration(
        unit: try bareEnum("\(path).unit", try req(path, f, "unit"), "DurationUnit"),
        style: try bareEnum("\(path).style", try req(path, f, "style"), "DurationStyle"))
    case let o:
      throw unknownCase(
        path, o, "Number | Currency | Percent | Date | RelativeTime | Since | Duration")
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
    case "Duration":
      return .duration(
        unit: try bareEnum("\(path).unit", try req(path, f, "unit"), "DurationUnit"),
        style: try bareEnum("\(path).style", try req(path, f, "style"), "DurationStyle"))
    case "RelativeTime":
      return .relativeTime(
        unit: try bareEnum("\(path).unit", try req(path, f, "unit"), "RelativeTimeUnit"))
    case "Custom": return .custom
    case let o:
      throw unknownCase(
        path, o,
        "None | Number | Currency | Percent | SignificantDigits | Date | Duration | RelativeTime | Custom"
      )
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

  static func optBindingSlot(
    _ path: String, _ f: [String: JSON], _ key: String, _ slot: StaticSlot
  ) throws -> Binding? {
    guard let v = f[key] else { return nil }
    return try bindingSlot("\(path).\(key)", v, slot)
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
    // The host-furnished instant - no payload; the host clock supplies the value.
    // Phase 1533 — the declared `grain` is the one wire field, optional, absent
    // meaning `Second`. Present-but-unreadable is a REFUSAL rather than a
    // silent fallback to the default: a document naming a grain the host cannot
    // honour must not be rendered at a neighbouring resolution in silence.
    case "Now":
      var grain: TimeGrain? = nil
      if let g = f["grain"] {
        grain = try bareEnum("\(path).grain", g, "TimeGrain")
      }
      return .now(grain: grain)
    case "I18n":
      let key = try reqString(path, f, "key")
      var args: [NamedBinding]? = nil
      if let v = f["args"] {
        let af = try object("\(path).args", v)
        // Sorted by name, as `Transform.params` and `jvalMap` already are: a Swift
        // dictionary's iteration order is not a property of the document, and an
        // unsorted map here decoded the same bytes to a different argument order —
        // and, with two invalid entries, to a different REFUSAL — on every call.
        args = try af.sorted(by: { $0.key < $1.key }).map {
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
      // §3.3.3 — the buffer's own codec REPLACES the identity on both sides:
      // `format` renders through it, `parse` inverts it. The admitted set is
      // therefore the `Format` cases with a TOTAL, LOCALE-INDEPENDENT inverse,
      // and today that is `Number` alone. Every other case is refused with a
      // stated reason rather than by omission — `Currency` prepends a
      // locale-chosen symbol, `Date`'s styles are locale renditions with no
      // parse, and `Percent` (the one that looks admissible) needs a ×100 scale
      // whose IEEE round trip is not exact, so admitting it would mean
      // specifying a rounding to the bit on every host.
      var codec: Format? = nil
      if let c = f["codec"] {
        let decoded = try format("\(path).codec", c)
        guard case .number = decoded else {
          throw wrongType(
            "\(path).codec",
            "a Format with a total, locale-independent inverse — Number alone, since whatever "
              + "the buffer renders it must also parse back from what the reader typed")
        }
        codec = decoded
      }
      let onCommit = optClosure(f, "onCommit")
      let commitTo = try optString(path, f, "commitTo")
      // Mutually exclusive, and a refusal rather than a precedence rule: the
      // wire cannot carry the closure — it is `"<closure>"` and nothing more —
      // so a host honouring `onCommit` and a host honouring `commitTo` would
      // write to different places from identical bytes.
      if onCommit != nil && commitTo != nil {
        throw wrongType(
          "\(path).commitTo",
          "exactly one of 'onCommit' and 'commitTo' — the wire cannot carry the closure, so two "
            + "hosts would write to different places from identical bytes")
      }
      return .local(
        codec: codec, commitTo: commitTo, flushOn: flush, initialFrom: initial,
        onCommit: onCommit)
    case "Format":
      let source = try binding("\(path).source", try req(path, f, "source"))
      let fmt = try format("\(path).format", try req(path, f, "format"))
      let loc = try localeSource("\(path).locale", try req(path, f, "locale"))
      return .format(format: fmt, locale: loc, source: source)
    case "Transform":
      let source = try dataSource("\(path).source", try req(path, f, "source"))
      let pipeline = try pipelineSteps("\(path).pipeline", try req(path, f, "pipeline"))
      return .transform(
        params: try bindingParams(path, f), pipeline: pipeline, source: source)
    // Phase 1534 (§3.3.2) — ONE scalar expression evaluated to ONE value. The
    // expression is the SAME `ColExpr` algebra a `Transform` pipeline step
    // carries, decoded by the same codec, so there is one algebra to specify,
    // certify and teach rather than two that drift apart.
    case "Expr":
      let exprPath = "\(path).expr"
      let e = try colExpr(exprPath, try req(path, f, "expr"))
      // §21.8 — the evaluation bound, counted per EXPRESSION rather than per
      // document. Its scope is EVERY expression a decoded document can name, so
      // a pipeline's `derive` / `filter` expressions take the same bound where
      // they are decoded (Phase 1662). This comment named them as deliberately
      // NOT covered until Phase 1677, which is exactly what made the bound
      // bypassable: the same expression refused here was accepted by wrapping
      // it in a `Transform`.
      try checkExprBound(exprPath, e)
      let exprParams = try bindingParams(path, f)
      // The two refusals, both because an `Expr` HAS NO ROW. Left admitted,
      // each would decode to an expression whose evaluation could only ever
      // fail, once per render, on every host — so they are decode-time and
      // unconditional rather than resolution-time.
      if let offender = firstColReference(e) {
        throw wrongType(
          exprPath,
          "no column reference — a Binding.Expr evaluates against its params alone and has no "
            + "frame for '\(offender)' to read; the remedy is a different BINDING, not a "
            + "different spelling, and Binding.Transform is the case that supplies the frame")
      }
      let bound = Set((exprParams ?? []).map { $0.name })
      // Statically decidable HERE where it is not for `Transform`, whose
      // unbound filter params are PRUNED under the deliberate "unset chip ⇒ no
      // constraint" leniency: an `Expr` has no step to prune and no rows to
      // fall back on, so an unbound reference has no value it could ever take.
      if let unbound = firstUnboundParam(e, bound) {
        throw wrongType(
          exprPath,
          "every referenced param to be bound by the binding's own params list — '\(unbound)' "
            + "is not")
      }
      return .expr(expr: e, params: exprParams)
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
      let args = try f["args"].map { try i18nArgs("\(path).args", $0) } ?? [:]
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
        payload: try jval("\(path).payload", try req(path, f, "payload")))
    // Field aliases: href (the dominant web name) / url / to → route.
    //
    // Phase 1536 — the route is a `TextSource`, so a tree can name a
    // destination it computes from what the reader is looking at. The bare JSON
    // string IS `Literal`'s canonical form, so every document written before
    // the widening decodes exactly as it did — aliases included, since they
    // resolve before the value is decoded. `target` is omitted at `Self`.
    case "Navigate":
      var navTarget = NavigateTarget.selfWindow
      if let t = f["target"] {
        navTarget = try bareEnum("\(path).target", t, "NavigateTarget")
      }
      return .navigate(
        route: try reqTextSourceAliased(path, f, "route", ["href", "url", "to"]),
        target: navTarget)
    case "SetState":
      // `oneOf: [required value, required valueFrom]` - a literal payload OR a binding
      // resolved at dispatch time, never both. Both-present is refused rather than settled
      // by precedence: the two say different things about where the value comes from, and
      // silently preferring one hands the emitter a write it did not ask for.
      let rawValue = f["value"]
      let rawFrom = f["valueFrom"]
      if rawValue != nil && rawFrom != nil {
        throw wrongType(
          "\(path).valueFrom", "a SetState to carry `value` or `valueFrom`, not both")
      }
      if rawValue == nil && rawFrom == nil { throw missing(path, "value") }
      var setValue: JSON? = nil
      if let rv = rawValue { setValue = try jval("\(path).value", rv) }
      var setFrom: Binding? = nil
      if let rf = rawFrom { setFrom = try binding("\(path).valueFrom", rf) }
      return .setState(
        key: try reqString(path, f, "key"), value: setValue, valueFrom: setFrom)
    case "AiTool":
      return .aiTool(
        toolName: try reqString(path, f, "toolName"),
        args: try jval("\(path).args", try req(path, f, "args")))
    case "Chain":
      let items = try array("\(path).ops", try req(path, f, "ops"))
      return .chain(try items.enumerated().map { try action("\(path).ops[\($0.0)]", $0.1) })
    case "CommitLocal": return .commitLocal(nodeId: try reqString(path, f, "nodeId"))
    // Phase 1126 — the payload is a `TextSource`; the bare string IS
    // `Literal`'s canonical form, so the explicit envelope normalises down to
    // it here as at every other text slot (§16). Never coerced from a non-text
    // JSON value: a host reading the widening as "this member is now open"
    // would put a JSON literal on the reader's clipboard.
    case "WriteToClipboard": return .writeToClipboard(text: try reqTextSource(path, f, "text"))
    // Phase 1124 — the payload-free print, and the ONE action arm strict about
    // unrecognised members. Everywhere else in this format an unknown member is
    // one the reading host has not learned yet, and dropping it is the
    // forward-compatible answer; here there is nothing to learn, so accepting
    // `{"$type":"Print","pageRange":"1-3"}` would leave the emitter believing
    // it had constrained a printing it had not. The refusal names the offending
    // member's own path, taking the FIRST in sorted order so which member is
    // named is deterministic rather than a function of dictionary order.
    case "Print":
      let extras = f.keys.filter { $0 != "$type" }.sorted()
      if let first = extras.first {
        throw wrongType("\(path).\(first)", "no member beside $type — Print takes no payload")
      }
      return .print
    // Phase 1537 — ask, then act. The DEPTH-ONE REFUSAL is the substance of
    // this arm: a `Confirm` reachable from either continuation is refused, and
    // the check walks the DECODED continuation rather than its immediate
    // `$type`, so a nested confirm inside a `Chain` is caught by the same line
    // that catches a bare one. A dialogue that answers a dialogue is a modal
    // stack the reader cannot escape, and it says nothing one question does not.
    case "Confirm":
      let prompt = try reqTextSource(path, f, "prompt")
      let onConfirm = try action("\(path).onConfirm", try req(path, f, "onConfirm"))
      try refuseNestedConfirm(onConfirm, "\(path).onConfirm")
      var onCancel: Action? = nil
      if let c = f["onCancel"] {
        let decoded = try action("\(path).onCancel", c)
        try refuseNestedConfirm(decoded, "\(path).onCancel")
        onCancel = decoded
      }
      return .confirm(prompt: prompt, onConfirm: onConfirm, onCancel: onCancel)
    // Phase 1537 — a bare node id, the `CommitLocal` shape above. It addresses
    // a node in THIS document, so there is nothing for a binding to compute.
    case "Focus": return .focus(nodeId: try reqString(path, f, "nodeId"))
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
        "Dispatch | Call | Notify | Navigate | SetState | AiTool | Chain | CommitLocal | WriteToClipboard | Print | Confirm | Focus | ReadFileBody | Invoke"
      )
    }
  }

  /// Phase 1537 — fail when a `confirm` is reachable from `action`.
  /// Confirmation is bounded at ONE question: a dialogue that answers a
  /// dialogue is a modal stack the reader cannot escape, and it expresses no
  /// intent a single question does not.
  ///
  /// It walks the DECODED action rather than raw JSON, and descends `chain`,
  /// because a chain is otherwise a hiding place — a check written against the
  /// continuation's immediate `$type` passes a nested confirm one level down.
  static func refuseNestedConfirm(_ a: Action, _ path: String) throws {
    switch a {
    case .confirm:
      throw wrongType(
        path,
        "no Confirm inside another Confirm's continuation — confirmation is bounded at one "
          + "question")
    case .chain(let ops):
      for (i, inner) in ops.enumerated() {
        try refuseNestedConfirm(inner, "\(path).ops[\(i)]")
      }
    default: return
    }
  }

  static func reqAction(_ path: String, _ f: [String: JSON], _ key: String) throws -> Action {
    try action("\(path).\(key)", try req(path, f, key))
  }

  /// The `params` slot shared by `Binding.transform` and `Binding.expr` — ONE
  /// decoder, because §3.3.2 makes it the SAME slot following the same rules,
  /// and two copies would drift on the lenient form below.
  ///
  /// Lenient AI-ingest (§3.6): a `{name: <Binding>}` MAP is accepted alongside
  /// the canonical `[{from, name}]` array — normalised to the array form sorted
  /// by name (the reference host's map iteration order). Omitted when empty.
  static func bindingParams(_ path: String, _ f: [String: JSON]) throws -> [TransformParam]? {
    guard let v = f["params"] else { return nil }
    if case .object(let mapFields) = v {
      return try mapFields.sorted { $0.key < $1.key }.map { (name, fromJ) in
        TransformParam(name: name, from: try binding("\(path).params.\(name).from", fromJ))
      }
    }
    let items = try array("\(path).params", v)
    return try items.map { item in
      let pf = try object("\(path).params[]", item)
      return TransformParam(
        name: try reqString("\(path).params[]", pf, "name"),
        from: try binding("\(path).params[].from", try req("\(path).params[]", pf, "from")))
    }
  }

  /// Every direct sub-expression of `e`, so the three walks below share one
  /// definition of the shape and cannot disagree about which arms recurse.
  static func exprChildren(_ e: ColExpr) -> [ColExpr] {
    switch e {
    case .col, .param, .lit: return []
    case .binary(_, let l, let r): return [l, r]
    case .not(let x), .cast(_, let x), .isNull(let x): return [x]
    case .coalesce(let xs): return xs
    case .apply(_, let xs): return xs
    case .caseExpr(let cases, let elseExpr):
      return cases.flatMap { [$0.when, $0.then] } + [elseExpr]
    case .inList(let subject, let items): return [subject] + items
    case .inParam(let subject, _): return [subject]
    }
  }

  /// The `ColExpr` node count of one expression — the subject of §21.8's
  /// `maxExprNodes`, counted per EXPRESSION rather than per document.
  static func countExprNodes(_ e: ColExpr) -> Int {
    1 + exprChildren(e).reduce(0) { $0 + countExprNodes($1) }
  }

  /// §21.8's evaluation bound over ONE decoded expression, refused at the path
  /// of the member that carries it so an author is told which expression — and,
  /// in a pipeline, which STEP — to come back under.
  ///
  /// Shared by the three positions the bound covers, so there is ONE definition
  /// of it rather than one per arm: a `Binding.expr`'s `expr`, a pipeline
  /// `derive` step's `expr`, and a pipeline `filter` step's `pred`. Those three
  /// are the whole surface — no other step carries an expression, and a `join`
  /// / `union` / `intersect` / `except` operand is a data source rather than
  /// another pipeline — so this bounds every expression a decoded document can
  /// name, which is what §21.8 asks and what a scope naming only the binding
  /// could not deliver.
  ///
  /// Taken at DECODE and not left to the evaluator, because this projection
  /// hands a decoded tree to the Rust core and to an embedding app: a document
  /// that DECODES must not be able to name an unbounded evaluation, whoever
  /// runs it and whenever.
  static func checkExprBound(_ path: String, _ e: ColExpr) throws {
    let nodes = countExprNodes(e)
    if nodes > WireLimits.maxExprNodes {
      throw err(
        .limitExceeded, path,
        "expression carries \(nodes) nodes, above the \(WireLimits.maxExprNodes) one expression "
          + "may hold (WIRE_FORMAT.md §21.8)")
    }
  }

  /// The first `col` reference reachable in `e`, if any (§3.3.2 refusal 1).
  static func firstColReference(_ e: ColExpr) -> String? {
    if case .col(let name) = e { return name }
    for child in exprChildren(e) {
      if let found = firstColReference(child) { return found }
    }
    return nil
  }

  /// The first param name `e` references that `bound` does not carry, if any
  /// (§3.3.2 refusal 2). `inParam`'s name is a param too — it is the LIST
  /// spelling of the same reference, so leaving it out would admit an unbound
  /// membership test through the one arm that reads a param without being one.
  static func firstUnboundParam(_ e: ColExpr, _ bound: Set<String>) -> String? {
    switch e {
    case .param(let name) where !bound.contains(name): return name
    case .inParam(_, let name) where !bound.contains(name): return name
    default: break
    }
    for child in exprChildren(e) {
      if let found = firstUnboundParam(child, bound) { return found }
    }
    return nil
  }
}
