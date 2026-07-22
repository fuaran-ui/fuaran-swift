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
}

public struct ImageSpec: Equatable, Sendable {
  public var alt: TextSource
  public var src: Binding
  public var variant: ImageVariant
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

  public static let empty = DrawStyle(
    fill: nil, stroke: nil, strokeWidth: nil, opacity: nil,
    textAnchor: nil, fontSize: nil, emphasis: nil, fontFamily: nil, markId: nil)
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
}

public struct FormField: Equatable, Sendable {
  public var id: String
  public var kind: FormFieldKind
  public var label: TextSource
  public var required: Bool
  public var help: TextSource?
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
}

public struct GridSpec: Equatable, Sendable {
  public var columns: [ColumnErased]
  public var editable: Bool
  public var source: Binding
  public var onRowClick: Closure?
  public var rowKey: Closure?
  public var rowKeyField: String?
  public var staticRows: StaticRows?
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

public struct SwitchSpec: Equatable, Sendable {
  public var stateKey: String
  public var cases: [SwitchCase]
  public var defaultChild: Node
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
