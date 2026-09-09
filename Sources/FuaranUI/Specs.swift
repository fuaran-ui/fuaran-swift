// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The per-kind spec records of the Fuaran UI wire vocabulary. Layout containers
// hold `[Node]`; the structural kinds hold single `Node`s (behind the indirect
// `NodeKind`, so the value graph stays finite).

import Foundation

// ── Display specs ────────────────────────────────────────────────────────────

public struct HeadingSpec: Equatable, Sendable {
  public var level: Int
  public var text: TextSource
  public var variant: HeadingVariant
}

public struct MarkdownSpec: Equatable, Sendable {
  public var text: TextSource
}

public struct MetricSpec: Equatable, Sendable {
  public var label: TextSource
  /// 0.2.0 rename law — the scalar displayed value is `value` on the wire (the
  /// retired `source` spelling is a hard error; the `data` alias is lenient).
  public var value: Binding
  public var format: CellFormat
  public var tone: ToneVariant
  public var weight: StyleWeight
  public var emphasis: Emphasis
  public var trend: Binding?
  public var trendFormat: CellFormat?
  /// §3.6.1 — which way the quantity IMPROVES. TOTAL, not an `Optional`, and
  /// decoded independently of `trend`: the wire's "absent means
  /// `HigherIsBetter`" is a DEFAULT rather than a third state, so modelling it
  /// as `nil` would push the decision back out to every reader. A polarity
  /// declared with no `trend` is inert (legal per clause 4) and is kept rather
  /// than dropped — dropping it would silently rewrite the author's document
  /// because this surface judged the declaration pointless.
  public var trendPolarity: TrendPolarity
  public var icon: String?
  public var subtext: TextSource?
}

public struct BadgeSpec: Equatable, Sendable {
  public var label: TextSource
  public var variant: BadgeVariant
}

public struct SparklineSpec: Equatable, Sendable {
  public var source: Binding
}

public struct CalloutSpec: Equatable, Sendable {
  public var body: TextSource
  public var dismissable: Bool
  public var tone: ToneVariant
  public var heading: TextSource?
  public var icon: String?
}

public struct ProgressSpec: Equatable, Sendable {
  public var fraction: Binding
  public var indeterminate: Bool
  public var tone: ToneVariant
  public var label: TextSource?
  public var caveat: TextSource?
}

public struct SkeletonSpec: Equatable, Sendable {
  public var rows: Int
}

public struct LabelValueRowSpec: Equatable, Sendable {
  public var label: TextSource
  /// 0.2.0 rename law — scalar displayed value ⇒ `value` (`data` alias kept).
  public var value: Binding
  public var format: CellFormat
  /// The behavioural bool (is this row emphasised?) — 0.2.2 omitted-when-false;
  /// distinct from the `Emphasis` style enum.
  public var emphasis: Bool
  public var help: TextSource?
}

/// The labeled text-fact kind (0.2.x — `Fact`).
public struct FactSpec: Equatable, Sendable {
  public var label: TextSource
  public var value: TextSource
  public var emphasis: Bool
  public var tone: ToneVariant
  public var help: TextSource?
  public var icon: String?
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

/// A standalone glyph. `icon` is a NAME; the embedding app owns the name -> glyph
/// mapping, so this projection carries the name rather than resolving it.
public struct IconSpec: Equatable, Sendable {
  public var icon: String
  /// Absent => decorative (the a11y layer hides it); present => a labelled image role.
  public var label: String?
  public var size: IconSize
  public var tone: ToneVariant
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
  /// §3.6.3 — CONTENT, not a presentation token, so it takes the ordinary
  /// optional posture (there is no default caption the way there is a default
  /// fit) and is a `TextSource` rather than a `String`: a caption is
  /// i18n-capable on exactly the terms `alt` is. Narrowing this slot to a
  /// string is the rule a second surface is most likely to break, because it
  /// costs nothing until somebody needs a locale.
  public var caption: TextSource? = nil
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
}

// ── Media (§3.6.6) ───────────────────────────────────────────────────────────

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

  /// The wire `$type` of the variant, inside `kind.kind`.
  public var typeName: String {
    switch self {
    case .video: return "Video"
    case .audio: return "Audio"
    }
  }
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
  public var isDefault: Bool

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
  public var transcript: TextSource? = nil

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

// ── Embed (§3.6.8) ───────────────────────────────────────────────────

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

// ── Tree (§3.6.12) ─────────────────────────────────────────────────

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
  public var children: [TreeItem]

  public init(id: String, label: TextSource, icon: String? = nil, children: [TreeItem] = []) {
    self.id = id
    self.label = label
    self.icon = icon
    self.children = children
  }
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

public struct ListSpec: Equatable, Sendable {
  public var items: [TextSource]
  public var ordered: Bool
}

public struct ToastSpec: Equatable, Sendable {
  public var message: TextSource
  public var tone: ToneVariant
  public var open: Binding
  public var dismissable: Bool
}

public struct CodeBlockSpec: Equatable, Sendable {
  public var code: String
  public var language: String
  public var lineNumbers: Bool
  public var highlightLines: [Int]
  public var copyable: Bool
}

public struct MathSpec: Equatable, Sendable {
  public var source: String
  public var display: MathDisplay
}

// ── Drawing (bounded, typed vector graphics) ─────────────────────────────────

public struct DrawPoint: Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
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

  /// The memberwise initialiser, made public deliberately: the style cascade
  /// (`inheritedDrawStyle`) rebuilds a style field by field rather than copying
  /// and patching, so that adding a field to this record is a COMPILE ERROR at
  /// the cascade until someone decides whether it inherits. A copy-and-patch
  /// would silently leave a new field un-inherited.
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

  public static let empty = DrawStyle(
    fill: nil, stroke: nil, strokeWidth: nil, opacity: nil,
    textAnchor: nil, fontSize: nil, emphasis: nil, fontFamily: nil, markId: nil,
    rotation: nil, tip: nil)
}

public indirect enum CurveCommand: Equatable, Sendable {
  case moveTo(DrawPoint)
  case lineTo(DrawPoint)
  case cubicTo(control1: DrawPoint, control2: DrawPoint, to: DrawPoint)
  case quadraticTo(control: DrawPoint, to: DrawPoint)
  case close
}

public indirect enum Shape: Equatable, Sendable {
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

public struct DrawingSpec: Equatable, Sendable {
  public var viewBox: ViewBox
  public var shapes: [Shape]
  public var style: DrawStyle
  public var title: TextSource?
  public var description: TextSource?

  /// Public because a `Drawing` is now something a render projection PRODUCES as
  /// well as decodes: the Phase 1099 sparkline lowering builds one from a
  /// resolved series so the picture goes through the drawing canvas the surface
  /// already has, rather than through a second hand-written vector path.
  ///
  /// This is not an encode leg. The value never becomes wire bytes here — it is
  /// handed straight to the renderer — so the decode-only posture is unchanged.
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

// ── Input specs ──────────────────────────────────────────────────────────────

public enum FormFieldKind: Equatable, Sendable {
  case text(value: Binding, onChange: Closure?)
  case number(value: Binding, onChange: Closure?)
  case checkbox(value: Binding, onToggle: Closure?)
  /// The switch affordance: the same boolean slot as `checkbox`, a different control.
  case toggle(value: Binding, onToggle: Closure?)
  case choice(options: Binding, value: Binding, onChange: Closure?)
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
  /// 0.2.0 — the dual-thumb numeric range (absorbed the retired RangeFilter).
  case range(value: Binding, min: Double?, max: Double?, step: Double?, onChange: Closure?)
  case rangedNumber(
    value: Binding, min: Double?, max: Double?, step: Double?, onChange: Closure?)
  case segmentedChoice(
    options: Binding, orientation: Orientation, value: Binding, onChange: Closure?)
  case textArea(rows: Int, value: Binding, onChange: Closure?)
  case date(
    value: Binding, variant: DateVariant, min: String?, max: String?, step: Double?,
    onChange: Closure?)
  /// 0.7.0 — the single-control date range: `range`'s pair mechanics with
  /// `date`'s value conventions (an identical associated-value list to `date`,
  /// reusing the existing `DateVariant` — no new enum). In a filter context the
  /// pair binds ONE filter param, not two, which is the reason the case exists
  /// rather than two coordinated `date` fields.
  case dateRange(
    value: Binding, variant: DateVariant, min: String?, max: String?, step: Double?,
    onChange: Closure?)
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
  case tokens(
    value: Binding, suggestions: Binding?, allowFreeText: Bool, onChange: Closure?)
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
}

/// The cross-field operand. `against` is a `Binding`, and that IS the
/// cross-field mechanism rather than an accident of typing: any read slot may
/// take a Binding, and the auto-bind rule already puts every form field's value
/// in State under the field's own id, so `{"$type":"State","key":"<sibling id>"}`
/// reads the sibling with no coordination vocabulary at all.
public struct CompareRule: Equatable, Sendable {
  public var op: CompareOp
  public var against: Binding
}

/// A field's declared constraint — the ACCEPTED SET, where `FormFieldKind`
/// names the control. Every slot is optional structurally; the two
/// well-formedness refusals (a rule that constrains nothing; `minLength` above
/// `maxLength`) are relations BETWEEN slots and so live in the decoder's policy
/// layer rather than in this shape.
public struct FieldRule: Equatable, Sendable {
  public var format: TextFormat?
  public var pattern: String?
  public var minLength: Int?
  public var maxLength: Int?
  public var compare: CompareRule?
  public var message: TextSource?
}

public struct FormField: Equatable, Sendable {
  public var id: String
  public var kind: FormFieldKind
  public var label: TextSource
  public var required: Bool
  public var help: TextSource?
  public var rule: FieldRule?
}

public struct FormSpec: Equatable, Sendable {
  public var fields: [FormField]
  public var onSubmit: Action
  public var submitLabel: TextSource
  public var disabled: Binding?
}

/// 0.2.0 filters-unification: a chip's control is an ordinary `FormFieldKind`
/// (the retired `*Filter` discriminators are hard errors); its absent `value`
/// slot auto-binds `Filter(name)`.
public struct FilterSpec: Equatable, Sendable {
  public var kind: FormFieldKind
  public var label: TextSource
  public var name: String
}

public struct ButtonSpec: Equatable, Sendable {
  public var label: TextSource
  public var onClick: Action
  public var variant: ButtonVariant
  public var icon: String?
  public var disabled: Binding?
}

public struct SelectSpec: Equatable, Sendable {
  public var label: TextSource
  public var source: Binding
  public var value: Binding
  public var onChange: Closure?
  public var placeholder: TextSource?
  public var disabled: Binding?
  public var multiple: Bool
  public var values: Binding?
  public var onChangeMulti: Closure?
}

public struct FileUploadSpec: Equatable, Sendable {
  public var accept: [String]
  public var label: TextSource
  public var multiple: Bool
  public var disabled: Binding?
  /// Phase 1115 — two ADDITIONAL ingress routes, never replacements for the
  /// picker. Both omit at `false`, and the polarity is load-bearing: the
  /// shortest upload document is the plain picker, which is what every document
  /// written before that revision says.
  public var dropTarget: Bool
  public var acceptPaste: Bool
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
}

// ── Visualisation specs ──────────────────────────────────────────────────────

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

public struct ColumnErased: Equatable, Sendable {
  public var format: CellFormat
  public var kind: CellKindErased
  public var label: String
  public var width: ColumnWidth
  public var value: Closure?
  public var field: String?
}

public struct StaticRows: Equatable, Sendable {
  public var headers: [TextSource]
  public var rows: [[TextSource]]
  public var defaultSort: DefaultSort?
  public var sortable: Bool?
}

/// An initial sort: a zero-based header INDEX (the schema pins `minimum: 0`, so a
/// negative is malformed rather than a from-the-end convention) plus a direction.
public struct DefaultSort: Equatable, Sendable {
  public var column: Int
  public var direction: SortDirection
}

public struct GridSpec: Equatable, Sendable {
  public var columns: [ColumnErased]
  public var editable: Bool
  public var source: Binding
  public var onRowClick: Closure?
  public var rowKey: Closure?
  public var rowKeyField: String?
  public var staticRows: StaticRows?
  /// The sort / page / edit POSITIONS are addressed through state keys rather than
  /// literal values, so a control can move them; `defaultSort` and `pageSize` are the
  /// initial configuration. Decoded faithfully because this is a view of the wire -
  /// dropping a declaration would misreport the tree. Acting on them is the renderer's
  /// business, not the decoder's.
  public var sortStateKey: String?
  public var pageStateKey: String?
  public var editStateKey: String?
  /// Rows per page. The schema pins `minimum: 1` - a zero page size paginates nothing.
  public var pageSize: Int?
  public var defaultSort: DefaultSort?
  /// Phase 1473 — the paginated-media pair, on `Box`'s terms.
  public var keepRowsTogether: Bool
  public var repeatHeader: Bool
  /// Phase 1123 — this grid's rows may be taken out of the page as a file.
  /// Omitted at `false`.
  public var exportable: Bool
  /// Phase 1125 — the two sides of ONE shared State key. A grid declaring
  /// `transferOutKey` K may RELEASE rows onto K; one declaring `transferInKey`
  /// K ACCEPTS rows arriving on it. Separate decoder arms, and the corpus
  /// vectors them separately for that reason.
  public var transferInKey: String?
  public var transferOutKey: String?
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

public struct ChartSpec: Equatable, Sendable {
  public var kind: ChartKind
  public var source: Binding
  public var stacked: Bool
  public var xField: String
  public var yFields: [String]
  public var title: TextSource?
  public var onPointClick: Closure?
  /// Phase 1490 — omitted when the chart declares none.
  public var annotations: [ChartAnnotation]?
}

public struct MapSpec: Equatable, Sendable {
  public var centreLatitude: Double
  public var centreLongitude: Double
  public var source: Binding
  public var zoom: Int
  public var onMarkerClick: Closure?
}

// ── Layout specs ─────────────────────────────────────────────────────────────

public enum BoxLayout: Equatable, Sendable {
  case flex(direction: Orientation, gap: Int?, wrap: Bool)
  case grid(cols: Int, gap: Int?, templateColumns: String?)
  /// WIRE_FORMAT §3.6.7 (Phase 1082) — the column-fill mode. `cols` is
  /// REQUIRED and POSITIVE; there is deliberately no `templateColumns` twin,
  /// because the multi-column model realising masonry has no track list for
  /// one to name.
  case masonry(cols: Int, gap: Int?)
  case auto
}

public struct BoxSpec: Equatable, Sendable {
  public var children: [Node]
  public var heading: TextSource?
  public var layout: BoxLayout
  public var role: BoxRole
  /// Phase 1473 — the print-break controls. Both omit at `false`, and both are
  /// declarations about PAGINATED media alone: a screen host reads them and
  /// emits nothing.
  public var breakBefore: Bool
  public var keepTogether: Bool
}

public struct SplitPanelSpec: Equatable, Sendable {
  public var children: [Node]
  public var weight: Double
}

public struct TabHeader: Equatable, Sendable {
  public var label: TextSource
  public var icon: String?
  public var disabled: Binding?
}

public struct TabsSpec: Equatable, Sendable {
  public var children: [Node]
  public var orientation: Orientation
  public var activeIndex: Binding
  public var onSelect: Closure?
  public var tabHeaders: [TabHeader]?
  public var tabTags: [String]?
  public var activeTag: Binding?
  public var onSelectTag: Closure?
}

public struct StepperSpec: Equatable, Sendable {
  public var activeStep: Binding
  public var children: [Node]
}

public struct SummaryListSpec: Equatable, Sendable {
  public var children: [Node]
  public var heading: TextSource?
}

public struct DisclosureSpec: Equatable, Sendable {
  public var children: [Node]
  public var defaultOpen: Bool
  public var heading: TextSource
  public var open: Binding
  public var onToggle: Closure?
}

public struct ModalSpec: Equatable, Sendable {
  public var children: [Node]
  public var dismissable: Bool
  public var open: Binding
  public var onDismiss: Action?
  public var heading: TextSource?
  /// §3.6.11 — omitted at `modal`, which is the blocking modality every
  /// pre-modality document meant. A present value outside the two is
  /// `UNKNOWN_DU_CASE` and a non-string is `WRONG_TYPE`; neither falls back,
  /// because a document asking for a popover and getting a blocking modal has
  /// been answered with a different affordance.
  public var modality: ModalityKind
}

public struct ScrollAreaSpec: Equatable, Sendable {
  public var children: [Node]
  public var orientation: ScrollOrientation
  public var maxHeight: Int?
  public var maxWidth: Int?
}

// ── Structural kinds ─────────────────────────────────────────────────────────

public struct ContentHash: Equatable, Sendable {
  public var algorithm: String
  public var hash: String
  public var strictness: HashStrictness
}

public struct CustomSpec: Equatable, Sendable {
  public var moduleId: String
  public var componentId: String
  public var props: [String: JSON]
  public var contentHash: ContentHash?
  public var exposedNodeIds: [String]
}

public struct ErrorBoundarySpec: Equatable, Sendable {
  public var child: Node
  public var fallback: Node
}

/// Phase 1535 — the two spellings of a case's condition. They interleave freely
/// in one ordered `cases` array, and first-match-wins runs over the array in
/// AUTHORED order: a host evaluates case *n* fully before considering case
/// *n+1*, and must not batch all the matches ahead of all the predicates.
public enum SwitchCondition: Equatable, Sendable {
  /// Compares the switch's resolved selector against a literal string.
  case match(String)
  /// Evaluates a `Binding<bool>` and takes the case on a RESOLVED `true` only —
  /// a resolved `false`, an unresolved binding and an errored one all fall
  /// through. There is no truthiness rule: `0`, `""` and `"false"` are refused
  /// by the coercion rather than read as `false`.
  ///
  /// It consults no selector at all, so a switch whose cases are ALL predicates
  /// needs no `on` and has no state key for anything to write.
  case when(Binding)
}

public struct SwitchCase: Equatable, Sendable {
  /// EXACTLY ONE of `match` and `when` is present (§3.6) — both together and
  /// neither at all are decode errors, the same shape and the same reasoning as
  /// `setState`'s `value` / `valueFrom` pair.
  ///
  /// A case naming no condition is not a case that never matches; it is a
  /// document whose author meant something the wire cannot say, and a host that
  /// silently skipped it would render the `default` and report nothing. A
  /// precedence rule for "both" would have to be specified, agreed on every
  /// host and remembered by every author, for a document nobody meant to write.
  public var condition: SwitchCondition
  public var child: Node
}

/// The declarative selector. The branch follows a state key or - since the widening -
/// any `Binding`, so a `Selection` makes it follow the clicked row. The schema requires
/// at least one of the two (`anyOf`); `on` is the more specific declaration and wins.
public struct SwitchSpec: Equatable, Sendable {
  public var stateKey: String?
  public var cases: [SwitchCase]
  public var defaultChild: Node
  public var on: Binding?
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
}

public enum HoleValueSpace: Equatable, Sendable {
  case intRange(min: Int, max: Int)
  case floatRange(min: Double, max: Double)
  case stringLen(minLen: Int, maxLen: Int)
  case enumChoices(choices: [String])
  case anyString
}

public enum FragmentScalar: Equatable, Sendable {
  case int(Int)
  case float(Double)
  case bool(Bool)
  case str(String)
}

public enum HoleDecl: Equatable, Sendable {
  case value(name: String, space: HoleValueSpace, default: FragmentScalar?)
  case slot(name: String, kindConstraint: String?)
  case repeatHole(name: String, countSpace: HoleValueSpace)
}

public struct EffectClass: Equatable, Sendable {
  public var hostEffect: HostEffect
  public var determinism: DeterminismSource

  public static let pureDeterministic = EffectClass(
    hostEffect: .pure, determinism: .deterministic)
}

public enum FragmentArg: Equatable, Sendable {
  case value(FragmentScalar)
  case slot(tree: Node)
}

/// A named `FragmentArg` entry (fragment-ref args / mount inputs). A named
/// struct rather than a `(String, FragmentArg)` tuple so `Equatable` synthesis
/// works.
public struct FragmentArgEntry: Equatable, Sendable {
  public var name: String
  public var arg: FragmentArg
  public init(name: String, arg: FragmentArg) {
    self.name = name
    self.arg = arg
  }
}

public struct FragmentDeclSpec: Equatable, Sendable {
  public var name: String
  public var body: Node
  public var holes: [HoleDecl]
  public var effect: EffectClass
}

public struct FragmentRefSpec: Equatable, Sendable {
  public var name: String
  public var args: [FragmentArgEntry]
}

public struct MountChannel: Equatable, Sendable {
  public var direction: ChannelDirection
  public var messageShape: String?
}

public struct MountSpec: Equatable, Sendable {
  public var scopeId: String
  public var inputs: [FragmentArgEntry]
  public var channel: MountChannel
  public var capabilities: [String]
}
