// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The node envelope (§3.1) and the flat `NodeKind` wire vocabulary (§3.2). The
// closed set is a Swift `enum`; the exhaustive `typeName` / `category`
// switches (no `default` arm) are the compile-time guard: adding a `NodeKind`
// case without extending them is a build error, so a new kind can never slip in
// as a silent fallback.

import Foundation

/// A reference box for the state-behaviour subtrees. `StateBehaviour` is an
/// inline field of `Node`, so its optional child `Node`s must sit behind a
/// reference to keep the value graph finite (the `NodeKind` payloads are boxed
/// by `indirect`, but `Node.state` is not).
public final class NodeRef: Equatable, @unchecked Sendable {
  public let node: Node
  public init(_ node: Node) { self.node = node }
  public static func == (l: NodeRef, r: NodeRef) -> Bool { l.node == r.node }
}

/// State-dependent alternative renderings (§3.1). `onError` is a closure (§4) —
/// presence only.
public struct StateBehaviour: Equatable, Sendable {
  public var onLoading: NodeRef?
  public var onEmpty: NodeRef?
  public var onError: Closure?

  public static let empty = StateBehaviour(onLoading: nil, onEmpty: nil, onError: nil)

  public var isEmpty: Bool { onLoading == nil && onEmpty == nil && onError == nil }
}

/// The semantic-style triple plus the Phase 147 role/voice (both omitted on the
/// wire at their defaults).
public struct SemanticStyle: Equatable, Sendable {
  public var emphasis: Emphasis
  public var tone: ToneVariant
  public var weight: StyleWeight
  public var role: StyleRole
  public var voice: FontVoice

  public static let `default` = SemanticStyle(
    emphasis: .normal, tone: .default, weight: .standard, role: .none, voice: .default)

  public var isDefault: Bool { self == .default }
}

public struct Accessibility: Equatable, Sendable {
  public var label: Binding?
  public var labelledBy: String?
  public var describedBy: String?
  public var role: String?
  public var liveRegion: LiveRegionKind?
  public var hidden: Binding?
}

/// The behavioural category a primitive belongs to — recovered on decode, never
/// a wire level.
public enum NodeCategory: Equatable, Sendable {
  case layout
  case display
  case input
  case visualisation
  case structural
}

/// The node's primitive kind: the closed, flat `kind.$type` vocabulary.
public indirect enum NodeKind: Equatable, Sendable {
  // Layout
  case box(BoxSpec)
  case splitPanel(SplitPanelSpec)
  case tabs(TabsSpec)
  case stepper(StepperSpec)
  case summaryList(SummaryListSpec)
  case disclosure(DisclosureSpec)
  case modal(ModalSpec)
  case scrollArea(ScrollAreaSpec)
  // Display
  case heading(HeadingSpec)
  case markdown(MarkdownSpec)
  case metric(MetricSpec)
  case badge(BadgeSpec)
  case sparkline(SparklineSpec)
  case callout(CalloutSpec)
  case progress(ProgressSpec)
  case skeleton(SkeletonSpec)
  case icon(IconSpec)
  case fact(FactSpec)
  case labelValueRow(LabelValueRowSpec)
  case link(LinkSpec)
  case image(ImageSpec)
  case list(ListSpec)
  case toast(ToastSpec)
  case codeBlock(CodeBlockSpec)
  case math(MathSpec)
  case drawing(DrawingSpec)
  // Input
  case form(FormSpec)
  case filters([FilterSpec])
  case button(ButtonSpec)
  case fileUpload(FileUploadSpec)
  case select(SelectSpec)
  // Visualisation
  case dataGrid(GridSpec)
  case chart(ChartSpec)
  case map(MapSpec)
  // Structural
  case custom(CustomSpec)
  case errorBoundary(ErrorBoundarySpec)
  case switchKind(SwitchSpec)
  case fragmentDecl(FragmentDeclSpec)
  case fragmentRef(FragmentRefSpec)
  case mount(MountSpec)

  /// The wire `$type` discriminator of this kind. Exhaustive by construction.
  public var typeName: String {
    switch self {
    case .box: return "Box"
    case .splitPanel: return "SplitPanel"
    case .tabs: return "Tabs"
    case .stepper: return "Stepper"
    case .summaryList: return "SummaryList"
    case .disclosure: return "Disclosure"
    case .modal: return "Modal"
    case .scrollArea: return "ScrollArea"
    case .heading: return "Heading"
    case .markdown: return "Markdown"
    case .metric: return "Metric"
    case .badge: return "Badge"
    case .sparkline: return "Sparkline"
    case .callout: return "Callout"
    case .progress: return "Progress"
    case .skeleton: return "Skeleton"
    case .icon: return "Icon"
    case .fact: return "Fact"
    case .labelValueRow: return "LabelValueRow"
    case .link: return "Link"
    case .image: return "Image"
    case .list: return "List"
    case .toast: return "Toast"
    case .codeBlock: return "CodeBlock"
    case .math: return "Math"
    case .drawing: return "Drawing"
    case .form: return "Form"
    case .filters: return "Filters"
    case .button: return "Button"
    case .fileUpload: return "FileUpload"
    case .select: return "Select"
    case .dataGrid: return "DataGrid"
    case .chart: return "Chart"
    case .map: return "Map"
    case .custom: return "Custom"
    case .errorBoundary: return "ErrorBoundary"
    case .switchKind: return "Switch"
    case .fragmentDecl: return "FragmentDecl"
    case .fragmentRef: return "FragmentRef"
    case .mount: return "Mount"
    }
  }

  /// The host-side behavioural classification (§3.2). Exhaustive by construction.
  public var category: NodeCategory {
    switch self {
    case .box, .splitPanel, .tabs, .stepper, .summaryList, .disclosure, .modal, .scrollArea:
      return .layout
    case .heading, .markdown, .metric, .badge, .sparkline, .callout, .progress, .skeleton,
      .icon, .fact, .labelValueRow, .link, .image, .list, .toast, .codeBlock, .math, .drawing:
      return .display
    case .form, .filters, .button, .fileUpload, .select:
      return .input
    case .dataGrid, .chart, .map:
      return .visualisation
    case .custom, .errorBoundary, .switchKind, .fragmentDecl, .fragmentRef, .mount:
      return .structural
    }
  }
}

/// The typed UI tree node (§3.1). `motion` / `extraAttributes` are wire-omitted
/// by design (§9) and therefore not modelled by this render projection.
public struct Node: Equatable, Sendable {
  public var id: String
  public var kind: NodeKind
  public var state: StateBehaviour
  public var style: SemanticStyle
  public var accessibility: Accessibility?

  public init(
    id: String, kind: NodeKind, state: StateBehaviour = .empty,
    style: SemanticStyle = .default, accessibility: Accessibility? = nil
  ) {
    self.id = id
    self.kind = kind
    self.state = state
    self.style = style
    self.accessibility = accessibility
  }
}
