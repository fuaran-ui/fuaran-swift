// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Drawing lowering — the load-bearing semantics of the drawing render arm,
// deliberately OUTSIDE the SwiftUI-gated renderer file.
//
// Everything here is pure (no SwiftUI), so it compiles and is TESTED on every
// platform, including the Windows and Linux boxes where the SwiftUI renderer
// compiles to nothing. That placement is the whole point: rotation sign,
// accessible-name composition and style inheritance are exactly the rules two
// surfaces come to disagree about, and a helper living inside
// `#if canImport(SwiftUI)` can only ever be exercised on macOS. This mirrors the
// grid-cell lowering's placement in `BindingContext.swift`.

import Foundation
import FuaranUI

// ── The drawing root's accessible name ───────────────────────────────────────
//
// The wire's drawing root is one announced graphic carrying an accessible NAME
// composed from its two text artefacts: the title names it, the description
// describes it. A description that is only carried as a description is a value
// most assistive technology never announces — which is why the composition
// happens at the wiring rather than being baked into either artefact.
//
// The composition is TITLE FIRST, then the description, joined by a single
// space, with the title terminated by a period unless it already ends in
// sentence punctuation — so the listener hears two sentences rather than one
// run-on. A drawing with no description keeps its title as the name unchanged
// (it is already named by it); a drawing with neither carries no name at all,
// and announcing an empty string would be worse than announcing nothing.

/// Terminate a composed title so the name reads as two sentences. An empty
/// title contributes nothing rather than a bare period.
public func terminateDrawingTitle(_ title: String) -> String {
  guard let last = title.last else { return "" }
  switch last {
  case ".", "!", "?": return title
  default: return title + "."
  }
}

/// The drawing root's accessible name, or `nil` when the drawing carries no
/// text artefact to name it with.
///
/// Takes already-RESOLVED strings: a `TextSource`'s bound / i18n arms resolve
/// only at render time, so composing before resolution would announce a
/// different thing depending on how the drawing was authored.
public func drawingAccessibilityName(title: String?, description: String?) -> String? {
  let descText = description.flatMap { $0.isEmpty ? nil : $0 }
  let titleText = title.flatMap { $0.isEmpty ? nil : $0 }
  switch (titleText, descText) {
  case (let t?, let d?): return terminateDrawingTitle(t) + " " + d
  case (let t?, nil): return t
  case (nil, let d?): return d
  case (nil, nil): return nil
  }
}

// ── Rotation: the sign convention, stated as executable arithmetic ───────────
//
// The wire spells a label rotation as DEGREES CLOCKWISE about the label's own
// anchor point — the `rotate(θ x y)` form, whose matrix in a Y-DOWN coordinate
// space is
//
//     ⎡ cos θ  −sin θ ⎤
//     ⎣ sin θ   cos θ ⎦
//
// applied to the offset from the pivot. In a y-down space that matrix turns a
// point CLOCKWISE for a positive θ, so a NEGATIVE θ turns it anti-clockwise.
//
// This function is the sign convention written down as arithmetic rather than
// as a comment, so a test can check it against a real corpus fixture instead of
// a reader checking it against their intuition — which is the failure mode a
// rotation sign has: it is 50% likely to look plausible either way, and the two
// surfaces only disagree once someone renders a chart.
//
// SwiftUI's `rotationEffect` uses the SAME convention — its coordinate space is
// y-down and a positive `Angle` turns the rendered output clockwise — so the
// degrees pass through the render arm UNCONVERTED. That claim is not left as
// prose: `DrawingRenderTests` rasterises a rotated marker on the macOS rig and
// asserts the drawn pixel lands where THIS function predicts.
public func svgRotate(
  x: Double, y: Double, aboutX: Double, aboutY: Double, degrees: Double
) -> (x: Double, y: Double) {
  let radians = degrees * Double.pi / 180
  let c = cos(radians)
  let s = sin(radians)
  let dx = x - aboutX
  let dy = y - aboutY
  return (aboutX + dx * c - dy * s, aboutY + dx * s + dy * c)
}

/// Where a label's glyph run starts, as a fraction of its own width measured
/// from the anchor point: `Start` runs right from the anchor, `End` ends at it,
/// `Middle` straddles it. An absent anchor is `Start` — the wire's own default.
public func drawingAnchorFraction(_ anchor: TextAnchor?) -> Double {
  switch anchor {
  case .none, .some(.start): return 0
  case .some(.middle): return 0.5
  case .some(.end): return 1
  }
}

// ── Style inheritance ────────────────────────────────────────────────────────

/// Resolve a shape's effective style against the style it nests inside (the
/// drawing root's, or an enclosing group's): a field the shape omits is
/// inherited, a field it declares wins.
///
/// Three fields are deliberately NOT inherited, and the exclusion is the part
/// worth testing. `tip` names ONE mark — propagating a group's readout to every
/// child would make a single hover claim apply to marks it was never about.
/// `markId` is an identity, so inheriting it would mint duplicates of a key
/// whose entire purpose is to be unique. And `rotation` is a geometric
/// transform rather than a presentation attribute: inherited, it would silently
/// turn every nested label a group happens to contain.
public func inheritedDrawStyle(parent: DrawStyle, child: DrawStyle) -> DrawStyle {
  DrawStyle(
    fill: child.fill ?? parent.fill,
    stroke: child.stroke ?? parent.stroke,
    strokeWidth: child.strokeWidth ?? parent.strokeWidth,
    opacity: child.opacity ?? parent.opacity,
    textAnchor: child.textAnchor ?? parent.textAnchor,
    fontSize: child.fontSize ?? parent.fontSize,
    emphasis: child.emphasis ?? parent.emphasis,
    fontFamily: child.fontFamily ?? parent.fontFamily,
    markId: child.markId,
    rotation: child.rotation,
    tip: child.tip)
}

// ── The tip census ───────────────────────────────────────────────────────────

/// One tipped mark: the shape's discriminator, its position in the drawing's
/// own tree order, and the tip `TextSource` as authored.
public struct TippedMark: Equatable, Sendable {
  public let shape: String
  public let path: String
  public let tip: TextSource

  public init(shape: String, path: String, tip: TextSource) {
    self.shape = shape
    self.path = path
    self.tip = tip
  }
}

/// Every tipped mark in a drawing, in tree order — the render arm's worklist and
/// the census a test asserts against.
///
/// A tip is the one style field that applies to EVERY shape rather than only to
/// a label, so this walks the whole shape tree including group children (whose
/// own tips are their own, per `inheritedDrawStyle`). An explicitly EMPTY tip is
/// enumerated: it is a present value on the wire and a distinct shape from an
/// absent one, so dropping it here would quietly erase the distinction the
/// format keeps.
public func tippedMarks(_ spec: DrawingSpec) -> [TippedMark] {
  var out: [TippedMark] = []
  func walk(_ shapes: [FuaranUI.Shape], _ prefix: String) {
    for (i, shape) in shapes.enumerated() {
      let path = "\(prefix)[\(i)]"
      let style = drawShapeStyle(shape)
      if let tip = style.tip {
        out.append(TippedMark(shape: drawShapeName(shape), path: path, tip: tip))
      }
      if case .group(let children, _) = shape { walk(children, path + ".children") }
    }
  }
  walk(spec.shapes, "shapes")
  return out
}

/// A shape's own style. Exhaustive over the sealed shape DU — a new shape case
/// is a build error here rather than a silently untipped mark.
public func drawShapeStyle(_ shape: FuaranUI.Shape) -> DrawStyle {
  switch shape {
  case .group(_, let style): return style
  case .rectangle(_, _, _, _, _, let style): return style
  case .line(_, _, _, _, let style): return style
  case .polyline(_, let style): return style
  case .polygon(_, let style): return style
  case .curve(_, let style): return style
  case .circle(_, _, _, let style): return style
  case .ellipse(_, _, _, _, let style): return style
  case .label(_, _, _, let style): return style
  }
}

/// A shape's wire discriminator. Exhaustive for the same reason.
public func drawShapeName(_ shape: FuaranUI.Shape) -> String {
  switch shape {
  case .group: return "Group"
  case .rectangle: return "Rectangle"
  case .line: return "Line"
  case .polyline: return "Polyline"
  case .polygon: return "Polygon"
  case .curve: return "Curve"
  case .circle: return "Circle"
  case .ellipse: return "Ellipse"
  case .label: return "Label"
  }
}

// ── User space → view space ──────────────────────────────────────────────────

/// The uniform, aspect-preserving map from the drawing's own coordinate box
/// into the view's rectangle — the `viewBox` contract: fit the whole box,
/// centre the slack, scale text with the geometry so a label keeps its
/// proportion to the marks it labels.
public struct DrawingTransform: Equatable, Sendable {
  public let scale: Double
  public let offsetX: Double
  public let offsetY: Double
  public let minX: Double
  public let minY: Double

  public init(viewBox: ViewBox, width: Double, height: Double) {
    let boxW = viewBox.width > 0 ? viewBox.width : 1
    let boxH = viewBox.height > 0 ? viewBox.height : 1
    let s = min(width / boxW, height / boxH)
    self.scale = s.isFinite && s > 0 ? s : 1
    self.offsetX = (width - boxW * self.scale) / 2
    self.offsetY = (height - boxH * self.scale) / 2
    self.minX = viewBox.minX
    self.minY = viewBox.minY
  }

  public func pointX(_ x: Double) -> Double { (x - minX) * scale + offsetX }
  public func pointY(_ y: Double) -> Double { (y - minY) * scale + offsetY }
  public func length(_ l: Double) -> Double { l * scale }
}

// ── Colour ───────────────────────────────────────────────────────────────────

/// Parse a drawing colour to its RGB components in 0…1, or `nil` for a value
/// that names no literal colour — `currentColor`, a design token, an unknown
/// spelling. `nil` means "take the surface's own foreground", which is what
/// `currentColor` asks for and the honest answer for the rest: inventing a
/// colour for a token this surface does not hold would be a claim about the
/// theme rather than a rendering of it.
public func parseDrawColour(_ value: String) -> (red: Double, green: Double, blue: Double)? {
  let text = value.trimmingCharacters(in: .whitespaces)
  guard text.hasPrefix("#") else { return nil }
  let hex = String(text.dropFirst())
  let digits: [Character] = Array(hex)
  func nibble(_ c: Character) -> Int? { c.hexDigitValue }
  switch digits.count {
  case 3:
    guard let r = nibble(digits[0]), let g = nibble(digits[1]), let b = nibble(digits[2])
    else { return nil }
    return (Double(r * 17) / 255, Double(g * 17) / 255, Double(b * 17) / 255)
  case 6:
    var comps: [Double] = []
    for i in stride(from: 0, to: 6, by: 2) {
      guard let hi = nibble(digits[i]), let lo = nibble(digits[i + 1]) else { return nil }
      comps.append(Double(hi * 16 + lo) / 255)
    }
    return (comps[0], comps[1], comps[2])
  default:
    return nil
  }
}
