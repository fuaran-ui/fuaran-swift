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

  public init(
    kind: MediaKind, label: TextSource, src: Binding, controls: Bool = true, loop: Bool = false
  ) {
    self.kind = kind
    self.label = label
    self.src = src
    self.controls = controls
    self.loop = loop
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
}

public struct ViewBox: Equatable, Sendable {
  public var minX: Double
  public var minY: Double
  public var width: Double
  public var height: Double
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
}

// ── Input specs ──────────────────────────────────────────────────────────────

public enum FormFieldKind: Equatable, Sendable {
  case text(value: Binding, onChange: Closure?)
  case number(value: Binding, onChange: Closure?)
  case checkbox(value: Binding, onToggle: Closure?)
  /// The switch affordance: the same boolean slot as `checkbox`, a different control.
  case toggle(value: Binding, onToggle: Closure?)
  case choice(options: Binding, value: Binding, onChange: Closure?)
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
}

public struct ChartSpec: Equatable, Sendable {
  public var kind: ChartKind
  public var source: Binding
  public var stacked: Bool
  public var xField: String
  public var yFields: [String]
  public var title: TextSource?
  public var onPointClick: Closure?
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

public struct SwitchCase: Equatable, Sendable {
  public var matchValue: String
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
