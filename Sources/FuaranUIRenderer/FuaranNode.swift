// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The SwiftUI renderer floor (Phase 540): the first genuinely native render
// target of the Fuaran UI vocabulary. `FuaranNode` projects a decoded `Node`
// (the sealed Phase 538 model) as SwiftUI views — the wire tree rendered as
// SwiftUI, not HTML. A **pure projection**: no wire-JSON parsing happens here
// (decode ran first, in `FuaranUI.RenderProjection`).
//
// The dispatch spine `fuaranNodeBody` is an **exhaustive `switch` over the
// sealed `NodeKind` with no `default` arm** — a new wire kind is a compile error
// until its arm lands (the render-floor twin of the Phase 538 decode spine). A
// visible development placeholder (`fallbackPlaceholder`) is the *defined*
// fallback a host may deliberately route an unimplemented kind through; it is
// structurally unreachable from the exhaustive spine and its use is loud
// (coverage-tracked).
//
// The whole file is guarded by `#if canImport(SwiftUI)` — on a platform without
// SwiftUI (Linux / Windows dev boxes) it compiles to nothing and the pure model
// + decoder (Phase 538) stand alone, mirroring how `Session.swift` is guarded on
// the native-core flag. The reference target is macOS (the CI `swift` job).

#if canImport(SwiftUI)

  import Foundation
  import FuaranUI
  import SwiftUI

  // ── Tone tokens (Phase 540 light floor; the full light/dark tone bridge is
  //    Phase 541's Theme.swift, which supersedes this section) ────────────────

  /// A resolved tone swatch: a filled container, its readable foreground, and an
  /// accent for emphasis.
  struct ToneSwatch {
    let container: Color
    let onContainer: Color
    let accent: Color
  }

  /// The light-scheme tone mapping (higher-luminance containers, dark
  /// foregrounds). Phase 541 replaces this with a scheme-aware palette.
  func toneSwatch(_ tone: ToneVariant) -> ToneSwatch {
    switch tone {
    case .default: return ToneSwatch(container: c(0.95, 0.95, 0.96), onContainer: c(0.11, 0.11, 0.12), accent: c(0.23, 0.23, 0.25))
    case .subdued: return ToneSwatch(container: c(0.90, 0.90, 0.92), onContainer: c(0.35, 0.35, 0.38), accent: c(0.45, 0.45, 0.49))
    case .brand: return ToneSwatch(container: c(0.86, 0.89, 1.0), onContainer: c(0.0, 0.10, 0.25), accent: c(0.18, 0.36, 0.82))
    case .success: return ToneSwatch(container: c(0.83, 0.95, 0.85), onContainer: c(0.02, 0.21, 0.10), accent: c(0.12, 0.48, 0.27))
    case .warning: return ToneSwatch(container: c(0.99, 0.91, 0.76), onContainer: c(0.24, 0.18, 0.0), accent: c(0.60, 0.42, 0.0))
    case .critical: return ToneSwatch(container: c(0.99, 0.85, 0.84), onContainer: c(0.25, 0.0, 0.01), accent: c(0.73, 0.10, 0.10))
    case .info: return ToneSwatch(container: c(0.81, 0.91, 0.96), onContainer: c(0.02, 0.19, 0.25), accent: c(0.05, 0.43, 0.58))
    }
  }

  /// Map the badge-variant vocabulary onto the tone palette (Neutral → subdued).
  func badgeSwatch(_ variant: BadgeVariant) -> ToneSwatch {
    switch variant {
    case .neutral: return toneSwatch(.subdued)
    case .brand: return toneSwatch(.brand)
    case .success: return toneSwatch(.success)
    case .warning: return toneSwatch(.warning)
    case .critical: return toneSwatch(.critical)
    case .info: return toneSwatch(.info)
    }
  }

  private func c(_ r: Double, _ g: Double, _ b: Double) -> Color {
    Color(red: r, green: g, blue: b)
  }

  // ── Public entry — the exhaustive dispatch spine ──────────────────────────

  /// Render a decoded `Node` as SwiftUI. A pure projection of the sealed model.
  public struct FuaranNode: View {
    let node: Node
    let ctx: BindingContext

    public init(_ node: Node, _ ctx: BindingContext = .empty) {
      self.node = node
      self.ctx = ctx
    }

    public var body: some View { fuaranNodeBody(node, ctx) }
  }

  /// The dispatch: record coverage, then an **exhaustive `switch` with no
  /// `default`** over the sealed `NodeKind`. Written as a plain function
  /// (returning `AnyView`) rather than a `@ViewBuilder` so the coverage
  /// side-effect statement is legal and so a coverage walk can invoke it
  /// directly, node by node, without a live render pass.
  @MainActor
  func fuaranNodeBody(_ node: Node, _ ctx: BindingContext) -> AnyView {
    ctx.coverage?.count(node.kind.typeName)
    switch node.kind {
    // Layout
    case .box(let k): return AnyView(RenderBox(k: k, ctx: ctx))
    case .splitPanel(let k): return AnyView(RenderSplitPanel(k: k, ctx: ctx))
    case .tabs(let k): return AnyView(RenderTabs(k: k, ctx: ctx))
    case .stepper(let k): return AnyView(RenderStepper(k: k, ctx: ctx))
    case .summaryList(let k): return AnyView(RenderSummaryList(k: k, ctx: ctx))
    case .disclosure(let k): return AnyView(RenderDisclosure(k: k, ctx: ctx))
    case .modal(let k): return AnyView(RenderModal(k: k, ctx: ctx))
    case .scrollArea(let k): return AnyView(RenderScrollArea(k: k, ctx: ctx))
    // Display
    case .heading(let k): return AnyView(RenderHeading(k: k, ctx: ctx))
    case .markdown(let k): return AnyView(Text(ctx.resolveText(k.text)).padding(2))
    case .metric(let k): return AnyView(RenderMetric(k: k, ctx: ctx))
    case .badge(let k): return AnyView(RenderBadge(k: k, ctx: ctx))
    case .sparkline: return AnyView(RenderSparkline())
    case .callout(let k): return AnyView(RenderCallout(k: k, ctx: ctx))
    case .progress(let k): return AnyView(RenderProgress(k: k, ctx: ctx))
    case .skeleton(let k): return AnyView(RenderSkeleton(rows: k.rows))
    case .labelValueRow(let k): return AnyView(RenderLabelValueRow(k: k, ctx: ctx))
    case .link(let k): return AnyView(RenderLink(k: k, ctx: ctx))
    case .image(let k): return AnyView(RenderImage(k: k, ctx: ctx))
    case .list(let k): return AnyView(RenderList(k: k, ctx: ctx))
    case .toast(let k): return AnyView(RenderToast(k: k, ctx: ctx))
    case .codeBlock(let k): return AnyView(RenderCodeBlock(code: k.code))
    case .math(let k): return AnyView(Text(k.source).font(.system(.body, design: .monospaced)).padding(2))
    case .drawing(let k): return AnyView(RenderDrawing(k: k, ctx: ctx))
    // Input
    case .form(let k): return AnyView(RenderForm(k: k, ctx: ctx))
    case .filters(let items): return AnyView(RenderFilters(items: items, ctx: ctx))
    case .button(let k): return AnyView(RenderButton(k: k, ctx: ctx))
    case .fileUpload(let k):
      return AnyView(Button(ctx.resolveText(k.label)) {}.disabled(ctx.resolveBool(k.disabled)))
    case .select(let k): return AnyView(RenderSelect(k: k, ctx: ctx))
    // Visualisation
    case .dataGrid(let k): return AnyView(RenderDataGrid(k: k, ctx: ctx))
    case .chart(let k): return AnyView(RenderChart(k: k, ctx: ctx))
    case .map(let k):
      return AnyView(InfoCard(title: "Map", subtitle: "lat \(k.centreLatitude), lng \(k.centreLongitude) · z\(k.zoom)"))
    // Structural
    case .custom(let k): return AnyView(InfoCard(title: "Custom", subtitle: "\(k.moduleId)/\(k.componentId)"))
    case .errorBoundary(let k): return AnyView(FuaranNode(k.child, ctx))
    case .switchKind(let k): return AnyView(RenderSwitch(k: k, ctx: ctx))
    case .fragmentDecl(let k): return AnyView(FuaranNode(k.body, ctx))
    case .fragmentRef(let k): return AnyView(InfoCard(title: "Fragment", subtitle: k.name))
    case .mount(let k):
      return AnyView(InfoCard(title: "Mount", subtitle: k.scopeId + " · " + k.capabilities.joined(separator: ",")))
    }
  }

  /// The defined visible development placeholder for a kind a host deliberately
  /// leaves unimplemented (never a silent skip). Structurally unreachable from
  /// the exhaustive spine — a new kind is a compile error — it exists so hosts
  /// have a loud, coverage-tracked fallback rather than a blank.
  @MainActor
  func fallbackPlaceholder(_ discriminator: String, _ ctx: BindingContext) -> AnyView {
    ctx.coverage?.fallback(discriminator)
    return AnyView(
      Text("⚠ unrendered node kind: \(discriminator)")
        .font(.caption)
        .foregroundStyle(Color.red)
        .padding(6)
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red, lineWidth: 1)))
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  private struct InfoCard: View {
    let title: String
    let subtitle: String
    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        Text(title).font(.system(size: 14, weight: .semibold))
        if !subtitle.isEmpty { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
      }
      .padding(8)
      .background(Color.gray.opacity(0.08))
      .clipShape(RoundedRectangle(cornerRadius: 6))
      .padding(2)
    }
  }

  /// A vertical stack over an array of child nodes (the common container body).
  private struct NodeStack: View {
    let children: [Node]
    let ctx: BindingContext
    var spacing: CGFloat = 2
    var body: some View {
      VStack(alignment: .leading, spacing: spacing) {
        ForEach(children.indices, id: \.self) { i in FuaranNode(children[i], ctx) }
      }
    }
  }

  private struct RenderChildren: View {
    let children: [Node]
    let layout: BoxLayout
    let ctx: BindingContext
    var body: some View {
      switch layout {
      case .flex(let direction, let gap, _):
        let g = CGFloat(gap ?? 4)
        if direction == .horizontal {
          HStack(alignment: .top, spacing: g) {
            ForEach(children.indices, id: \.self) { i in FuaranNode(children[i], ctx) }
          }
        } else {
          VStack(alignment: .leading, spacing: g) {
            ForEach(children.indices, id: \.self) { i in FuaranNode(children[i], ctx) }
          }
        }
      case .grid(let cols, let gap, _):
        let g = CGFloat(gap ?? 4)
        let rows = chunked(children, max(cols, 1))
        VStack(alignment: .leading, spacing: g) {
          ForEach(rows.indices, id: \.self) { r in
            HStack(alignment: .top, spacing: g) {
              ForEach(rows[r].indices, id: \.self) { ci in FuaranNode(rows[r][ci], ctx) }
            }
          }
        }
      case .auto:
        VStack(alignment: .leading) {
          ForEach(children.indices, id: \.self) { i in FuaranNode(children[i], ctx) }
        }
      }
    }
  }

  private func chunked<T>(_ items: [T], _ size: Int) -> [[T]] {
    guard size > 0 else { return [items] }
    var out: [[T]] = []
    var i = 0
    while i < items.count {
      out.append(Array(items[i..<min(i + size, items.count)]))
      i += size
    }
    return out
  }

  // ── Layout ────────────────────────────────────────────────────────────────

  private struct RenderBox: View {
    let k: BoxSpec
    let ctx: BindingContext
    var body: some View {
      switch k.role {
      case .separator:
        Divider().padding(.vertical, 4)
      case .card:
        VStack(alignment: .leading, spacing: 4) { inner }
          .padding(10)
          .background(Color.gray.opacity(0.06))
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .padding(4)
      case .dashboard:
        VStack(alignment: .leading, spacing: 4) { inner }.padding(8)
      case .group:
        VStack(alignment: .leading, spacing: 4) { inner }.padding(2)
      }
    }

    @ViewBuilder private var inner: some View {
      if let heading = k.heading {
        Text(ctx.resolveText(heading)).font(.system(size: 15, weight: .semibold))
      }
      RenderChildren(children: k.children, layout: k.layout, ctx: ctx)
    }
  }

  private struct RenderSplitPanel: View {
    let k: SplitPanelSpec
    let ctx: BindingContext
    var body: some View {
      HStack(alignment: .top, spacing: 4) {
        ForEach(k.children.indices, id: \.self) { i in FuaranNode(k.children[i], ctx).padding(2) }
      }
    }
  }

  private struct RenderTabs: View {
    let k: TabsSpec
    let ctx: BindingContext
    var body: some View {
      let active = min(max(ctx.resolveInt(k.activeIndex, 0), 0), max(k.children.count - 1, 0))
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 4) {
          ForEach(k.children.indices, id: \.self) { i in
            let label = k.tabHeaders.flatMap { $0.indices.contains(i) ? ctx.resolveText($0[i].label) : nil } ?? "Tab \(i + 1)"
            Text(label).font(.system(size: 13, weight: i == active ? .bold : .regular)).padding(4)
          }
        }
        Divider()
        if k.children.indices.contains(active) { FuaranNode(k.children[active], ctx) }
      }
    }
  }

  private struct RenderStepper: View {
    let k: StepperSpec
    let ctx: BindingContext
    var body: some View {
      let active = ctx.resolveInt(k.activeStep, 0)
      VStack(alignment: .leading, spacing: 4) {
        ForEach(k.children.indices, id: \.self) { i in
          HStack(alignment: .center, spacing: 4) {
            Text("\(i + 1). ").font(.system(size: 13, weight: i == active ? .bold : .regular))
            FuaranNode(k.children[i], ctx)
          }
        }
      }
    }
  }

  private struct RenderSummaryList: View {
    let k: SummaryListSpec
    let ctx: BindingContext
    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        if let heading = k.heading {
          Text(ctx.resolveText(heading)).font(.system(size: 15, weight: .semibold))
        }
        NodeStack(children: k.children, ctx: ctx)
      }
    }
  }

  private struct RenderDisclosure: View {
    let k: DisclosureSpec
    let ctx: BindingContext
    var body: some View {
      let open: Bool = {
        if case .staticValue = k.open { return ctx.resolveBool(k.open) }
        return k.defaultOpen
      }()
      VStack(alignment: .leading, spacing: 2) {
        Text((open ? "▼ " : "▶ ") + ctx.resolveText(k.heading)).font(.system(size: 14, weight: .semibold))
        if open { NodeStack(children: k.children, ctx: ctx).padding(.leading, 12) }
      }
    }
  }

  private struct RenderModal: View {
    let k: ModalSpec
    let ctx: BindingContext
    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        if let heading = k.heading {
          Text(ctx.resolveText(heading)).font(.system(size: 15, weight: .bold))
        }
        NodeStack(children: k.children, ctx: ctx)
      }
      .padding(10)
      .background(Color.gray.opacity(0.06))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .padding(4)
    }
  }

  private struct RenderScrollArea: View {
    let k: ScrollAreaSpec
    let ctx: BindingContext
    var body: some View {
      ScrollView { NodeStack(children: k.children, ctx: ctx) }
    }
  }

  private struct RenderSwitch: View {
    let k: SwitchSpec
    let ctx: BindingContext
    var body: some View {
      let current = ctx.resolve(.state(key: k.stateKey, defaultValue: .stringOpt(nil)))
      let chosen = k.cases.first { $0.matchValue == current }?.child ?? k.defaultChild
      FuaranNode(chosen, ctx)
    }
  }

  // ── Display ───────────────────────────────────────────────────────────────

  private struct RenderHeading: View {
    let k: HeadingSpec
    let ctx: BindingContext
    var body: some View {
      let size: CGFloat = {
        switch min(max(k.level, 1), 6) {
        case 1: return 26
        case 2: return 22
        case 3: return 19
        case 4: return 17
        case 5: return 15
        default: return 13
        }
      }()
      Text(ctx.resolveText(k.text)).font(.system(size: size, weight: .bold)).padding(.vertical, 2)
    }
  }

  private struct RenderMetric: View {
    let k: MetricSpec
    let ctx: BindingContext
    var body: some View {
      let accent = toneSwatch(k.tone).accent
      VStack(alignment: .leading, spacing: 1) {
        Text(ctx.resolveText(k.label)).font(.caption).foregroundStyle(.secondary)
        Text(ctx.resolve(k.source)).font(.system(size: 22, weight: .bold)).foregroundStyle(accent)
        if let subtext = k.subtext { Text(ctx.resolveText(subtext)).font(.caption2).foregroundStyle(.secondary) }
        if let trend = k.trend { Text(ctx.resolve(trend)).font(.caption2) }
      }
      .padding(4)
    }
  }

  private struct RenderBadge: View {
    let k: BadgeSpec
    let ctx: BindingContext
    var body: some View {
      let swatch = badgeSwatch(k.variant)
      Text(ctx.resolveText(k.label))
        .font(.caption)
        .foregroundStyle(swatch.onContainer)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(swatch.container)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
  }

  private struct RenderSparkline: View {
    var body: some View {
      RoundedRectangle(cornerRadius: 2).fill(Color(red: 0.69, green: 0.75, blue: 0.77)).frame(width: 80, height: 16)
    }
  }

  private struct RenderCallout: View {
    let k: CalloutSpec
    let ctx: BindingContext
    var body: some View {
      let swatch = toneSwatch(k.tone)
      VStack(alignment: .leading, spacing: 2) {
        if let heading = k.heading {
          Text(ctx.resolveText(heading)).font(.system(size: 14, weight: .bold)).foregroundStyle(swatch.onContainer)
        }
        Text(ctx.resolveText(k.body)).foregroundStyle(swatch.onContainer)
      }
      .padding(10)
      .background(swatch.container)
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  private struct RenderProgress: View {
    let k: ProgressSpec
    let ctx: BindingContext
    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        if let label = k.label { Text(ctx.resolveText(label)).font(.caption) }
        if k.indeterminate {
          ProgressView()
        } else {
          ProgressView(value: min(max(ctx.resolveFloat(k.fraction, 0), 0), 1))
        }
      }
    }
  }

  private struct RenderSkeleton: View {
    let rows: Int
    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(0..<min(max(rows, 0), 20), id: \.self) { _ in
          RoundedRectangle(cornerRadius: 2).fill(Color.gray.opacity(0.15)).frame(height: 12)
        }
      }
    }
  }

  private struct RenderLabelValueRow: View {
    let k: LabelValueRowSpec
    let ctx: BindingContext
    var body: some View {
      HStack {
        Text(ctx.resolveText(k.label)).foregroundStyle(.secondary)
        Spacer()
        Text(ctx.resolve(k.source)).font(.system(size: 13, weight: k.emphasis ? .bold : .regular))
      }
    }
  }

  private struct RenderLink: View {
    let k: LinkSpec
    let ctx: BindingContext
    var body: some View {
      Text(ctx.resolveText(k.label)).foregroundStyle(Color(red: 0.08, green: 0.40, blue: 0.75)).padding(2)
    }
  }

  private struct RenderImage: View {
    let k: ImageSpec
    let ctx: BindingContext
    var body: some View {
      // Render floor has no network image loader — a labelled placeholder box.
      let alt = ctx.resolveText(k.alt)
      Text(alt.isEmpty ? "image" : alt)
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(width: 72, height: 72)
        .background(Color.gray.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.4), lineWidth: 1))
    }
  }

  private struct RenderList: View {
    let k: ListSpec
    let ctx: BindingContext
    var body: some View {
      VStack(alignment: .leading, spacing: 1) {
        ForEach(k.items.indices, id: \.self) { i in
          Text((k.ordered ? "\(i + 1). " : "• ") + ctx.resolveText(k.items[i]))
        }
      }
    }
  }

  private struct RenderToast: View {
    let k: ToastSpec
    let ctx: BindingContext
    var body: some View {
      let swatch = toneSwatch(k.tone)
      Text(ctx.resolveText(k.message))
        .foregroundStyle(swatch.onContainer)
        .padding(8)
        .background(swatch.container)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  private struct RenderCodeBlock: View {
    let code: String
    var body: some View {
      Text(code)
        .font(.system(.caption, design: .monospaced))
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.gray.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 4))
    }
  }

  private struct RenderDrawing: View {
    let k: DrawingSpec
    let ctx: BindingContext
    var body: some View {
      let labels = labelTexts
      VStack(alignment: .leading, spacing: 2) {
        if let title = k.title { Text(ctx.resolveText(title)).font(.system(size: 14, weight: .semibold)) }
        Text("Drawing · \(k.shapes.count) shape(s)").font(.caption).foregroundStyle(.secondary)
        ForEach(labels.indices, id: \.self) { i in Text(labels[i]).font(.caption) }
      }
      .padding(8)
      .background(Color.gray.opacity(0.06))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var labelTexts: [String] {
      k.shapes.compactMap { shape in
        if case .label(_, _, let text, _) = shape { return ctx.resolveText(text) }
        return nil
      }
    }
  }

  // ── Input (render-only — interaction is Phase 541) ────────────────────────

  private struct RenderForm: View {
    let k: FormSpec
    let ctx: BindingContext
    var body: some View {
      VStack(alignment: .leading, spacing: 6) {
        ForEach(k.fields.indices, id: \.self) { i in RenderFormField(field: k.fields[i], ctx: ctx) }
        Button(ctx.resolveText(k.submitLabel)) {}.disabled(ctx.resolveBool(k.disabled))
      }
      .padding(4)
    }
  }

  private struct RenderFormField: View {
    let field: FormField
    let ctx: BindingContext
    var body: some View {
      let label = ctx.resolveText(field.label) + (field.required ? " *" : "")
      switch field.kind {
      case .text(let value, _), .number(let value, _), .choice(_, let value, _), .date(let value, _, _, _, _, _):
        labelled(label) { TextField("", text: .constant(ctx.resolve(value))).disabled(true) }
      case .textArea(_, let value, _):
        labelled(label) { TextField("", text: .constant(ctx.resolve(value)), axis: .vertical).disabled(true) }
      case .checkbox(let value, _):
        Toggle(isOn: .constant(ctx.resolveBool(value))) { Text(label) }.disabled(true)
      case .rangedNumber(let value, let minV, let maxV, _, _):
        let lo = minV ?? 0
        let hi = maxV ?? 100
        VStack(alignment: .leading, spacing: 1) {
          Text("\(label): \(numberString(ctx.resolveFloat(value, lo)))").font(.caption)
          Slider(value: .constant(min(max(ctx.resolveFloat(value, lo), lo), hi)), in: lo...max(hi, lo + 1)).disabled(true)
        }
      case .segmentedChoice(let options, _, let value, _):
        let selected = ctx.resolve(value)
        let opts = ctx.resolve(options).split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let shown = opts.isEmpty ? [selected.isEmpty ? "—" : selected] : opts
        VStack(alignment: .leading, spacing: 2) {
          Text(label).font(.caption).foregroundStyle(.secondary)
          HStack(spacing: 6) {
            ForEach(shown.indices, id: \.self) { i in
              Text(shown[i])
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(shown[i] == selected ? Color.gray.opacity(0.2) : Color.gray.opacity(0.06))
                .clipShape(RoundedRectangle(cornerRadius: 4))
            }
          }
        }
      }
    }

    @ViewBuilder private func labelled(_ label: String, @ViewBuilder _ control: () -> some View) -> some View {
      VStack(alignment: .leading, spacing: 1) {
        Text(label).font(.caption).foregroundStyle(.secondary)
        control()
      }
    }
  }

  private struct RenderButton: View {
    let k: ButtonSpec
    let ctx: BindingContext
    var body: some View {
      Button(ctx.resolveText(k.label)) {}.disabled(ctx.resolveBool(k.disabled))
    }
  }

  private struct RenderSelect: View {
    let k: SelectSpec
    let ctx: BindingContext
    var body: some View {
      let display: String = {
        let v = ctx.resolve(k.value)
        if !v.isEmpty { return v }
        return k.placeholder.map { ctx.resolveText($0) } ?? ""
      }()
      VStack(alignment: .leading, spacing: 1) {
        Text(ctx.resolveText(k.label)).font(.caption).foregroundStyle(.secondary)
        TextField("", text: .constant(display)).disabled(true)
      }
    }
  }

  private struct RenderFilters: View {
    let items: [FilterSpec]
    let ctx: BindingContext
    var body: some View {
      VStack(alignment: .leading, spacing: 4) {
        ForEach(items.indices, id: \.self) { i in
          HStack(spacing: 4) {
            Text(ctx.resolveText(items[i].label) + ": ").font(.caption).foregroundStyle(.secondary)
            Text(items[i].name).font(.caption)
          }
        }
      }
    }
  }

  // ── Visualisation ─────────────────────────────────────────────────────────

  private struct RenderDataGrid: View {
    let k: GridSpec
    let ctx: BindingContext
    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 12) {
          ForEach(k.columns.indices, id: \.self) { i in
            Text(k.columns[i].label).font(.system(size: 12, weight: .semibold))
          }
        }
        Divider()
        if let staticRows = k.staticRows {
          ForEach(staticRows.rows.indices, id: \.self) { r in
            HStack(spacing: 12) {
              ForEach(staticRows.rows[r].indices, id: \.self) { ci in
                Text(ctx.resolveText(staticRows.rows[r][ci])).font(.caption)
              }
            }
          }
        } else {
          Text("(data-bound rows)").font(.caption2).foregroundStyle(.secondary)
        }
      }
      .padding(4)
      .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.gray.opacity(0.3), lineWidth: 1))
    }
  }

  private struct RenderChart: View {
    let k: ChartSpec
    let ctx: BindingContext
    var body: some View {
      VStack(alignment: .leading, spacing: 2) {
        if let title = k.title { Text(ctx.resolveText(title)).font(.system(size: 14, weight: .semibold)) }
        Text("\(k.kind.rawValue) chart · \(k.xField) × \(k.yFields.joined(separator: ","))")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      .padding(8)
      .background(Color.gray.opacity(0.06))
      .clipShape(RoundedRectangle(cornerRadius: 6))
    }
  }

  // ── Coverage-walk child extraction ────────────────────────────────────────

  /// Every embedded `Node` the floor can render, for the coverage walk to
  /// recurse into. An **exhaustive `switch` with no `default`** — a new kind
  /// that carries child nodes is a compile error until it is enumerated here, so
  /// the coverage walk can never silently miss a nested kind.
  public func fuaranCoverageChildren(_ node: Node) -> [Node] {
    switch node.kind {
    case .box(let k): return k.children
    case .splitPanel(let k): return k.children
    case .tabs(let k): return k.children
    case .stepper(let k): return k.children
    case .summaryList(let k): return k.children
    case .disclosure(let k): return k.children
    case .modal(let k): return k.children
    case .scrollArea(let k): return k.children
    case .errorBoundary(let k): return [k.child, k.fallback]
    case .switchKind(let k): return k.cases.map { $0.child } + [k.defaultChild]
    case .fragmentDecl(let k): return [k.body]
    case .fragmentRef(let k): return slotTrees(k.args)
    case .mount(let k): return slotTrees(k.inputs)
    // Leaf / non-child-bearing kinds.
    case .heading, .markdown, .metric, .badge, .sparkline, .callout, .progress, .skeleton,
      .labelValueRow, .link, .image, .list, .toast, .codeBlock, .math, .drawing,
      .form, .filters, .button, .fileUpload, .select, .dataGrid, .chart, .map, .custom:
      return []
    }
  }

  private func slotTrees(_ args: [FragmentArgEntry]) -> [Node] {
    args.compactMap { entry in
      if case .slot(let tree) = entry.arg { return tree }
      return nil
    }
  }

#endif
