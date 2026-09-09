// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The bare-string enumerations of the Fuaran UI wire format (WIRE_FORMAT §3.5):
// closed vocabularies that ride the wire as a plain JSON string. Each is a
// Swift `String`-raw enum whose `rawValue` is the wire spelling, so
// `init?(rawValue:)` is the from-wire parse and a missing case is an
// (throwable) unknown-discriminator, never a silent fallback.

import Foundation

public enum Orientation: String, CaseIterable, Equatable, Sendable {
  case vertical = "Vertical"
  case horizontal = "Horizontal"
}

public enum ScrollOrientation: String, CaseIterable, Equatable, Sendable {
  case vertical = "Vertical"
  case horizontal = "Horizontal"
  case both = "Both"
}

public enum BadgeVariant: String, CaseIterable, Equatable, Sendable {
  case neutral = "Neutral"
  case brand = "Brand"
  case success = "Success"
  case warning = "Warning"
  case critical = "Critical"
  case info = "Info"
}

public enum ButtonVariant: String, CaseIterable, Equatable, Sendable {
  case primary = "Primary"
  case secondary = "Secondary"
  case tertiary = "Tertiary"
  case destructive = "Destructive"
}

public enum HeadingVariant: String, CaseIterable, Equatable, Sendable {
  case standard = "Standard"
  case eyebrow = "Eyebrow"
  case caption = "Caption"
  case lead = "Lead"
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

public enum StyleWeight: String, CaseIterable, Equatable, Sendable {
  case compact = "Compact"
  case standard = "Standard"
  case spacious = "Spacious"
}

public enum Emphasis: String, CaseIterable, Equatable, Sendable {
  case quiet = "Quiet"
  case normal = "Normal"
  case loud = "Loud"
}

public enum StyleRole: String, CaseIterable, Equatable, Sendable {
  case none = "None"
  case eyebrow = "Eyebrow"
  case data = "Data"
  case lede = "Lede"
  case caption = "Caption"
}

public enum FontVoice: String, CaseIterable, Equatable, Sendable {
  case `default` = "Default"
  case display = "Display"
  case structural = "Structural"
}

public enum ChartKind: String, CaseIterable, Equatable, Sendable {
  case line = "Line"
  case bar = "Bar"
  case area = "Area"
  case pie = "Pie"
  case scatter = "Scatter"
  case heatmap = "Heatmap"
}

public enum ImageVariant: String, CaseIterable, Equatable, Sendable {
  case `default` = "Default"
  case avatar = "Avatar"
  case rounded = "Rounded"
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

/// Anti-scraper render strategy for a `Link` — `email` marks a `mailto:` link
/// whose address must not appear in plaintext in emitted markup (the emission
/// strategy is renderer-owned; a render projection may treat it as advisory).
/// Lower-case on the wire.
public enum LinkProtection: String, CaseIterable, Equatable, Sendable {
  case email = "email"
}

/// The rendered size of a standalone `Icon`. Omitted on the wire at `Medium`.
public enum IconSize: String, CaseIterable, Equatable, Sendable {
  case small = "Small"
  case medium = "Medium"
  case large = "Large"
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

public enum DurationUnit: String, CaseIterable, Equatable, Sendable {
  case seconds = "Seconds"
  case minutes = "Minutes"
  case hours = "Hours"
}

/// How a `Duration` renders: `1h 5m` / `01:05:00` / `1 hour 5 minutes`.
public enum DurationStyle: String, CaseIterable, Equatable, Sendable {
  case compact = "Compact"
  case clock = "Clock"
  case long = "Long"
}

/// A sort direction. Lower-case on the wire, like `LinkProtection`.
public enum SortDirection: String, CaseIterable, Equatable, Sendable {
  case asc = "asc"
  case desc = "desc"
}

public enum MathDisplay: String, CaseIterable, Equatable, Sendable {
  case inline = "Inline"
  case block = "Block"
}

public enum DateVariant: String, CaseIterable, Equatable, Sendable {
  case date = "Date"
  case time = "Time"
  case dateTime = "DateTime"
}

/// §3.6.11 — the modality a `Modal` declares. Omitted at `modal`, which is the
/// blocking modality every pre-modality document meant.
public enum ModalityKind: String, CaseIterable, Equatable, Sendable {
  case modal = "Modal"
  case popover = "Popover"
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

/// Phase 1536 — `Action.navigate`'s destination window (§3.6.21). A CLOSED
/// enum of two, deliberately not HTML's `target` attribute: that vocabulary
/// also carries `_parent` and `_top`, which are frame-busting gestures a hosted
/// tree must not be able to ask for, so `_blank` is refused rather than aliased
/// — accepting any of it would teach an emitter the wrong vocabulary.
public enum NavigateTarget: String, CaseIterable, Equatable, Sendable {
  case selfWindow = "Self"
  case blank = "Blank"
}

/// Phase 1116 — the recording device a `FileUpload` asks the platform for
/// (§3.6.18). There is deliberately no display-capture case and there will not
/// be one by widening this member: a screen capture reaches every window the
/// reader has open rather than one device behind the picker.
public enum CaptureSource: String, CaseIterable, Equatable, Sendable {
  case camera = "Camera"
  case microphone = "Microphone"
}

public enum FileReadEncoding: String, CaseIterable, Equatable, Sendable {
  case text = "Text"
  case base64 = "Base64"
  case dataUrl = "DataUrl"
}

public enum LiveRegionKind: String, CaseIterable, Equatable, Sendable {
  case polite = "polite"
  case assertive = "assertive"
  case off = "off"
}

public enum DateStyle: String, CaseIterable, Equatable, Sendable {
  case short = "Short"
  case medium = "Medium"
  case long = "Long"
  case full = "Full"
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

public enum HashStrictness: String, CaseIterable, Equatable, Sendable {
  case strictReplay = "StrictReplay"
  case advisoryWarning = "AdvisoryWarning"
  case enforced = "Enforced"
}

public enum BoxRole: String, CaseIterable, Equatable, Sendable {
  case group = "Group"
  case card = "Card"
  case dashboard = "Dashboard"
  case separator = "Separator"
}

public enum HostEffect: String, CaseIterable, Equatable, Sendable {
  case pure = "Pure"
  case readsHost = "ReadsHost"
  case writesHost = "WritesHost"
}

public enum DeterminismSource: String, CaseIterable, Equatable, Sendable {
  case deterministic = "Deterministic"
  case clock = "Clock"
  case random = "Random"
  case network = "Network"
}

public enum ChannelDirection: String, CaseIterable, Equatable, Sendable {
  case outOnly = "OutOnly"
  case twoWay = "TwoWay"
}

public enum TextAnchor: String, CaseIterable, Equatable, Sendable {
  case start = "Start"
  case middle = "Middle"
  case end = "End"
}

// ── Compute layer (dataframe algebra) ────────────────────────────────────────

public enum ColumnType: String, CaseIterable, Equatable, Sendable {
  case int = "int"
  case float = "float"
  case bool = "bool"
  case string = "string"
  case date = "date"
  case timestamp = "timestamp"
}

public enum BinOp: String, CaseIterable, Equatable, Sendable {
  case add, sub, mul, div, mod, eq, ne, lt, le, gt, ge, and, or
  // 0.2.x string predicates.
  case contains
  case startsWith = "startsWith"
  case endsWith = "endsWith"
}

public enum ScalarFn: String, CaseIterable, Equatable, Sendable {
  case abs, round, floor, ceil, length, lower, upper, substr
  case datePart = "datePart"
  // 0.2.x string/date scalar functions.
  case concat, trim, replace
  case dateDiffDays = "dateDiffDays"
}

public enum AggFn: String, CaseIterable, Equatable, Sendable {
  case sum, mean, min, max, count, median, stddev, first, last
}

public enum JoinKind: String, CaseIterable, Equatable, Sendable {
  case inner, left, right, outer
}

public enum WindowFn: String, CaseIterable, Equatable, Sendable {
  case rowNumber = "rowNumber"
  case rank = "rank"
  case lag = "lag"
  case lead = "lead"
  // `cumulSum` is the canonical tag; the legacy `cumSum` spelling decodes as a
  // lenient alias.
  case cumulSum = "cumulSum"
  case rollingMean = "rollingMean"
}

public enum SortDir: String, CaseIterable, Equatable, Sendable {
  case asc, desc
}

/// `FieldRule.format` — the closed named-format set a text field's value is held to.
public enum TextFormat: String, CaseIterable, Equatable, Sendable {
  case email, url, tel
}

/// `CompareRule.op` — the cross-field comparison operator.
public enum CompareOp: String, CaseIterable, Equatable, Sendable {
  case eq, neq, lt, lte, gt, gte
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

  /// The lower-case HTML token a rendering host emits for this case
  /// (§3.6.6 obligation 1). Kept beside the case set so the two cannot drift.
  public var htmlToken: String { rawValue.lowercased() }
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

  /// The `sandbox` attribute token for this relaxation, or `nil` where the
  /// relaxation is not a sandbox token at all.
  ///
  /// `AllowFullscreen` returns `nil` deliberately: it is a **permissions-policy
  /// directive** riding `allow="fullscreen"`, not a sandbox relaxation. A host
  /// that mapped the whole enum onto sandbox tokens round-trips every fixture
  /// and fails its render obligation on `nodes/embed-permissions-1.json`, which
  /// is authored with exactly that one permission for exactly that reason.
  public var sandboxToken: String? {
    switch self {
    case .allowScripts: return "allow-scripts"
    case .allowSameOrigin: return "allow-same-origin"
    case .allowForms: return "allow-forms"
    case .allowFullscreen: return nil
    }
  }

  /// The `allow` (permissions-policy) directive for this relaxation, or `nil`
  /// where it rides `sandbox` instead. The inverse of `sandboxToken`, and the
  /// two are exhaustive complements by construction.
  public var allowDirective: String? {
    switch self {
    case .allowFullscreen: return "fullscreen"
    case .allowScripts, .allowSameOrigin, .allowForms: return nil
    }
  }
}
