// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// GENERATED from the wire corpus's `idl.json` by `Sources/FuaranUIIdlGen` — do not edit.
// The rules, and the dialect this surface keeps over them, are in that directory.
//
//   idl.json sha256: c0ca90a68de458ae90cc369c5afe6e75cf0a1b36d8383579a0f48073ef8157d8
//
// Regenerate with
//   FUARAN_IDL_REGENERATE=1 swift test --filter GeneratedModelTests
// or `swift run fuaran-idl-gen`. Without the variable the same test is the drift
// check, red when the corpus IDL has moved and this file has not.

import Foundation

/// The IDL this model was generated from.
enum GeneratedModel {
  /// The SHA-256 of the `idl.json` bytes.
  static let idlSha256 = "c0ca90a68de458ae90cc369c5afe6e75cf0a1b36d8383579a0f48073ef8157d8"
}

// ── Bare-string enums: the `rawValue` is the wire spelling ───────────────────

public enum BadgeVariant: String, CaseIterable, Equatable, Sendable {
  case neutral = "Neutral"
  case brand = "Brand"
  case success = "Success"
  case warning = "Warning"
  case critical = "Critical"
  case info = "Info"
}

public enum BoxRole: String, CaseIterable, Equatable, Sendable {
  case dashboard = "Dashboard"
  case card = "Card"
  case group = "Group"
  case separator = "Separator"
}

public enum ButtonVariant: String, CaseIterable, Equatable, Sendable {
  case primary = "Primary"
  case secondary = "Secondary"
  case tertiary = "Tertiary"
  case destructive = "Destructive"
}

/// Phase 1116 — the recording device a `FileUpload` asks the platform for
/// (§3.6.18). There is deliberately no display-capture case and there will not
/// be one by widening this member: a screen capture reaches every window the
/// reader has open rather than one device behind the picker.
public enum CaptureSource: String, CaseIterable, Equatable, Sendable {
  case camera = "Camera"
  case microphone = "Microphone"
}

public enum ChannelDirection: String, CaseIterable, Equatable, Sendable {
  case outOnly = "OutOnly"
  case twoWay = "TwoWay"
}

public enum ChartKind: String, CaseIterable, Equatable, Sendable {
  case line = "Line"
  case bar = "Bar"
  case area = "Area"
  case pie = "Pie"
  case scatter = "Scatter"
  case heatmap = "Heatmap"
}

/// `CompareRule.op` — the cross-field comparison operator.
public enum CompareOp: String, CaseIterable, Equatable, Sendable {
  case eq = "eq"
  case neq = "neq"
  case lt = "lt"
  case lte = "lte"
  case gt = "gt"
  case gte = "gte"
}

public enum DateStyle: String, CaseIterable, Equatable, Sendable {
  case short = "Short"
  case medium = "Medium"
  case long = "Long"
  case full = "Full"
}

/// Phase 1811 — `DateTimeVariant` (was `DateVariant`): the temporal breadth of a
/// `dateTime` / `dateTimeRange` field. The three cases did not move.
public enum DateTimeVariant: String, CaseIterable, Equatable, Sendable {
  case date = "Date"
  case time = "Time"
  case dateTime = "DateTime"
}

public enum DeterminismSource: String, CaseIterable, Equatable, Sendable {
  case deterministic = "Deterministic"
  case clock = "Clock"
  case random = "Random"
  case network = "Network"
}

/// How a `Duration` renders: `1h 5m` / `01:05:00` / `1 hour 5 minutes`.
public enum DurationStyle: String, CaseIterable, Equatable, Sendable {
  case compact = "Compact"
  case clock = "Clock"
  case long = "Long"
}

public enum DurationUnit: String, CaseIterable, Equatable, Sendable {
  case seconds = "Seconds"
  case minutes = "Minutes"
  case hours = "Hours"
}

/// `EmbedSpec.permissions` — the closed list of sandbox relaxations an embed may
/// request (WIRE_FORMAT.md §3.6.8, Phase 1111). Bare strings on the wire, and
/// the list is OMITTED at empty — which means TOTAL DENIAL, so the wire-cheapest
/// document is also the most locked-down one.
///
/// **Declaration order here IS the render order.** §3.6.8 obligation 2 fixes the
/// emitted token order at the vocabulary's declaration order rather than the
/// document's, so two documents naming the same set render identically; the
/// `CaseIterable` order below is that order, and the projection reads it rather
/// than carrying a second list.
///
/// **Two relaxations are excluded rather than defaulted off, and are not
/// reserved either**: a top-level-navigation relaxation would let a framed
/// document navigate the page that framed it, and a downloads relaxation would
/// put a file-save prompt in a third party's hands. Neither is admitted and
/// neither is a name a later phase should take — which is why
/// `"allow-top-navigation"`, the token an author reaches for from memory, is
/// refused as `UNKNOWN_DU_CASE` rather than aliased.
public enum EmbedPermission: String, CaseIterable, Equatable, Sendable {
  case allowScripts = "AllowScripts"
  case allowSameOrigin = "AllowSameOrigin"
  case allowForms = "AllowForms"
  case allowFullscreen = "AllowFullscreen"
}

public enum Emphasis: String, CaseIterable, Equatable, Sendable {
  case quiet = "Quiet"
  case normal = "Normal"
  case loud = "Loud"
}

public enum FileReadEncoding: String, CaseIterable, Equatable, Sendable {
  case text = "Text"
  case base64 = "Base64"
  case dataUrl = "DataUrl"
}

public enum FontVoice: String, CaseIterable, Equatable, Sendable {
  case `default` = "Default"
  case display = "Display"
  case structural = "Structural"
}

public enum HashStrictness: String, CaseIterable, Equatable, Sendable {
  case strictReplay = "StrictReplay"
  case advisoryWarning = "AdvisoryWarning"
  case enforced = "Enforced"
}

public enum HeadingVariant: String, CaseIterable, Equatable, Sendable {
  case standard = "Standard"
  case eyebrow = "Eyebrow"
  case caption = "Caption"
  case lead = "Lead"
}

public enum HostEffect: String, CaseIterable, Equatable, Sendable {
  case pure = "Pure"
  case readsHost = "ReadsHost"
  case writesHost = "WritesHost"
}

/// The rendered size of a standalone `Icon`. Omitted on the wire at `Medium`.
public enum IconSize: String, CaseIterable, Equatable, Sendable {
  case small = "Small"
  case medium = "Medium"
  case large = "Large"
}

/// The box the element reserves BEFORE the image arrives (§3.6.2). Omitted on
/// the wire at `Natural`.
///
/// A LAYOUT reservation, not a crop — what happens to pixels that do not match
/// the box is `ImageFit`'s statement, and neither is derived from the other.
/// Four named ratios, never a number, a pair, or the stylesheet spelling
/// (`"16 / 9"`, `"16:9"`, `1.7778`); the corpus's `reject-unknown-image-aspect`
/// fixture pins that refusal at the bare slot.
public enum ImageAspect: String, CaseIterable, Equatable, Sendable {
  case natural = "Natural"
  case square = "Square"
  case fourThree = "FourThree"
  case threeTwo = "ThreeTwo"
  case sixteenNine = "SixteenNine"
}

/// How the decoded pixels fill the box the layout gives the element (§3.6.2).
/// Omitted on the wire at `Natural`.
///
/// A TOKEN, never a CSS value — the vocabulary is closed at three, so an
/// author-supplied `object-fit` string has nowhere to land. That is the point:
/// admitting one would put a free-form style value on the wire, which is the
/// escape this format does not have.
public enum ImageFit: String, CaseIterable, Equatable, Sendable {
  case natural = "Natural"
  case cover = "Cover"
  case contain = "Contain"
}

/// Whether a fetching host loads the image during initial load or defers it
/// (§3.6.2). Omitted on the wire at `Eager`.
///
/// `Eager` is the default deliberately, and it is not the "unoptimised" value:
/// deferring an above-the-fold image delays the largest contentful paint rather
/// than helping it, and only the author knows where the image sits. A host MUST
/// NOT infer laziness from position, viewport, or anything else the tree does
/// not say.
public enum ImageLoading: String, CaseIterable, Equatable, Sendable {
  case eager = "Eager"
  case `lazy` = "Lazy"
}

public enum ImageVariant: String, CaseIterable, Equatable, Sendable {
  case `default` = "Default"
  case avatar = "Avatar"
  case rounded = "Rounded"
}

/// Anti-scraper render strategy for a `Link` — `email` marks a `mailto:` link
/// whose address must not appear in plaintext in emitted markup (the emission
/// strategy is renderer-owned; a render projection may treat it as advisory).
/// Lower-case on the wire.
public enum LinkProtection: String, CaseIterable, Equatable, Sendable {
  case email = "email"
}

public enum LiveRegionKind: String, CaseIterable, Equatable, Sendable {
  case polite = "polite"
  case assertive = "assertive"
  case off = "off"
}

public enum MathDisplay: String, CaseIterable, Equatable, Sendable {
  case inline = "Inline"
  case block = "Block"
}

/// §3.6.11 — the modality a `Modal` declares. Omitted at `modal`, which is the
/// blocking modality every pre-modality document meant.
public enum ModalityKind: String, CaseIterable, Equatable, Sendable {
  case modal = "Modal"
  case popover = "Popover"
}

/// Phase 1536 — `Action.navigate`'s destination window (§3.6.21). A CLOSED
/// enum of two, deliberately not HTML's `target` attribute: that vocabulary
/// also carries `_parent` and `_top`, which are frame-busting gestures a hosted
/// tree must not be able to ask for, so `_blank` is refused rather than aliased
/// — accepting any of it would teach an emitter the wrong vocabulary.
public enum NavigateTarget: String, CaseIterable, Equatable, Sendable {
  case selfWindow = "Self"
  case blank = "Blank"
}

public enum Orientation: String, CaseIterable, Equatable, Sendable {
  case vertical = "Vertical"
  case horizontal = "Horizontal"
}

public enum RelativeTimeUnit: String, CaseIterable, Equatable, Sendable {
  case second = "Second"
  case minute = "Minute"
  case hour = "Hour"
  case day = "Day"
  case week = "Week"
  case month = "Month"
  case year = "Year"
}

public enum ScrollOrientation: String, CaseIterable, Equatable, Sendable {
  case vertical = "Vertical"
  case horizontal = "Horizontal"
  case both = "Both"
}

/// A sort direction. Lower-case on the wire, like `LinkProtection`.
public enum SortDirection: String, CaseIterable, Equatable, Sendable {
  case asc = "asc"
  case desc = "desc"
}

public enum StyleRole: String, CaseIterable, Equatable, Sendable {
  case none = "None"
  case eyebrow = "Eyebrow"
  case data = "Data"
  case lede = "Lede"
  case caption = "Caption"
}

public enum StyleWeight: String, CaseIterable, Equatable, Sendable {
  case compact = "Compact"
  case standard = "Standard"
  case spacious = "Spacious"
}

public enum TextAnchor: String, CaseIterable, Equatable, Sendable {
  case start = "Start"
  case middle = "Middle"
  case end = "End"
}

/// Phase 1472 — the node-level declared text direction (§3.1). Lower-case on
/// the wire, like `LiveRegionKind` and `SortDirection`, because these are the
/// HTML `dir` tokens themselves. Omitted at `auto`, which leaves the inherited
/// direction in place — the pre-1472 rendering.
public enum TextDirection: String, CaseIterable, Equatable, Sendable {
  case auto = "auto"
  case ltr = "ltr"
  case rtl = "rtl"
}

/// `FieldRule.format` — the closed named-format set a text field's value is held to.
public enum TextFormat: String, CaseIterable, Equatable, Sendable {
  case email = "email"
  case url = "url"
  case tel = "tel"
}

/// The unit a `Duration` cell format's raw value counts in.
/// Phase 1533 — the resolution a `Binding.now` declares for the host-furnished
/// instant. FOUR members and not `RelativeTimeUnit`'s seven, deliberately: this
/// is a TRUNCATION of a calendar instant, and a week, a month or a year has no
/// truncation every host agrees on (which weekday starts a week; which
/// calendar). The four here truncate the canonical ISO-8601 form by prefix.
public enum TimeGrain: String, CaseIterable, Equatable, Sendable {
  case second = "Second"
  case minute = "Minute"
  case hour = "Hour"
  case day = "Day"
}

/// Phase 1810 — the time-of-day half of `Format.dateTime`'s `dateStyle` /
/// `timeStyle` pair. The same four cases as `DateStyle`, deliberately a SEPARATE
/// enum: the two name breadths of different things.
public enum TimeStyle: String, CaseIterable, Equatable, Sendable {
  case short = "Short"
  case medium = "Medium"
  case long = "Long"
  case full = "Full"
}

public enum ToneVariant: String, CaseIterable, Equatable, Sendable {
  case `default` = "Default"
  case subdued = "Subdued"
  case brand = "Brand"
  case success = "Success"
  case warning = "Warning"
  case critical = "Critical"
  case info = "Info"
}

/// `TrackEntry.kind` — a media element's timed-text track class
/// (WIRE_FORMAT.md §3.6.6, Phase 1110). Bare strings on the wire.
///
/// **The set is CLOSED at four, and `Metadata` is deliberately not a case.** Its
/// cues are rendered by no user agent and read only by script, so a declarative
/// document naming it would state an intent no conformant host could honour
/// without leaving the vocabulary. A fifth is an ADDITION, never a spelling a
/// decoder may guess at — which is why no alias arm is registered for the HTML
/// lower-case spellings either: those are the emitted tokens, not accepted
/// input.
public enum TrackKind: String, CaseIterable, Equatable, Sendable {
  case subtitles = "Subtitles"
  case captions = "Captions"
  case descriptions = "Descriptions"
  case chapters = "Chapters"
}

/// `Metric.trendPolarity` — which way the measured quantity IMPROVES
/// (WIRE_FORMAT.md §3.6.1). Distinct from `tone`, which says how the reading
/// STANDS: a host derives neither from the other, and nothing here ever writes
/// back to `tone`.
///
/// **`Neutral` is reserved by the specification and is deliberately NOT a case
/// here.** The case set IS the accepted wire set, so omitting it means
/// `"Neutral"` fails `UNKNOWN_DU_CASE` naming the two legal spellings, rather
/// than this surface quietly deciding a question the reservation holds open.
/// That is the same modelling choice the Rust reference core made for the same
/// slot, and it is why the wire slot is an enum rather than an `inverted` bool:
/// admitting the third case later is one added case plus a compiler error at
/// every site that must then decide what it means.
///
/// No alias arm is registered, and that omission is deliberate: the obvious
/// candidates are precisely the spellings that must not be accepted — `Neutral`
/// would pre-empt the reservation, and `Inverted` / `Descending` would reinstate
/// the boolean spelling §3.6.1 refuses.
public enum TrendPolarity: String, CaseIterable, Equatable, Sendable {
  case higherIsBetter = "HigherIsBetter"
  case lowerIsBetter = "LowerIsBetter"
}

// ── Tagged unions: one case per wire `$type` ─────────────────────────────────

/// A user-interaction action (§3.3), one case per wire `$type`.
public indirect enum Action: Equatable, Sendable {
  case chain([Action])
  /// Phase 1126 — the payload is a `TextSource`. A `text` that is neither a
  /// string nor a `$type`-tagged `TextSource` is `WRONG_TYPE` and is never
  /// coerced: a host reading the widening as "this member is now open" would
  /// put a JSON literal on the reader's clipboard, and a clipboard is a channel
  /// the reader later pastes somewhere with authority.
  case writeToClipboard(text: TextSource)
  case dispatch
  case invoke(capabilityId: String, args: [InvokeArg])
  case readFileBody(fileRef: String, encoding: FileReadEncoding)
  case call(endpoint: String, into: CallResultTarget?, onResult: Closure?)
  /// Phase 1536 — `route` is a `TextSource`, not a bare string, so a tree can
  /// name a destination it computes from what the reader is looking at. The
  /// bare JSON string IS `Literal`'s canonical form, so every document written
  /// before the widening decodes exactly as it did. `target` is the CLOSED
  /// `Self | Blank` enum, omitted at `Self`.
  case navigate(route: TextSource, target: NavigateTarget)
  case commitLocal(nodeId: String)
  case notify(channel: String, payload: JSON)
  /// Exactly ONE of `value` (a literal payload) and `valueFrom` (a binding resolved at
  /// dispatch time) is present - the schema states it as a `oneOf`, so both-present is a
  /// reject rather than a precedence question.
  case setState(key: String, value: JSON?, valueFrom: Binding?)
  case aiTool(toolName: String, args: JSON)
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
  /// The host-furnished instant. Carries no payload: the value is supplied at resolve
  /// time by the host clock, which is why it is a `Clock`-determinism source, not wire data.
  ///
  /// Phase 1533 — the declared GRAIN truncates the instant BEFORE it is read.
  /// Absent is `second`, which is the identity; a present value outside the
  /// four is refused rather than silently read at a neighbouring resolution.
  case now(grain: TimeGrain?)
  case computed
  /// Phase 1534 (§3.3.3) — `codec` declares the buffer's OWN codec and replaces
  /// the identity on both sides; `commitTo` declares the State key the flush
  /// writes to. `commitTo` and the `onCommit` closure are mutually exclusive,
  /// because the wire cannot carry the closure and two hosts would otherwise
  /// write to different places from identical bytes.
  case local(
    codec: Format?, commitTo: String?, flushOn: LocalFlushTrigger, initialFrom: Binding,
    onCommit: Closure?)
  case format(format: Format, locale: LocaleSource, source: Binding)
  case i18n(key: String, args: [NamedBinding]?)
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

public enum BoxLayout: Equatable, Sendable {
  case auto
  case flex(direction: Orientation, gap: Int?, wrap: Bool)
  case grid(cols: Int, gap: Int?, templateColumns: String?)
  /// WIRE_FORMAT §3.6.7 (Phase 1082) — the column-fill mode. `cols` is
  /// REQUIRED and POSITIVE; there is deliberately no `templateColumns` twin,
  /// because the multi-column model realising masonry has no track list for
  /// one to name.
  case masonry(cols: Int, gap: Int?)
}

/// The declarative result target of an `Action.Call` (Phase 428).
public enum CallResultTarget: Equatable, Sendable {
  case state(key: String)
  case query(name: String)
}

public enum CellFormat: Equatable, Sendable {
  case none
  case number(decimals: Int?)
  case currency(code: String)
  case percent(decimals: Int?)
  case significantDigits(digits: Int)
  /// Phase 1811 — `dateTime` (was `date`): the pattern renders a date, a time or both.
  case dateTime(format: String)
  case duration(unit: DurationUnit, style: DurationStyle)
  /// A relative-time CELL format ("3 minutes ago"). Distinct from the `Format` DU's own
  /// `relativeTime`: the wire carries two format DUs and a case in one is not a case in
  /// the other.
  case relativeTime(unit: RelativeTimeUnit)
  case custom
}

public enum CellKindErased: Equatable, Sendable {
  case text
  case numeric
  case date
  case editable
  case checkbox
  case button(label: TextSource)
  case buttonGroup(labels: [TextSource])
  case link
  case pill
  /// Phase 750 — the declarative twin of `pill`, and the ONE cell kind holding no
  /// closure, which is exactly why it survives the wire. `field` names the row
  /// property that is both the pill's label and the map key; `map` carries value →
  /// tone; `defaultTone` covers a value the map does not mention and is omitted on
  /// the wire at `.default`.
  ///
  /// This is the first cell kind this projection carries any PAYLOAD for. Every
  /// other one is defined by a closure, which never rides the wire, so the case
  /// name was the whole of the information — a decode-only projection could
  /// faithfully represent it as a bare case. A declared tone rule is data, so it
  /// has to be carried.
  case tonedPill(field: String, map: [String: ToneVariant], defaultTone: ToneVariant)
  case progress
  case custom
}

/// Phase 1490 (§4l) — a chart's data-addressed annotation. An annotation names a
/// place in the DATA's coordinates and, optionally, a label; it carries no
/// geometry and no style at all, which is what makes it survive a data change, a
/// theme flip, a restyle and a resize.
public enum ChartAnnotation: Equatable, Sendable {
  /// A horizontal line at `value` in the VALUE axis's own units.
  case referenceLine(value: Double, label: TextSource?)
  /// A VERTICAL line at an x address — the reference line mirrored across the
  /// axes.
  case eventMarker(at: ChartAnnotationX, label: TextSource?)
  /// A shaded interval on either axis, and the one member that draws BEHIND
  /// every series.
  case rangeBand(range: ChartAnnotationRange, label: TextSource?)
}

/// Phase 1492 (§4l) — a `rangeBand`'s PAIR: two of the same address form, on one
/// axis.
///
/// THE AXIS IS THE CASE. §4l requires a band to declare which axis it sits on;
/// carrying that as a separate flag beside an untyped pair would admit a
/// document declaring the value axis and addressing it with two category keys.
/// The union tag declares the axis AND types the pair with it, so that document
/// cannot be written by any conformant emitter.
public enum ChartAnnotationRange: Equatable, Sendable {
  case valueRange(from: Double, to: Double)
  case xRange(from: ChartAnnotationX, to: ChartAnnotationX)
}

/// Phase 1491 (§4l) — an annotation's x address: a CATEGORY key read under the
/// categorical scale, and an ISO-8601 `Date` read under `Temporal`.
///
/// Its own type rather than two inline fields, because a range band addresses an
/// x-axis interval with a PAIR of these.
public enum ChartAnnotationX: Equatable, Sendable {
  case category(key: String)
  case date(iso: String)
}

public enum ColumnWidth: Equatable, Sendable {
  case auto
  case fixed(pixels: Int)
  case flex(weight: Double)
}

public enum CurveCommand: Equatable, Sendable {
  case moveTo(DrawPoint)
  case lineTo(DrawPoint)
  case cubicTo(control1: DrawPoint, control2: DrawPoint, to: DrawPoint)
  case quadraticTo(control: DrawPoint, to: DrawPoint)
  case close
}

public enum FormFieldKind: Equatable, Sendable {
  case text(value: Binding, onChange: Closure?)
  case number(value: Binding, onChange: Closure?)
  case checkbox(value: Binding, onToggle: Closure?)
  /// The switch affordance: the same boolean slot as `checkbox`, a different control.
  case toggle(value: Binding, onToggle: Closure?)
  case choice(options: Binding, value: Binding, onChange: Closure?)
  case textArea(rows: Int, value: Binding, onChange: Closure?)
  case rangedNumber(value: Binding, min: Double?, max: Double?, step: Double?, onChange: Closure?)
  /// 0.2.0 — the dual-thumb numeric range (absorbed the retired RangeFilter).
  case range(value: Binding, min: Double?, max: Double?, step: Double?, onChange: Closure?)
  case segmentedChoice(
    options: Binding, orientation: Orientation, value: Binding, onChange: Closure?)
  /// Phase 1811 — `dateTime` (was `date`): the field already took a date, a time
  /// of day or both via `variant`; the name now says so.
  case dateTime(
    value: Binding, variant: DateTimeVariant, min: String?, max: String?, step: Double?,
    onChange: Closure?)
  /// 0.7.0 — the single-control date range (`dateTimeRange` since Phase 1811):
  /// `range`'s pair mechanics with `dateTime`'s value conventions (an identical
  /// associated-value list to `dateTime`, reusing the existing `DateTimeVariant` —
  /// no new enum). In a filter context the pair binds ONE filter param, not two,
  /// which is the reason the case exists rather than two coordinated `dateTime`
  /// fields.
  case dateTimeRange(
    value: Binding, variant: DateTimeVariant, min: String?, max: String?, step: Double?,
    onChange: Closure?)
  /// The searchable form of `choice` (§3.6.9, Phase 1113). **`options` is the
  /// case's only REQUIRED member** — a combobox with no option source is not a
  /// control — and `value` / `onChange` are `choice`'s, deliberately and
  /// normatively: the constrained combobox IS a searchable select, so a document
  /// migrating between the two changes its `$type` and nothing else, and a host
  /// implementing a different value contract here would break exactly that
  /// migration.
  ///
  /// `allowFreeText` omits at `false` and the polarity is load-bearing: the
  /// SHORTEST combobox document is the CONSTRAINED one, so admitting off-list
  /// values is the thing an emitter has to ask for. A present member of any
  /// other type is `WRONG_TYPE` and MUST NOT be coerced — a lenient truthiness
  /// read would widen the field on `"no"` and `"false"` alike.
  ///
  /// An asynchronous suggestion source needs no vocabulary of its own: a
  /// `Binding.query` in the ordinary `options` slot IS the async feed, resolved
  /// by the same machinery every other query-bound slot uses. Nothing in this
  /// case names a request, a debounce or a minimum query length.
  case combobox(options: Binding, value: Binding, allowFreeText: Bool, onChange: Closure?)
  /// Phase 1130 (§3.6.17) — a subjective score on a small ordinal scale. The
  /// line against `rangedNumber` is who the number belongs to: a rating is a
  /// judgement a person GIVES, a ranged number a measurement they REPORT.
  ///
  /// `max` is the case's only required member and is refused below 1 — a scale
  /// with no positions has nothing to draw and no keystroke that could change
  /// anything. `value` is a float even where nothing can type a fraction,
  /// because the commonest rating a reader sees is an AVERAGE arriving through
  /// a query. `allowHalf` governs ENTRY, never display.
  case rating(value: Binding, max: Int, allowHalf: Bool, onChange: Closure?)
  /// Phase 1130 (§3.6.17) — the platform's own colour picker. A CONTROL, not a
  /// `rule.format`: a swatch that opens the operating system's picker, which no
  /// format on a text field can produce.
  ///
  /// Both members optional. The value is `#rrggbb` and nothing else — the one
  /// form a native colour input can hold or return — and case is PRESERVED
  /// rather than normalised.
  case color(value: Binding, onChange: Closure?)
  /// Phase 1121 (§3.6.19) — SEVERAL values accumulated as removable chips, over
  /// a suggestion set that may be open, searchable, asynchronous, or absent.
  ///
  /// Every member is optional, so `{"$type":"Tokens"}` is a complete document.
  /// `allowFreeText` omits at **`true`** — the OPPOSITE polarity to `combobox`,
  /// and the one thing about this case a host is most likely to get wrong:
  /// `combobox`'s option source is REQUIRED so "constrained" is its resting
  /// state, where `suggestions` is optional so "open" is this one's. The
  /// default follows the required-ness of the set.
  ///
  /// `value` is a `Binding<string list>` and the list is ORDERED — chips appear
  /// where the reader added them, so a host must not sort or de-duplicate it.
  case tokens(value: Binding, suggestions: Binding?, allowFreeText: Bool, onChange: Closure?)
}

public enum Format: Equatable, Sendable {
  case number(decimals: Int?)
  case currency(isoCode: String)
  case percent(decimals: Int?)
  /// Phase 1810 — `dateStyle` / `timeStyle` are BOTH optional: `timeStyle` alone
  /// is a time of day, both together a date-time. Phase 1811 — `dateTime` (was
  /// `date`): an honest name once it renders a time.
  case dateTime(dateStyle: DateStyle?, timeStyle: TimeStyle?)
  case relativeTime(unit: RelativeTimeUnit)
  /// Phase 819 — the numeric source counts `unit`s, rendered per the bounded
  /// `style`.
  case duration(unit: DurationUnit, style: DurationStyle)
  /// Phase 1533 — the elapsed-time rendition. Distinct from `relativeTime`:
  /// this one is a function of the HOST instant as well as of its source, so a
  /// host with no instant renders nothing rather than an invented delta.
  case since(unit: RelativeTimeUnit?)
}

public enum HoleDecl: Equatable, Sendable {
  case value(name: String, space: HoleValueSpace, default: FragmentScalar?)
  case slot(name: String, kindConstraint: String?)
  case repeatHole(name: String, countSpace: HoleValueSpace)
}

public enum HoleValueSpace: Equatable, Sendable {
  case intRange(min: Int, max: Int)
  case floatRange(min: Double, max: Double)
  case stringLen(minLen: Int, maxLen: Int)
  case enumChoices(choices: [String])
  case anyString
}

public enum LocalFlushTrigger: Equatable, Sendable {
  case onBlur
  case onSubmit
  case onDebounce(milliseconds: Int)
  case onCommitAction
}

public enum LocaleSource: Equatable, Sendable {
  case ambient
  case explicit(tag: String)
}

/// Which playback surface a `Media` node is — ONE kind, two variants, never two
/// kinds. Everything a video surface and an audio surface SHARE is stated once
/// on `MediaSpec`; only the slots that genuinely differ live here, and there
/// are two of them, both on `Video`.
///
/// **`Audio` has NO autoplay pathway — in the type, on the wire, or in the
/// emission.** That is why this is an `enum` with associated values per case
/// rather than a discriminator beside two optional fields: the case declares no
/// such slot, so a renderer has nothing to branch on and cannot acquire one by
/// a later edit. This is stronger than a default of `false` — a slot that
/// defaults to off is one a document can switch on, and there is no document
/// this format wants to be able to state in which a page begins making sound
/// unbidden. A document carrying `{"$type":"Audio","autoplay":true}` decodes to
/// an audio surface that does not autoplay, because the value has nowhere to
/// land.
public enum MediaKind: Equatable, Sendable {
  /// `autoplay` is a wire DECLARATION whose rendering is constrained: a host
  /// that honours it MUST pair it with muted playback. There is deliberately no
  /// separate `muted` slot on the wire — a second knob would be free to
  /// disagree with the first, and the only combination it would add is the one
  /// no host may render. `poster` is a second URL through the §19 floor, and a
  /// refused one is DROPPED rather than neutered (§3.6.6).
  case video(autoplay: Bool, poster: Binding?)
  /// The variant whose payload is the discriminator alone.
  case audio
}

public enum FragmentScalar: Equatable, Sendable {
  case int(Int)
  case float(Double)
  case bool(Bool)
  case str(String)
}

public enum Shape: Equatable, Sendable {
  case group(children: [Shape], style: DrawStyle)
  case rectangle(
    x: Double, y: Double, width: Double, height: Double, cornerRadius: Double?, style: DrawStyle)
  case line(x1: Double, y1: Double, x2: Double, y2: Double, style: DrawStyle)
  case polyline(points: [DrawPoint], style: DrawStyle)
  case polygon(points: [DrawPoint], style: DrawStyle)
  case curve(commands: [CurveCommand], style: DrawStyle)
  case circle(cx: Double, cy: Double, r: Double, style: DrawStyle)
  case ellipse(cx: Double, cy: Double, rx: Double, ry: Double, style: DrawStyle)
  case label(x: Double, y: Double, text: TextSource, style: DrawStyle)
}

/// A text-producing position (§3.3). A bare wire string decodes to `.literal`
/// (the §16 AI-ingest shorthand).
public enum TextSource: Equatable, Sendable {
  case literal(String)
  case bound(Binding)
  case i18n(key: String, args: [String: JSON])
}

// ── Records ──────────────────────────────────────────────────────────────────

public struct Accessibility: Equatable, Sendable {
  public var label: Binding?
  public var labelledBy: String?
  public var describedBy: String?
  public var role: String?
  public var liveRegion: LiveRegionKind?
  public var hidden: Binding?
  /// Phase 1812 — the node's SPOKEN rendering for a voice surface: an ordinary
  /// `TextSource` (bare-string canonical for a literal, as `tooltip`). Inert to
  /// every visual renderer: it MUST reach no attribute and no visible text.
  public var speak: TextSource?

  public init(
    label: Binding? = nil, labelledBy: String? = nil, describedBy: String? = nil,
    role: String? = nil, liveRegion: LiveRegionKind? = nil, hidden: Binding? = nil,
    speak: TextSource? = nil
  ) {
    self.label = label
    self.labelledBy = labelledBy
    self.describedBy = describedBy
    self.role = role
    self.liveRegion = liveRegion
    self.hidden = hidden
    self.speak = speak
  }
}

public struct ColumnErased: Equatable, Sendable {
  public var field: String?
  public var format: CellFormat = .none
  public var kind: CellKindErased
  public var label: String
  public var value: Closure?
  public var width: ColumnWidth = .auto
}

/// The cross-field operand. `against` is a `Binding`, and that IS the
/// cross-field mechanism rather than an accident of typing: any read slot may
/// take a Binding, and the auto-bind rule already puts every form field's value
/// in State under the field's own id, so `{"$type":"State","key":"<sibling id>"}`
/// reads the sibling with no coordination vocabulary at all.
public struct CompareRule: Equatable, Sendable {
  public var against: Binding
  public var op: CompareOp
}

public struct ContentHash: Equatable, Sendable {
  public var algorithm: String
  public var hash: String
  public var strictness: HashStrictness
}

/// An initial sort: a zero-based header INDEX (the schema pins `minimum: 0`, so a
/// negative is malformed rather than a from-the-end convention) plus a direction.
public struct DefaultSort: Equatable, Sendable {
  public var column: Int
  public var direction: SortDirection
}

public struct DrawPoint: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

/// The public memberwise initialiser exists deliberately: the style cascade
/// (`inheritedDrawStyle`) rebuilds a style field by field rather than copying
/// and patching, so that adding a field to this record is a COMPILE ERROR at
/// the cascade until someone decides whether it inherits. A copy-and-patch
/// would silently leave a new field un-inherited.
public struct DrawStyle: Equatable, Sendable {
  public var fill: Binding?
  public var stroke: Binding?
  public var strokeWidth: Binding?
  public var opacity: Binding?
  public var textAnchor: TextAnchor?
  public var fontSize: Double?
  public var emphasis: Emphasis?
  public var fontFamily: String?
  /// Phase 642 — keyed mark identity (omitted-when-absent on the wire).
  public var markId: String?
  /// Label rotation in DEGREES, clockwise-positive about the label's own anchor
  /// point — the wire's `rotate(θ x y)` semantics, taken as-authored (no host
  /// re-rounds on decode). Applies only to `Shape.label`; ignored elsewhere,
  /// exactly like the rest of the text-only cluster above.
  public var rotation: Double?
  /// The mark's hover-readable readout. The one `DrawStyle` field that applies
  /// to EVERY shape rather than only to `label` — the marks a reader reaches for
  /// are the bars, wedges and points. An explicitly EMPTY tip is a present value
  /// and a distinct wire shape from an absent one.
  public var tip: TextSource?

  public init(
    fill: Binding? = nil, stroke: Binding? = nil, strokeWidth: Binding? = nil,
    opacity: Binding? = nil, textAnchor: TextAnchor? = nil, fontSize: Double? = nil,
    emphasis: Emphasis? = nil, fontFamily: String? = nil, markId: String? = nil,
    rotation: Double? = nil, tip: TextSource? = nil
  ) {
    self.fill = fill
    self.stroke = stroke
    self.strokeWidth = strokeWidth
    self.opacity = opacity
    self.textAnchor = textAnchor
    self.fontSize = fontSize
    self.emphasis = emphasis
    self.fontFamily = fontFamily
    self.markId = markId
    self.rotation = rotation
    self.tip = tip
  }
}

public struct EffectClass: Equatable, Sendable {
  public var determinism: DeterminismSource
  public var hostEffect: HostEffect
}

/// A field's declared constraint — the ACCEPTED SET, where `FormFieldKind`
/// names the control. Every slot is optional structurally; the two
/// well-formedness refusals (a rule that constrains nothing; `minLength` above
/// `maxLength`) are relations BETWEEN slots and so live in the decoder's policy
/// layer rather than in this shape.
public struct FieldRule: Equatable, Sendable {
  public var compare: CompareRule?
  public var format: TextFormat?
  public var maxLength: Int?
  public var message: TextSource?
  public var minLength: Int?
  public var pattern: String?
}

/// 0.2.0 filters-unification: a chip's control is an ordinary `FormFieldKind`
/// (the retired `*Filter` discriminators are hard errors); its absent `value`
/// slot auto-binds `Filter(name)`.
public struct FilterSpec: Equatable, Sendable {
  public var kind: FormFieldKind
  public var label: TextSource
  public var name: String
}

public struct FormField: Equatable, Sendable {
  public var id: String
  public var kind: FormFieldKind
  public var label: TextSource
  public var required: Bool
  public var help: TextSource?
  public var rule: FieldRule?
}

public struct MountChannel: Equatable, Sendable {
  public var direction: ChannelDirection
  public var messageShape: String?
}

public struct InvokeArg: Equatable, Sendable {
  public var addr: String
  public var value: String

  public init(addr: String, value: String) {
    self.addr = addr
    self.value = value
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

public struct SelectOption: Equatable, Sendable {
  public var value: String
  public var label: TextSource

  public init(value: String, label: TextSource) {
    self.value = value
    self.label = label
  }
}

/// The semantic-style triple plus the Phase 147 role/voice (both omitted on the
/// wire at their defaults).
public struct SemanticStyle: Equatable, Sendable {
  /// Phase 1472 — the one member of this record that is not presentational: it
  /// declares the text DIRECTION, which is a fact about the content rather than
  /// a style choice. Omitted at `auto` on both boundaries, like its siblings.
  public var direction: TextDirection = .auto
  public var emphasis: Emphasis = .normal
  public var role: StyleRole = .none
  public var tone: ToneVariant = .default
  public var voice: FontVoice = .default
  public var weight: StyleWeight = .standard
}

/// One alternate rendition of the SAME picture at a declared intrinsic pixel
/// width (§3.6.4). Both members are required *within* the entry.
public struct SrcSetEntry: Equatable, Sendable {
  public var src: Binding
  /// The `w` descriptor a client selects on. A POSITIVE integer, and the floor
  /// is a DECODE rule rather than a render one: a `0w` candidate is not a small
  /// image, it is one a client can never select, so admitting it would let the
  /// wire state a rendition no host can render.
  public var width: Int

  public init(src: Binding, width: Int) {
    self.src = src
    self.width = width
  }
}

public struct StaticRows: Equatable, Sendable {
  public var defaultSort: DefaultSort?
  public var headers: [TextSource]
  public var rows: [[TextSource]]
  public var sortable: Bool?
}

public struct TabHeader: Equatable, Sendable {
  public var label: TextSource
  public var icon: String?
  public var disabled: Binding?
}

/// One timed-text track on a media element (§3.6.6, Phase 1110).
///
/// **The strictest record on the wire: four of its five members are REQUIRED.**
/// `default` is the one omitted-at-`false` slot; everything else must be stated,
/// and each requirement buys something a default could not.
///
/// `srcLang` is required on EVERY kind, where HTML makes `srclang` mandatory
/// only on a subtitles track. The extra strictness costs an author one value and
/// buys a menu a user agent can order, a speech engine can pronounce and a
/// reader can tell apart; there is no value to default to that would not be an
/// invented claim about someone else's recording. `label` is required for the
/// reason `MediaSpec.label` is: it is the entry a user agent puts in its track
/// menu and the only thing distinguishing one track from another there.
public struct TrackEntry: Equatable, Sendable {
  public var kind: TrackKind
  public var src: Binding
  public var srcLang: String
  public var label: TextSource
  /// The ONE omitted-at-`false` slot. Note what it does NOT decide: §3.6.6
  /// obligation 3 says a document electing two defaults of one kind is legal
  /// bytes, so this slot records the ELECTION and the render projection
  /// resolves it (first election of a kind wins). A decoder that refused the
  /// second election would refuse a document every lenient host renders.
  public var isDefault: Bool = false

  public init(
    kind: TrackKind, src: Binding, srcLang: String, label: TextSource, isDefault: Bool = false
  ) {
    self.kind = kind
    self.src = src
    self.srcLang = srcLang
    self.label = label
    self.isDefault = isDefault
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

/// One row of a `Tree` (§3.6.12, Phase 1120) — the format's first
/// SELF-REFERENTIAL record.
///
/// Rows are `TreeItem`s, not `Node`s, and `children` is a list of the same
/// record. `id` and `label` are required; `children` omits at the EMPTY list and
/// `icon` when absent, so a leaf carries two keys and nothing else — which is
/// most of a real hierarchy.
///
/// `id` is required because it is what the two State slots NAME. `label` is a
/// `TextSource` because it is content — authored, translated, bindable.
///
/// **Row ids MUST be unique within one tree, and that is an EMIT-side
/// obligation, not a decode refusal** (§8.1's position for `NodeId`, transferred
/// for §8.1's own reason): duplicate detection is a whole-tree property, a
/// decoder streaming a document is not required to carry the id set, and there
/// is no error code for it. This surface therefore accepts a duplicate and is
/// still conformant.
public struct TreeItem: Equatable, Sendable {
  public var id: String
  public var label: TextSource
  public var icon: String?
  public var children: [TreeItem] = []

  public init(id: String, label: TextSource, icon: String? = nil, children: [TreeItem] = []) {
    self.id = id
    self.label = label
    self.icon = icon
    self.children = children
  }
}

public struct ViewBox: Equatable, Sendable {
  public var minX: Double
  public var minY: Double
  public var width: Double
  public var height: Double

  public init(minX: Double, minY: Double, width: Double, height: Double) {
    self.minX = minX
    self.minY = minY
    self.width = width
    self.height = height
  }
}

// ── Node kind specs ──────────────────────────────────────────────────────────

public struct BadgeSpec: Equatable, Sendable {
  public var label: TextSource
  public var variant: BadgeVariant
}

public struct BoxSpec: Equatable, Sendable {
  public var children: [Node]
  public var heading: TextSource?
  public var layout: BoxLayout
  public var role: BoxRole
  public var keepTogether: Bool = false
  /// Phase 1473 — the print-break controls. Both omit at `false`, and both are
  /// declarations about PAGINATED media alone: a screen host reads them and
  /// emits nothing.
  public var breakBefore: Bool = false
}

public struct ButtonSpec: Equatable, Sendable {
  public var label: TextSource
  public var onClick: Action
  public var variant: ButtonVariant
  public var icon: String?
  public var disabled: Binding?
}

public struct CalloutSpec: Equatable, Sendable {
  public var body: TextSource
  public var dismissable: Bool = false
  public var tone: ToneVariant = .default
  public var heading: TextSource?
  public var icon: String?
}

public struct ChartSpec: Equatable, Sendable {
  public var kind: ChartKind
  public var source: Binding
  public var stacked: Bool = false
  public var xField: String
  public var yFields: [String]
  public var title: TextSource?
  /// Phase 1490 — omitted when the chart declares none.
  public var annotations: [ChartAnnotation]?
  public var onPointClick: Closure?
}

public struct CodeBlockSpec: Equatable, Sendable {
  public var code: String
  public var copyable: Bool
  public var highlightLines: [Int]
  public var language: String
  public var lineNumbers: Bool
}

public struct CustomSpec: Equatable, Sendable {
  public var moduleId: String
  public var componentId: String
  public var props: [String: JSON]
  public var contentHash: ContentHash?
  public var exposedNodeIds: [String]
}

public struct GridSpec: Equatable, Sendable {
  public var columns: [ColumnErased]
  public var editable: Bool = false
  public var rowKey: Closure?
  public var rowKeyField: String?
  /// The sort / page / edit POSITIONS are addressed through state keys rather than
  /// literal values, so a control can move them; `defaultSort` and `pageSize` are the
  /// initial configuration. Decoded faithfully because this is a view of the wire -
  /// dropping a declaration would misreport the tree. Acting on them is the renderer's
  /// business, not the decoder's.
  public var sortStateKey: String?
  /// Rows per page. The schema pins `minimum: 1` - a zero page size paginates nothing.
  public var pageSize: Int?
  public var pageStateKey: String?
  public var defaultSort: DefaultSort?
  public var editStateKey: String?
  /// Phase 1125 — the two sides of ONE shared State key. A grid declaring
  /// `transferOutKey` K may RELEASE rows onto K; one declaring `transferInKey`
  /// K ACCEPTS rows arriving on it. Separate decoder arms, and the corpus
  /// vectors them separately for that reason.
  public var transferInKey: String?
  public var transferOutKey: String?
  /// Phase 1473 — the paginated-media pair, on `Box`'s terms.
  public var keepRowsTogether: Bool = false
  public var repeatHeader: Bool = false
  /// Phase 1123 — this grid's rows may be taken out of the page as a file.
  /// Omitted at `false`.
  public var exportable: Bool = false
  public var source: Binding
  public var staticRows: StaticRows?
  public var onRowClick: Closure?
}

public struct DisclosureSpec: Equatable, Sendable {
  public var children: [Node]
  public var defaultOpen: Bool
  public var heading: TextSource
  public var onToggle: Closure?
  public var `open`: Binding
}

/// The initialiser is public because a `Drawing` is something a render
/// projection PRODUCES as well as decodes: the Phase 1099 sparkline lowering
/// builds one from a resolved series so the picture goes through the drawing
/// canvas the surface already has, rather than through a second hand-written
/// vector path. This is not an encode leg — the value never becomes wire bytes
/// here — so the decode-only posture is unchanged.
public struct DrawingSpec: Equatable, Sendable {
  public var viewBox: ViewBox
  public var shapes: [Shape]
  public var style: DrawStyle = .empty
  public var title: TextSource?
  public var description: TextSource?

  public init(
    viewBox: ViewBox, shapes: [Shape], style: DrawStyle = .empty, title: TextSource? = nil,
    description: TextSource? = nil
  ) {
    self.viewBox = viewBox
    self.shapes = shapes
    self.style = style
    self.title = title
    self.description = description
  }
}

/// The sandboxed third-party embed (§3.6.8, Phase 1111).
///
/// **A KIND, not a `Mount` variant and not a `Media` variant.** `Mount` composes
/// a COOPERATING guest — a scope id, a declared message channel, a capability
/// request list — and a third-party page has none of those and cannot acquire
/// them. `Media` fetches an asset and DISPLAYS it, decoded into no scripting
/// context, where an embed fetches a document and lets it EXECUTE. That last
/// difference is why the source takes its own, narrower egress class (§19.1)
/// rather than reusing `Media`'s.
public struct EmbedSpec: Equatable, Sendable {
  public var src: Binding
  /// REQUIRED, on `MediaSpec.label`'s argument one kind over. A frame is a focus
  /// container a reader tabs INTO, so there is no decorative embed the way there
  /// is a decorative image; a frame with no accessible name is announced as
  /// "frame" and nothing else. A document omitting it is refused rather than
  /// defaulted, because an invented title is a claim about somebody else's
  /// document.
  public var title: TextSource
  /// Omitted at the EMPTY list, and empty means TOTAL DENIAL. That polarity is
  /// the design rather than a consequence of the omit rule: the wire-cheapest
  /// document is also the most locked-down one, so the default a careless
  /// emitter produces is the safe one.
  ///
  /// AUTHORED order is preserved here (a JSON array is ordered data); the
  /// vocabulary's declaration order is imposed at RENDER time, which is where
  /// the determinism the markup needs actually belongs.
  public var permissions: [EmbedPermission] = []
  /// REUSES `ImageAspect` rather than minting a parallel enum with identical
  /// cases: the cases are pure layout ratios with nothing image-specific in
  /// them, and the wire carries bare strings, so the type name reaches no
  /// document. Two closed sets that must be kept in step is the defect a
  /// separate type would introduce, not avoid. Total, omitted at `Natural`.
  public var aspectRatio: ImageAspect = .natural

  public init(
    src: Binding, title: TextSource, permissions: [EmbedPermission] = [],
    aspectRatio: ImageAspect = .natural
  ) {
    self.src = src
    self.title = title
    self.permissions = permissions
    self.aspectRatio = aspectRatio
  }
}

public struct ErrorBoundarySpec: Equatable, Sendable {
  public var child: Node
  public var fallback: Node
}

/// The labeled text-fact kind (0.2.x — `Fact`).
public struct FactSpec: Equatable, Sendable {
  public var emphasis: Bool = false
  public var help: TextSource?
  public var icon: String?
  public var label: TextSource
  public var tone: ToneVariant = .default
  public var value: TextSource
}

public struct FileUploadSpec: Equatable, Sendable {
  public var accept: [String]
  public var label: TextSource
  public var multiple: Bool
  public var disabled: Binding?
  public var acceptPaste: Bool = false
  /// Phase 1115 — two ADDITIONAL ingress routes, never replacements for the
  /// picker. Both omit at `false`, and the polarity is load-bearing: the
  /// shortest upload document is the plain picker, which is what every document
  /// written before that revision says.
  public var dropTarget: Bool = false
  /// Phase 1116 (§3.6.18) — WHICH of the reader's own recording devices the
  /// platform should open in place of the file browser. OPTIONAL rather than
  /// omit-at-default: "say nothing" is a state of its own, because an upload
  /// naming no device is asking for the file browser, which is not one of the
  /// two devices wearing a default.
  public var capture: CaptureSource?
  /// Phase 1117 (§3.6.20) — the host-registered destination an upload streams
  /// to. A NAME, and a name because it must never be an ADDRESS: a wire
  /// document comes from an arbitrary emitter, and a URL here would let that
  /// emitter choose where a reader's file goes. The empty string is REFUSED
  /// rather than read as absence, which would silently turn an upload the
  /// author meant to stream into a client-only one.
  public var destination: String?
  /// Phase 1548 (§3.6.23) — the declared ceilings: how large a file, and how
  /// many of them, this control accepts.
  ///
  /// `maxBytes` is PER FILE rather than per selection. That is what makes it
  /// meaningful on a single-file upload and what makes it the quantity a body
  /// read can be measured against; a control bounding a whole multiple
  /// selection states both members and the total it declares is
  /// `maxBytes × maxFiles`. A per-selection sum would be a different quantity
  /// wearing the same name.
  ///
  /// `maxFiles` is meaningful only alongside `multiple`, and beside
  /// `"multiple":false` it is INERT — carried, not refused, because the bytes
  /// describe a control every host renders identically with or without it, so
  /// there is nothing for a decoder to be right about.
  ///
  /// Both are OPTIONAL and POSITIVE. Absent declares no ceiling, which is every
  /// pre-1548 document exactly; `0` and below are refused at decode, because a
  /// ceiling of zero is not a small ceiling but a control that can accept
  /// nothing. `Int` here is §7.1's 32-bit slot, bounded by the strict integer
  /// reader rather than by this type.
  public var maxBytes: Int?
  public var maxFiles: Int?
}

public struct FormSpec: Equatable, Sendable {
  public var fields: [FormField]
  public var onSubmit: Action
  public var submitLabel: TextSource
  public var disabled: Binding?
}

public struct FragmentDeclSpec: Equatable, Sendable {
  public var body: Node
  public var name: String
  public var holes: [HoleDecl] = []
  public var effect: EffectClass
}

public struct FragmentRefSpec: Equatable, Sendable {
  public var name: String
  public var args: [FragmentArgEntry]
}

public struct HeadingSpec: Equatable, Sendable {
  public var level: Int
  public var text: TextSource
  public var variant: HeadingVariant
}

/// A standalone glyph. `icon` is a NAME; the embedding app owns the name -> glyph
/// mapping, so this projection carries the name rather than resolving it.
public struct IconSpec: Equatable, Sendable {
  public var icon: String
  public var size: IconSize = .medium
  public var tone: ToneVariant = .default
  /// Absent => decorative (the a11y layer hides it); present => a labelled image role.
  public var label: String?
}

public struct ImageSpec: Equatable, Sendable {
  public var alt: TextSource
  public var src: Binding
  public var variant: ImageVariant
  /// §3.6.2 — the three presentation slots, each omitted on the wire at its
  /// identity default. TOTAL, not `Optional`: "absent means `Natural`" is a
  /// DEFAULT rather than a third state, so modelling absence as `nil` would
  /// push the decision back out to every reader (the `trendPolarity`
  /// precedent, §3.6.1).
  public var fit: ImageFit = .natural
  public var aspectRatio: ImageAspect = .natural
  public var loading: ImageLoading = .eager
  /// §3.6.4 — absent MEANS the empty list, never `nil`. An absent slot and an
  /// empty one denote the SAME document, so this is `[SrcSetEntry]` and not
  /// `[SrcSetEntry]?`; a surface answering `nil` for an absent `srcSet` has
  /// produced a value the format's own encoder cannot round-trip. AUTHORED
  /// ORDER is preserved — a codec MUST NOT re-sort, because canonicalisation
  /// sorts object keys and never array elements. (Ascending-by-width is a
  /// RENDER-time ordering; see `orderedForPresentation` in the renderer.)
  public var srcSet: [SrcSetEntry] = []
  /// §3.6.5 — the only slot on this record that declares an INTERACTION.
  /// `false` by default and omitted at that default. What it declares is that
  /// the full asset is REACHABLE from the rendered image, not that a lightbox
  /// appears; nothing crosses the dispatch gate (§4), which is why it is a
  /// bool and not an `Action`.
  public var expandable: Bool = false
  /// §3.6.3 — CONTENT, not a presentation token, so it takes the ordinary
  /// optional posture (there is no default caption the way there is a default
  /// fit) and is a `TextSource` rather than a `String`: a caption is
  /// i18n-capable on exactly the terms `alt` is. Narrowing this slot to a
  /// string is the rule a second surface is most likely to break, because it
  /// costs nothing until somebody needs a locale.
  public var caption: TextSource?
}

public struct LabelValueRowSpec: Equatable, Sendable {
  /// The behavioural bool (is this row emphasised?) — 0.2.2 omitted-when-false;
  /// distinct from the `Emphasis` style enum.
  public var emphasis: Bool = false
  public var format: CellFormat = .none
  public var label: TextSource
  /// 0.2.0 rename law — scalar displayed value ⇒ `value` (`data` alias kept).
  public var value: Binding
  public var help: TextSource?
}

public struct LinkSpec: Equatable, Sendable {
  public var href: Binding
  public var label: TextSource
  public var download: Bool
  public var rel: String?
  public var target: String?
  /// Omitted on the wire when `nil`.
  public var protection: LinkProtection?
}

public struct ListSpec: Equatable, Sendable {
  public var items: [TextSource]
  public var ordered: Bool
}

public struct MapSpec: Equatable, Sendable {
  public var centreLatitude: Double
  public var centreLongitude: Double
  public var source: Binding
  public var zoom: Int
  public var onMarkerClick: Closure?
}

public struct MarkdownSpec: Equatable, Sendable {
  public var text: TextSource
}

public struct MathSpec: Equatable, Sendable {
  public var source: String
  public var display: MathDisplay
}

public struct MediaSpec: Equatable, Sendable {
  public var kind: MediaKind
  /// REQUIRED — the one place the media contract differs from `Image`'s. An
  /// image can honestly be decorative and say so with an empty `alt`; a media
  /// element is a TRANSPORT a reader focuses, plays, pauses and seeks, so it is
  /// never decorative. A document omitting it is refused rather than defaulted,
  /// because there is no value to default to that would not be a fabricated
  /// name for someone else's recording.
  public var label: TextSource
  public var src: Binding
  /// Omitted on the wire at TRUE — the second such slot in the vocabulary
  /// (`Toast.dismissable` is the first). The polarity is deliberate: a media
  /// element without a transport cannot be paused, seeked or muted by a
  /// keyboard user at all, so the accessible setting is what a document gets
  /// for free and taking it away is the deviation that costs a key.
  public var controls: Bool = true
  /// The ordinary polarity — omitted at `false`.
  public var loop: Bool = false
  /// §3.6.6 (Phase 1110) — the element's timed-text tracks, on the SPEC rather
  /// than on `MediaKind.video`, because captions and a transcript are not
  /// video-only affordances.
  ///
  /// Absent MEANS the empty list, never `nil` — an absent slot and an empty one
  /// denote the same document, so this is `[TrackEntry]` and not
  /// `[TrackEntry]?`, exactly as `ImageSpec.srcSet` is. AUTHORED ORDER is
  /// preserved and never re-sorted: this is the OPPOSITE of `srcSet`'s rule, and
  /// the difference is not an inconsistency — a browser picks ONE candidate from
  /// a srcset by an algorithm, so ordering it is canonicalisation, while a
  /// reader picks a track from a menu the user agent builds in DOCUMENT order,
  /// so ordering it would be rewriting someone else's menu.
  public var tracks: [TrackEntry] = []
  /// §3.6.6 (Phase 1110) — the element's text alternative.
  ///
  /// An ORDINARY optional, and the contrast with `tracks` is deliberate: absent
  /// means the document offers no transcript, which is a different statement
  /// from offering an empty one. It lives on the spec rather than on the video
  /// variant because a transcript is the affordance an AUDIO surface needs most
  /// — a recording with no visual channel has nowhere else to put its words.
  public var transcript: TextSource?

  public init(
    kind: MediaKind, label: TextSource, src: Binding, controls: Bool = true, loop: Bool = false,
    tracks: [TrackEntry] = [], transcript: TextSource? = nil
  ) {
    self.kind = kind
    self.label = label
    self.src = src
    self.controls = controls
    self.loop = loop
    self.tracks = tracks
    self.transcript = transcript
  }
}

public struct MetricSpec: Equatable, Sendable {
  public var label: TextSource
  /// 0.2.0 rename law — the scalar displayed value is `value` on the wire (the
  /// retired `source` spelling is a hard error; the `data` alias is lenient).
  public var value: Binding
  public var format: CellFormat = .none
  public var tone: ToneVariant = .default
  public var weight: StyleWeight = .standard
  public var emphasis: Emphasis = .normal
  public var trend: Binding?
  public var trendFormat: CellFormat?
  /// §3.6.1 — which way the quantity IMPROVES. TOTAL, not an `Optional`, and
  /// decoded independently of `trend`: the wire's "absent means
  /// `HigherIsBetter`" is a DEFAULT rather than a third state, so modelling it
  /// as `nil` would push the decision back out to every reader. A polarity
  /// declared with no `trend` is inert (legal per clause 4) and is kept rather
  /// than dropped — dropping it would silently rewrite the author's document
  /// because this surface judged the declaration pointless.
  public var trendPolarity: TrendPolarity = .higherIsBetter
  public var icon: String?
  public var subtext: TextSource?
}

public struct ModalSpec: Equatable, Sendable {
  public var children: [Node]
  public var dismissable: Bool
  public var onDismiss: Action?
  public var `open`: Binding
  public var heading: TextSource?
  /// §3.6.11 — omitted at `modal`, which is the blocking modality every
  /// pre-modality document meant. A present value outside the two is
  /// `UNKNOWN_DU_CASE` and a non-string is `WRONG_TYPE`; neither falls back,
  /// because a document asking for a popover and getting a blocking modal has
  /// been answered with a different affordance.
  public var modality: ModalityKind = .modal
}

public struct MountSpec: Equatable, Sendable {
  public var capabilities: [String]
  public var channel: MountChannel
  public var inputs: [FragmentArgEntry]
  public var scopeId: String
}

public struct ProgressSpec: Equatable, Sendable {
  public var fraction: Binding
  public var indeterminate: Bool = false
  public var tone: ToneVariant = .default
  public var label: TextSource?
  public var caveat: TextSource?
}

public struct ScrollAreaSpec: Equatable, Sendable {
  public var children: [Node]
  public var orientation: ScrollOrientation
  public var maxHeight: Int?
  public var maxWidth: Int?
}

public struct SelectSpec: Equatable, Sendable {
  public var label: TextSource
  public var onChange: Closure?
  public var onChangeMulti: Closure?
  public var source: Binding
  public var value: Binding
  public var placeholder: TextSource?
  public var disabled: Binding?
  public var multiple: Bool
  public var values: Binding?
}

public struct SkeletonSpec: Equatable, Sendable {
  public var rows: Int
}

public struct SparklineSpec: Equatable, Sendable {
  public var source: Binding
}

public struct SplitPanelSpec: Equatable, Sendable {
  public var children: [Node]
  public var weight: Double
}

public struct StepperSpec: Equatable, Sendable {
  public var activeStep: Binding
  public var children: [Node]
}

public struct SummaryListSpec: Equatable, Sendable {
  public var children: [Node]
  public var heading: TextSource?
}

/// The declarative selector. The branch follows a state key or - since the widening -
/// any `Binding`, so a `Selection` makes it follow the clicked row. The schema requires
/// at least one of the two (`anyOf`); `on` is the more specific declaration and wins.
public struct SwitchSpec: Equatable, Sendable {
  /// Phase 1122 — the timed carousel: advance to the next case every
  /// this-many milliseconds, omitted at absence. It declares the one fact a
  /// host cannot recover from the tree — every other half of a carousel was
  /// already composable, and nothing in any arrangement of those says a timer
  /// exists.
  ///
  /// A DURATION, never a flag. Non-positive and fractional values are REFUSED
  /// rather than canonicalised: `0` is what an emitter reaches for to mean
  /// "off" and the language already has a spelling for off, an absent key.
  public var autoAdvanceMs: Int?
  public var cases: [SwitchCase]
  public var defaultChild: Node
  public var on: Binding?
  public var stateKey: String?
}

public struct TabsSpec: Equatable, Sendable {
  public var activeIndex: Binding
  public var children: [Node]
  public var orientation: Orientation = .horizontal
  public var onSelect: Closure?
  public var onSelectTag: Closure?
  public var tabHeaders: [TabHeader]?
  public var tabTags: [String]?
  public var activeTag: Binding?
}

public struct ToastSpec: Equatable, Sendable {
  public var dismissable: Bool = true
  public var message: TextSource
  public var `open`: Binding
  public var tone: ToneVariant = .default
}

/// Recursive disclosure with tree semantics (§3.6.12, Phase 1120).
///
/// **This kind carries no `expandable` and no `selectable` boolean, and none is
/// coming.** A behaviour the reader drives is declared as a named State key the
/// host both writes and reads; a flag with no key behind it is a decorative
/// control writing state nothing reads. The slot shapes are fixed by the
/// specification so a host reading them does not have to guess:
///
/// - `expandedStateKey` names a JSON **array of row ids** — the rows currently
///   open. Absent, the tree renders FULLY EXPANDED and does not toggle.
/// - `selectionStateKey` names a bare **row-id string**. Absent, the tree does
///   not select and carries no selected state at all.
///
/// A state value of any other shape reads as *empty* / *none* rather than as an
/// error: this is a host's own state slot and not a wire document, so there is
/// nothing here to refuse, and refusing would blank a tree over a value the
/// reader never authored.
public struct TreeSpec: Equatable, Sendable {
  public var items: [TreeItem]
  public var expandedStateKey: String?
  public var selectionStateKey: String?
  public var onSelect: Closure?

  public init(
    items: [TreeItem], expandedStateKey: String? = nil, selectionStateKey: String? = nil,
    onSelect: Closure? = nil
  ) {
    self.items = items
    self.expandedStateKey = expandedStateKey
    self.selectionStateKey = selectionStateKey
    self.onSelect = onSelect
  }
}

// ── The node kind set ────────────────────────────────────────────────────────

/// The behavioural category a primitive belongs to — recovered on decode, never
/// a wire level.
public enum NodeCategory: Equatable, Sendable {
  case display
  case layout
  case input
  case visualisation
  case structural
}

/// The closed `kind.$type` discriminator set — one case per IDL kind. A decoder
/// dispatches on it with an exhaustive `switch`, so a kind added to the IDL is a
/// build error there until its arm is written.
public enum NodeKindTag: String, CaseIterable, Equatable, Sendable {
  case badge = "Badge"
  case box = "Box"
  case button = "Button"
  case callout = "Callout"
  case chart = "Chart"
  case codeBlock = "CodeBlock"
  case custom = "Custom"
  case dataGrid = "DataGrid"
  case disclosure = "Disclosure"
  case drawing = "Drawing"
  case embed = "Embed"
  case errorBoundary = "ErrorBoundary"
  case fact = "Fact"
  case fileUpload = "FileUpload"
  case filters = "Filters"
  case form = "Form"
  case fragmentDecl = "FragmentDecl"
  case fragmentRef = "FragmentRef"
  case heading = "Heading"
  case icon = "Icon"
  case image = "Image"
  case labelValueRow = "LabelValueRow"
  case link = "Link"
  case list = "List"
  case map = "Map"
  case markdown = "Markdown"
  case math = "Math"
  case media = "Media"
  case metric = "Metric"
  case modal = "Modal"
  case mount = "Mount"
  case progress = "Progress"
  case scrollArea = "ScrollArea"
  case select = "Select"
  case skeleton = "Skeleton"
  case sparkline = "Sparkline"
  case splitPanel = "SplitPanel"
  case stepper = "Stepper"
  case summaryList = "SummaryList"
  case switchKind = "Switch"
  case tabs = "Tabs"
  case toast = "Toast"
  case tree = "Tree"

  /// The host-side behavioural classification (§3.2). Exhaustive by construction.
  public var category: NodeCategory {
    switch self {
    case .badge, .callout, .codeBlock, .drawing, .embed, .fact, .heading, .icon, .image,
      .labelValueRow, .link, .list, .markdown, .math, .media, .metric, .progress, .skeleton,
      .sparkline, .toast, .tree:
      return .display
    case .box, .disclosure, .modal, .scrollArea, .splitPanel, .stepper, .summaryList, .tabs:
      return .layout
    case .button, .fileUpload, .filters, .form, .select:
      return .input
    case .chart, .dataGrid, .map:
      return .visualisation
    case .custom, .errorBoundary, .fragmentDecl, .fragmentRef, .mount, .switchKind:
      return .structural
    }
  }
}

/// The node's primitive kind: the closed, flat `kind.$type` vocabulary.
public indirect enum NodeKind: Equatable, Sendable {
  case badge(BadgeSpec)
  case box(BoxSpec)
  case button(ButtonSpec)
  case callout(CalloutSpec)
  case chart(ChartSpec)
  case codeBlock(CodeBlockSpec)
  case custom(CustomSpec)
  case dataGrid(GridSpec)
  case disclosure(DisclosureSpec)
  case drawing(DrawingSpec)
  case embed(EmbedSpec)
  case errorBoundary(ErrorBoundarySpec)
  case fact(FactSpec)
  case fileUpload(FileUploadSpec)
  case filters([FilterSpec])
  case form(FormSpec)
  case fragmentDecl(FragmentDeclSpec)
  case fragmentRef(FragmentRefSpec)
  case heading(HeadingSpec)
  case icon(IconSpec)
  case image(ImageSpec)
  case labelValueRow(LabelValueRowSpec)
  case link(LinkSpec)
  case list(ListSpec)
  case map(MapSpec)
  case markdown(MarkdownSpec)
  case math(MathSpec)
  case media(MediaSpec)
  case metric(MetricSpec)
  case modal(ModalSpec)
  case mount(MountSpec)
  case progress(ProgressSpec)
  case scrollArea(ScrollAreaSpec)
  case select(SelectSpec)
  case skeleton(SkeletonSpec)
  case sparkline(SparklineSpec)
  case splitPanel(SplitPanelSpec)
  case stepper(StepperSpec)
  case summaryList(SummaryListSpec)
  case switchKind(SwitchSpec)
  case tabs(TabsSpec)
  case toast(ToastSpec)
  case tree(TreeSpec)

  /// The wire discriminator of this kind. Exhaustive by construction.
  public var tag: NodeKindTag {
    switch self {
    case .badge: return .badge
    case .box: return .box
    case .button: return .button
    case .callout: return .callout
    case .chart: return .chart
    case .codeBlock: return .codeBlock
    case .custom: return .custom
    case .dataGrid: return .dataGrid
    case .disclosure: return .disclosure
    case .drawing: return .drawing
    case .embed: return .embed
    case .errorBoundary: return .errorBoundary
    case .fact: return .fact
    case .fileUpload: return .fileUpload
    case .filters: return .filters
    case .form: return .form
    case .fragmentDecl: return .fragmentDecl
    case .fragmentRef: return .fragmentRef
    case .heading: return .heading
    case .icon: return .icon
    case .image: return .image
    case .labelValueRow: return .labelValueRow
    case .link: return .link
    case .list: return .list
    case .map: return .map
    case .markdown: return .markdown
    case .math: return .math
    case .media: return .media
    case .metric: return .metric
    case .modal: return .modal
    case .mount: return .mount
    case .progress: return .progress
    case .scrollArea: return .scrollArea
    case .select: return .select
    case .skeleton: return .skeleton
    case .sparkline: return .sparkline
    case .splitPanel: return .splitPanel
    case .stepper: return .stepper
    case .summaryList: return .summaryList
    case .switchKind: return .switchKind
    case .tabs: return .tabs
    case .toast: return .toast
    case .tree: return .tree
    }
  }

  /// The wire `$type` discriminator of this kind.
  public var typeName: String { tag.rawValue }

  /// The host-side behavioural classification (§3.2).
  public var category: NodeCategory { tag.category }
}
