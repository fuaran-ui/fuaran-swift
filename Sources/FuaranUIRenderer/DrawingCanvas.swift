// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Drawing render arm — the wire's bounded vector-graphics primitive
// projected as SwiftUI. Every chart lowers to a `Drawing`, so this is the arm a
// chart is actually SEEN through, and the three things it has to get right are
// the three the surrounding vocabulary spent phases pinning down: a label turns
// about its own anchor point, a mark carries a reachable readout, and the whole
// graphic announces itself as one named picture.
//
// The load-bearing rules — rotation sign, the accessible-name composition,
// style inheritance, the user-space→view-space map — are NOT here. They live in
// the pure `DrawingLowering.swift`, which compiles and is tested on every
// platform; this file is the SwiftUI wiring over them, and it is the part only
// the macOS rig can compile at all.
//
// Structure: one SwiftUI view per mark inside a ZStack, rather than one
// `Canvas` for the whole drawing. A `Canvas` draws faster and cannot carry a
// per-mark affordance — no tooltip, no accessibility identity, nothing a
// pointer or an assistive technology can address. The tip arm needs marks to be
// views, so marks are views.

#if canImport(SwiftUI)

  import Foundation
  import FuaranUI
  import SwiftUI

  /// A decoded `DrawingSpec` rendered as SwiftUI, in its own coordinate box.
  ///
  /// The view fits the whole `viewBox` at its natural aspect ratio and centres
  /// the slack — the `viewBox` contract, which is what keeps a chart's geometry
  /// (bars against their axis, a label against its tick) intact at any size.
  public struct FuaranDrawing: View {
    let spec: DrawingSpec
    let ctx: BindingContext

    public init(_ spec: DrawingSpec, _ ctx: BindingContext = .empty) {
      self.spec = spec
      self.ctx = ctx
    }

    private var aspect: CGFloat {
      let w = spec.viewBox.width > 0 ? spec.viewBox.width : 1
      let h = spec.viewBox.height > 0 ? spec.viewBox.height : 1
      return CGFloat(w / h)
    }

    public var body: some View {
      GeometryReader { geo in
        let t = DrawingTransform(
          viewBox: spec.viewBox, width: Double(geo.size.width), height: Double(geo.size.height))
        ZStack(alignment: .topLeading) {
          ForEach(Array(spec.shapes.indices), id: \.self) { i in
            fuaranDrawShapeView(spec.shapes[i], inherited: spec.style, t: t, ctx: ctx)
          }
        }
        .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
      }
      .aspectRatio(aspect, contentMode: .fit)
    }
  }

  // ── One mark, one view ──────────────────────────────────────────────────────

  /// Project one shape (and, for a group, its children) as SwiftUI. Exhaustive
  /// over the sealed shape DU with no `default` — a new wire shape is a build
  /// error here rather than a mark that silently renders as nothing.
  @MainActor
  func fuaranDrawShapeView(
    _ shape: FuaranUI.Shape, inherited: DrawStyle, t: DrawingTransform, ctx: BindingContext
  ) -> AnyView {
    let style = inheritedDrawStyle(parent: inherited, child: drawShapeStyle(shape))
    let content: AnyView

    switch shape {
    case .group(let children, _):
      content = AnyView(
        ZStack(alignment: .topLeading) {
          ForEach(Array(children.indices), id: \.self) { i in
            fuaranDrawShapeView(children[i], inherited: style, t: t, ctx: ctx)
          }
        })

    case .rectangle(let x, let y, let w, let h, let corner, _):
      let rect = CGRect(
        x: t.pointX(x), y: t.pointY(y), width: t.length(w), height: t.length(h))
      let path =
        (corner ?? 0) > 0
        ? Path(roundedRect: rect, cornerRadius: CGFloat(t.length(corner ?? 0)))
        : Path(rect)
      content = fuaranPaintedPath(path, style: style, t: t, ctx: ctx, closed: true)

    case .line(let x1, let y1, let x2, let y2, _):
      var path = Path()
      path.move(to: CGPoint(x: t.pointX(x1), y: t.pointY(y1)))
      path.addLine(to: CGPoint(x: t.pointX(x2), y: t.pointY(y2)))
      content = fuaranPaintedPath(path, style: style, t: t, ctx: ctx, closed: false)

    case .polyline(let points, _):
      content = fuaranPaintedPath(
        fuaranPolyPath(points, t: t, close: false), style: style, t: t, ctx: ctx, closed: false)

    case .polygon(let points, _):
      content = fuaranPaintedPath(
        fuaranPolyPath(points, t: t, close: true), style: style, t: t, ctx: ctx, closed: true)

    case .curve(let commands, _):
      content = fuaranPaintedPath(
        fuaranCurvePath(commands, t: t), style: style, t: t, ctx: ctx, closed: true)

    case .circle(let cx, let cy, let r, _):
      let d = t.length(r) * 2
      let rect = CGRect(
        x: t.pointX(cx) - t.length(r), y: t.pointY(cy) - t.length(r), width: d, height: d)
      content = fuaranPaintedPath(
        Path(ellipseIn: rect), style: style, t: t, ctx: ctx, closed: true)

    case .ellipse(let cx, let cy, let rx, let ry, _):
      let rect = CGRect(
        x: t.pointX(cx) - t.length(rx), y: t.pointY(cy) - t.length(ry),
        width: t.length(rx) * 2, height: t.length(ry) * 2)
      content = fuaranPaintedPath(
        Path(ellipseIn: rect), style: style, t: t, ctx: ctx, closed: true)

    case .label(let x, let y, let text, _):
      content = fuaranDrawLabelView(
        x: x, y: y, text: ctx.resolveText(text), style: style, t: t, ctx: ctx)
    }

    return fuaranTipped(content, style: style, ctx: ctx)
  }

  // ── The rotation arm ────────────────────────────────────────────────────────
  //
  // A label is laid out against its anchor POINT and then turned about that same
  // point — which is what makes rotation compose with the anchor rather than
  // fight it: a `Middle`-anchored tilted category label stays centred under its
  // band, and an `End`-anchored one still ends at the tick it names.
  //
  // The construction: a ZERO-SIZE view positioned at the anchor point, with the
  // glyph run hung off it by an alignment that encodes the text anchor, then
  // `rotationEffect` about that zero-size view's own centre — which IS the
  // anchor point, so the pivot is exact rather than approximated by a bounding
  // box. Rotating a laid-out text box about `.center` would pivot about the
  // middle of the run instead, and a long category label would swing away from
  // its tick.
  //
  // The degrees pass through UNCONVERTED. SwiftUI's rotation and the wire's
  // share a convention — a y-down space where a positive angle turns clockwise —
  // so a negative tilt falls away from the axis on both. That is asserted on the
  // macOS rig against the pure `svgRotate`, not assumed here.
  //
  // The one deliberate approximation: the wire's y is a text BASELINE, and the
  // vertical alignment used is `.lastTextBaseline`, which is SwiftUI's own
  // baseline rather than a fraction of the line box — so the residual is the
  // difference between two typographic baselines, not a guess at a descender.
  @MainActor
  func fuaranDrawLabelView(
    x: Double, y: Double, text: String, style: DrawStyle, t: DrawingTransform,
    ctx: BindingContext
  ) -> AnyView {
    let size = t.length(style.fontSize ?? 12)
    let colour = fuaranDrawColour(style.fill, ctx) ?? Color.primary
    let opacity = style.opacity.map { ctx.resolveFloat($0, 1) } ?? 1

    let horizontal: HorizontalAlignment
    switch style.textAnchor {
    case .none, .some(.start): horizontal = .leading
    case .some(.middle): horizontal = .center
    case .some(.end): horizontal = .trailing
    }

    let weight: Font.Weight
    switch style.emphasis {
    case .some(.loud): weight = .semibold
    case .some(.quiet): weight = .light
    case .none, .some(.normal): weight = .regular
    }

    return AnyView(
      Color.clear
        .frame(width: 0, height: 0)
        .overlay(alignment: Alignment(horizontal: horizontal, vertical: .lastTextBaseline)) {
          Text(text)
            .font(.system(size: CGFloat(max(size, 1)), weight: weight))
            .foregroundStyle(colour)
            .fixedSize()
        }
        .rotationEffect(.degrees(style.rotation ?? 0), anchor: .center)
        .opacity(opacity)
        .position(x: CGFloat(t.pointX(x)), y: CGFloat(t.pointY(y))))
  }

  // ── The tip arm ─────────────────────────────────────────────────────────────
  //
  // THE IDIOM, AND WHAT "REACHABLE" MEANS ON EACH PLATFORM. The wire's tip is a
  // mark-level readout that the web host emits as the mark's own `<title>` — at
  // once the native pointer tooltip and the element's accessible name. The
  // SwiftUI counterpart of exactly that affordance is `.help(_:)`: on macOS it
  // IS the pointer tooltip, and on the touch platforms it maps to the element's
  // accessibility hint.
  //
  // So: on macOS a tip is reachable by hovering the mark, which is the same
  // gesture and the same string the web surface answers to. On iOS there is no
  // pointer, and the drawing root is a single accessibility element (see the
  // root-summary arm), so a tip is NOT independently reachable there. That is
  // the faithful mirror rather than a shortfall — a hover-only `<title>` is
  // equally unreachable on a phone browser, and the alternative (exposing every
  // mark as its own accessibility element) is precisely the wall-of-noise
  // option the root-summary decision declined.
  //
  // HOSTILE TEXT IS INHERITED, NOT RE-AUDITED. The web emitter must XML-escape a
  // tip because it writes raw markup; SwiftUI `Text` is not markup, so a tip
  // carrying `<script>alert("xss") & 'done'</script>` — the corpus fixture's
  // deliberate case — is displayed as those literal characters. There is no
  // escaping seam here to get wrong.
  //
  // An explicitly EMPTY tip is a present value on the wire and is preserved as
  // such by the decoder, but it names nothing, so no readout is attached — a
  // tooltip showing an empty box would be worse than none.
  @MainActor
  func fuaranTipped(_ content: AnyView, style: DrawStyle, ctx: BindingContext) -> AnyView {
    guard let tip = style.tip else { return content }
    let text = ctx.resolveText(tip)
    guard !text.isEmpty else { return content }
    return AnyView(content.help(text))
  }

  // ── Paint ───────────────────────────────────────────────────────────────────

  /// Fill and/or stroke a path from the resolved style.
  ///
  /// A shape declaring NEITHER fill nor stroke is treated the way the vector
  /// format treats it: closed shapes take the surface foreground as their fill,
  /// while an open run (a line, a polyline) is not filled at all — filling one
  /// would paint the phantom region between its ends, which is never what an
  /// axis rule or a sparkline meant.
  @MainActor
  func fuaranPaintedPath(
    _ path: Path, style: DrawStyle, t: DrawingTransform, ctx: BindingContext, closed: Bool
  ) -> AnyView {
    let fill = fuaranDrawColour(style.fill, ctx)
    let stroke = fuaranDrawColour(style.stroke, ctx)
    let width = t.length(style.strokeWidth.map { ctx.resolveFloat($0, 1) } ?? 1)
    let opacity = style.opacity.map { ctx.resolveFloat($0, 1) } ?? 1
    let effectiveFill: Color? = fill ?? ((stroke == nil && closed) ? Color.primary : nil)

    return AnyView(
      ZStack {
        if let effectiveFill { path.fill(effectiveFill) }
        if let stroke {
          path.stroke(
            stroke,
            style: StrokeStyle(
              lineWidth: CGFloat(max(width, 0)), lineCap: .round, lineJoin: .round))
        }
      }
      .opacity(opacity))
  }

  /// Resolve a colour binding. `nil` means "no colour declared"; a value that
  /// names no literal colour (`currentColor`, a design token) takes the
  /// surface's own foreground rather than an invented hex.
  @MainActor
  func fuaranDrawColour(_ binding: FuaranUI.Binding?, _ ctx: BindingContext) -> Color? {
    guard let binding else { return nil }
    let raw = ctx.resolve(binding)
    if raw.isEmpty { return nil }
    if let rgb = parseDrawColour(raw) {
      return Color(red: rgb.red, green: rgb.green, blue: rgb.blue)
    }
    return Color.primary
  }

  // ── Path builders ───────────────────────────────────────────────────────────

  func fuaranPolyPath(_ points: [DrawPoint], t: DrawingTransform, close: Bool) -> Path {
    var path = Path()
    for (i, p) in points.enumerated() {
      let cg = CGPoint(x: t.pointX(p.x), y: t.pointY(p.y))
      if i == 0 { path.move(to: cg) } else { path.addLine(to: cg) }
    }
    if close, !points.isEmpty { path.closeSubpath() }
    return path
  }

  /// Build a path from the typed command list. Exhaustive over the sealed
  /// command DU — the format carries no raw path string to fall back on, which
  /// is the whole point of the typed surface.
  func fuaranCurvePath(_ commands: [CurveCommand], t: DrawingTransform) -> Path {
    var path = Path()
    func cg(_ p: DrawPoint) -> CGPoint { CGPoint(x: t.pointX(p.x), y: t.pointY(p.y)) }
    for command in commands {
      switch command {
      case .moveTo(let p): path.move(to: cg(p))
      case .lineTo(let p): path.addLine(to: cg(p))
      case .cubicTo(let c1, let c2, let to):
        path.addCurve(to: cg(to), control1: cg(c1), control2: cg(c2))
      case .quadraticTo(let c, let to): path.addQuadCurve(to: cg(to), control: cg(c))
      case .close: path.closeSubpath()
      }
    }
    return path
  }

#endif
