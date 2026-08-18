// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Drawing lowering, tested on EVERY platform.
//
// The renderer itself is behind `#if canImport(SwiftUI)` and only the macOS rig
// compiles it, which makes it a poor home for rules that have to be RIGHT
// rather than merely present. The three this file exists for:
//
//   • the ROTATION SIGN, checked against a real corpus chart whose axis
//     geometry decides which direction "away" is — not against intuition, and
//     not against a restatement of the same arithmetic the renderer uses;
//   • the ACCESSIBLE NAME, asserted byte-for-byte against the exact string a
//     browser's accessibility tree was observed to expose for the same fixture;
//   • the TIP CENSUS, including the two cases a walk quietly gets wrong — a
//     group child's tip, and an explicitly empty one.
//
// Skips cleanly when the corpus is absent (standalone checkout).

import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class DrawingLoweringTests: XCTestCase {

  // ── Corpus access ──────────────────────────────────────────────────────────

  static func corpusDir() -> URL? {
    let here = URL(fileURLWithPath: #filePath)
    let repoRoot =
      here
      .deletingLastPathComponent()  // FuaranUIRendererTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // fuaran-swift
    let corpus = repoRoot.deletingLastPathComponent().appendingPathComponent("wire-format-fixtures")
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: corpus.path, isDirectory: &isDir)
    return exists && isDir.boolValue ? corpus : nil
  }

  func drawing(_ relativePath: String) throws -> DrawingSpec {
    guard let corpus = Self.corpusDir() else {
      throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
    }
    let url = corpus.appendingPathComponent(relativePath)
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw XCTSkip("corpus fixture \(relativePath) not present in this corpus revision.")
    }
    let node = try RenderProjection.decodeNode(try String(contentsOf: url, encoding: .utf8))
    guard case .drawing(let spec) = node.kind else {
      XCTFail("\(relativePath) is not a Drawing fixture")
      throw XCTSkip("not a drawing")
    }
    return spec
  }

  // ── The rotation sign ──────────────────────────────────────────────────────

  /// THE SIGN CHECK, and the whole reason it is done this way.
  ///
  /// A rotation sign is the kind of defect that looks plausible either way: flip
  /// it and the labels are still tilted, still legible in isolation, and wrong
  /// only in relation to the axis they hang off. So the check is made against a
  /// real lowered chart, whose numbers decide which direction "away from the
  /// axis" is, rather than against a hand-built case that could be built to
  /// agree with whichever convention was implemented. The flipped sign is shown
  /// to be a COLLISION rather than merely a different look.
  ///
  /// The fixture: a bar chart whose x-axis rule sits at y = 274.9 with the plot
  /// ABOVE it, and whose category labels are anchored 20 units BELOW at
  /// y = 294.9, `End`-anchored (the run ENDS at the tick) and tilted −30°.
  ///
  /// The property: the glyph run must fall AWAY from the axis. At +30° the same
  /// run rises back through the 20-unit gap and lands on the axis rule itself —
  /// so the wrong sign is a collision with the chrome, not a different look.
  func testNegativeTiltFallsAwayFromTheAxisAndTheFlippedSignCollidesWithIt() throws {
    let spec = try drawing("chart-lowering/bar-tilt-boundary.expected.json")

    // The x-axis rule: the lowest horizontal line in the drawing.
    var axisY: Double = -.infinity
    for shape in spec.shapes {
      if case .line(_, let y1, _, let y2, _) = shape, y1 == y2 { axisY = max(axisY, y1) }
    }
    XCTAssertEqual(axisY, 274.9, "the fixture's x-axis rule moved; re-read the geometry")

    // A tilted category label — anchored below the axis, ending at its tick.
    var tilted: (x: Double, y: Double, style: DrawStyle)? = nil
    for shape in spec.shapes {
      if case .label(let x, let y, _, let style) = shape, let r = style.rotation, r != -90 {
        tilted = (x, y, style)
        break
      }
    }
    guard let label = tilted else {
      return XCTFail("no tilted category label in the fixture")
    }
    XCTAssertEqual(label.style.rotation, -30, "the fixture's tilt is the lowering's own default")
    XCTAssertEqual(label.style.textAnchor, .end)
    XCTAssertGreaterThan(label.y, axisY, "the label is anchored below the axis rule")

    // An `End`-anchored run extends LEFT from its anchor. Take a point 40 user
    // units along it — the far end of a category label of that width.
    let runLength = 40.0
    let tailX = label.x - runLength
    let tailY = label.y

    let authored = svgRotate(
      x: tailX, y: tailY, aboutX: label.x, aboutY: label.y, degrees: label.style.rotation!)
    let flipped = svgRotate(
      x: tailX, y: tailY, aboutX: label.x, aboutY: label.y, degrees: -label.style.rotation!)

    // Authored: the run falls further from the axis (greater y is further down,
    // the plot being above) and stays clear of it.
    XCTAssertGreaterThan(authored.y, label.y, "the authored tilt must carry the run DOWNWARD")
    XCTAssertGreaterThan(authored.y, axisY + 20, "and therefore clear of the axis rule")
    XCTAssertLessThan(authored.x, label.x, "an End-anchored run extends left of its anchor")
    XCTAssertEqual(authored.y, label.y + runLength * 0.5, accuracy: 1e-9)

    // Flipped: the run rises back through the 20-unit gap and reaches the rule.
    XCTAssertLessThan(flipped.y, label.y, "the flipped sign carries the run UPWARD")
    XCTAssertLessThanOrEqual(flipped.y, axisY, "…onto the axis rule it is meant to hang below")
  }

  /// The rotation itself, against the closed form, in the y-down space the wire
  /// and the renderer share: a positive angle turns clockwise.
  func testPositiveDegreesTurnClockwiseInAYDownSpace() {
    // A point one unit to the RIGHT of the pivot.
    let quarter = svgRotate(x: 1, y: 0, aboutX: 0, aboutY: 0, degrees: 90)
    XCTAssertEqual(quarter.x, 0, accuracy: 1e-12)
    XCTAssertEqual(quarter.y, 1, accuracy: 1e-12)  // y-down ⇒ clockwise is DOWN

    let back = svgRotate(x: 1, y: 0, aboutX: 0, aboutY: 0, degrees: -90)
    XCTAssertEqual(back.x, 0, accuracy: 1e-12)
    XCTAssertEqual(back.y, -1, accuracy: 1e-12)

    // The pivot is invariant — the property the render arm's zero-size anchor
    // construction exists to preserve.
    let pivot = svgRotate(x: 12, y: 34, aboutX: 12, aboutY: 34, degrees: 137)
    XCTAssertEqual(pivot.x, 12, accuracy: 1e-12)
    XCTAssertEqual(pivot.y, 34, accuracy: 1e-12)
  }

  /// The rotated-label fixture's whole point: an EXPLICIT zero is a present
  /// value and a distinct wire shape from an absent one, and fractional tilts
  /// are taken as authored — no host re-rounds on decode.
  func testRotationIsDecodedAsAuthoredIncludingExplicitZero() throws {
    let spec = try drawing("nodes/drawing-rotated-labels.json")
    var byText: [String: Double?] = [:]
    for shape in spec.shapes {
      if case .label(_, _, let text, let style) = shape, case .literal(let s) = text {
        byText[s] = style.rotation
      }
    }
    XCTAssertEqual(byText["Q1 2026"], .some(-30))
    XCTAssertEqual(byText["Q2 2026"], .some(-90))
    XCTAssertEqual(byText["Revenue"], .some(90))
    XCTAssertEqual(byText["Fractional"], .some(12.34))
    XCTAssertEqual(byText["Hairline"], .some(-0.5))
    XCTAssertEqual(byText["Explicit zero"], .some(0), "an explicit 0 is a PRESENT rotation")
    XCTAssertEqual(byText["Upright"], .some(nil), "…and an omitted one stays absent")
  }

  // ── The root summary ───────────────────────────────────────────────────────

  /// The announced string, byte-for-byte.
  ///
  /// The oracle is not this test's own arithmetic: it is the exact name a
  /// browser's accessibility tree was observed to expose for this same fixture
  /// on the web surface. If the Swift composition ever drifts from it, the two
  /// surfaces are announcing different charts.
  func testTheComposedNameMatchesTheAnnouncedStringOnTheWebSurface() throws {
    let spec = try drawing("chart-lowering/bar-axis-titles.expected.json")
    let ctx = BindingContext.empty
    let name = drawingAccessibilityName(
      title: spec.title.map(ctx.resolveText), description: spec.description.map(ctx.resolveText))
    XCTAssertEqual(
      name,
      "Sales vs target. Bar chart. 2 series: sales, target. 3 categories: North to East. "
        + "Peak sales at South, 130.")
  }

  func testTheTitleIsTerminatedOnlyWhenItDoesNotAlreadyEndASentence() {
    XCTAssertEqual(terminateDrawingTitle("Sales vs target"), "Sales vs target.")
    XCTAssertEqual(terminateDrawingTitle("Done."), "Done.")
    XCTAssertEqual(terminateDrawingTitle("Really!"), "Really!")
    XCTAssertEqual(terminateDrawingTitle("Which?"), "Which?")
    // An empty title contributes nothing — never a bare period.
    XCTAssertEqual(terminateDrawingTitle(""), "")
  }

  func testANameFallsBackToWhicheverArtefactExists() {
    XCTAssertEqual(
      drawingAccessibilityName(title: "Rotated axis labels", description: nil),
      "Rotated axis labels")
    XCTAssertEqual(drawingAccessibilityName(title: nil, description: "Bar chart."), "Bar chart.")
    XCTAssertEqual(drawingAccessibilityName(title: "", description: "Bar chart."), "Bar chart.")
    // Nothing to say ⇒ no name at all. An empty accessible name is worse than
    // none: it announces an unlabelled graphic rather than staying silent.
    XCTAssertNil(drawingAccessibilityName(title: nil, description: nil))
    XCTAssertNil(drawingAccessibilityName(title: "", description: ""))
  }

  /// A title-only drawing keeps its title as the name, unterminated — it is
  /// already named by it, and the termination exists only to separate two
  /// sentences that are about to be joined.
  func testATitleOnlyDrawingIsNamedByItsTitleVerbatim() throws {
    let spec = try drawing("nodes/drawing-rotated-labels.json")
    XCTAssertNil(spec.description)
    let ctx = BindingContext.empty
    XCTAssertEqual(
      drawingAccessibilityName(
        title: spec.title.map(ctx.resolveText), description: spec.description.map(ctx.resolveText)),
      "Rotated axis labels")
  }

  // ── The tip census ─────────────────────────────────────────────────────────

  func testEveryTippedMarkIsEnumeratedIncludingAGroupChildAndAnEmptyTip() throws {
    let spec = try drawing("nodes/drawing-tipped-shapes.json")
    let marks = tippedMarks(spec)

    // Seven of the fixture's eight shapes carry a tip; the bare `Line` does not.
    XCTAssertEqual(
      marks.map(\.shape),
      ["Rectangle", "Circle", "Curve", "Polyline", "Group", "Label", "Ellipse"])
    XCTAssertEqual(spec.shapes.count, 8, "the untipped Line completes the fixture")

    let ctx = BindingContext.empty
    let texts = marks.map { ctx.resolveText($0.tip) }
    XCTAssertEqual(texts[0], "revenue · Q1 2026 · 1,234,567.89")
    XCTAssertEqual(texts[3], "revenue")

    // An explicitly EMPTY tip is a present value on the wire and stays one here.
    // Erasing it at the lowering would collapse the distinction the format keeps.
    XCTAssertEqual(texts[6], "")
    XCTAssertEqual(marks[6].shape, "Ellipse")
  }

  /// Hostile tip text rides through verbatim. SwiftUI `Text` is not markup, so
  /// the escaping the web emitter owes has no counterpart to get wrong here —
  /// the safety is inherited from the display primitive, not re-implemented.
  func testHostileTipTextIsCarriedVerbatim() throws {
    let spec = try drawing("nodes/drawing-tipped-shapes.json")
    let ctx = BindingContext.empty
    let label = tippedMarks(spec).first { $0.shape == "Label" }
    XCTAssertEqual(
      label.map { ctx.resolveText($0.tip) }, "<script>alert(\"xss\") & 'done'</script>")
  }

  // ── Style inheritance ──────────────────────────────────────────────────────

  func testPresentationFieldsInheritButTransformAndIdentityDoNot() {
    let parent = DrawStyle(
      fill: .staticValue(.stringOpt("#112233")), stroke: .staticValue(.stringOpt("#445566")),
      strokeWidth: .staticValue(.stringOpt("3")), opacity: .staticValue(.stringOpt("0.5")),
      textAnchor: .middle, fontSize: 20, emphasis: .loud, fontFamily: "serif",
      markId: "parent-mark", rotation: -45, tip: .literal("the group"))
    let child = DrawStyle.empty

    let merged = inheritedDrawStyle(parent: parent, child: child)

    // Presentation: inherited, exactly as the vector format's own cascade does.
    XCTAssertEqual(merged.textAnchor, .middle)
    XCTAssertEqual(merged.fontSize, 20)
    XCTAssertEqual(merged.emphasis, .loud)
    XCTAssertEqual(merged.fontFamily, "serif")
    XCTAssertNotNil(merged.fill)
    XCTAssertNotNil(merged.stroke)

    // NOT inherited, and each for its own reason: a readout names ONE mark, an
    // identity must stay unique, and a transform would silently turn every
    // nested label the group happens to contain.
    XCTAssertNil(merged.tip)
    XCTAssertNil(merged.markId)
    XCTAssertNil(merged.rotation)
  }

  func testAChildsOwnDeclarationWins() {
    let parent = DrawStyle(
      fill: nil, stroke: nil, strokeWidth: nil, opacity: nil, textAnchor: .middle, fontSize: 20,
      emphasis: nil, fontFamily: nil, markId: nil, rotation: nil, tip: nil)
    var child = DrawStyle.empty
    child.textAnchor = .end
    child.rotation = -30
    let merged = inheritedDrawStyle(parent: parent, child: child)
    XCTAssertEqual(merged.textAnchor, .end)
    XCTAssertEqual(merged.fontSize, 20)
    XCTAssertEqual(merged.rotation, -30)
  }

  /// The corpus's own group case: the group carries the tip, its child does not
  /// acquire one.
  func testAGroupsTipDoesNotDescendToItsChild() throws {
    let spec = try drawing("nodes/drawing-tipped-shapes.json")
    guard
      let group = spec.shapes.first(where: {
        if case .group = $0 { return true } else { return false }
      }),
      case .group(let children, let groupStyle) = group, let child = children.first
    else { return XCTFail("the fixture's tipped Group is missing") }

    XCTAssertNotNil(groupStyle.tip)
    let effective = inheritedDrawStyle(parent: groupStyle, child: drawShapeStyle(child))
    XCTAssertNil(effective.tip, "a group's readout is about the group, not each child")
  }

  // ── Geometry + colour ──────────────────────────────────────────────────────

  func testTheTransformFitsTheWholeViewBoxAndCentresTheSlack() {
    let box = ViewBox(minX: 0, minY: 0, width: 200, height: 100)
    // A square viewport: the box fits by WIDTH, and the vertical slack centres.
    let t = DrawingTransform(viewBox: box, width: 400, height: 400)
    XCTAssertEqual(t.scale, 2, accuracy: 1e-12)
    XCTAssertEqual(t.pointX(0), 0, accuracy: 1e-12)
    XCTAssertEqual(t.pointX(200), 400, accuracy: 1e-12)
    XCTAssertEqual(t.pointY(0), 100, accuracy: 1e-12)
    XCTAssertEqual(t.pointY(100), 300, accuracy: 1e-12)
    XCTAssertEqual(t.length(10), 20, accuracy: 1e-12)
  }

  func testANonZeroViewBoxOriginShiftsTheMap() {
    let t = DrawingTransform(
      viewBox: ViewBox(minX: 10, minY: 20, width: 100, height: 100), width: 100, height: 100)
    XCTAssertEqual(t.pointX(10), 0, accuracy: 1e-12)
    XCTAssertEqual(t.pointY(20), 0, accuracy: 1e-12)
  }

  /// A degenerate box must not produce a NaN scale that silently blanks a
  /// drawing — the empty-drawing fixture is exactly that shape.
  func testADegenerateViewBoxStillProducesAUsableTransform() {
    let t = DrawingTransform(
      viewBox: ViewBox(minX: 0, minY: 0, width: 0, height: 0), width: 0, height: 0)
    XCTAssertTrue(t.scale.isFinite)
    XCTAssertGreaterThan(t.scale, 0)
  }

  func testColoursParseFromBothHexFormsAndTokensDeferToTheSurface() {
    let full = parseDrawColour("#3366cc")
    XCTAssertEqual(full?.red ?? -1, 51.0 / 255, accuracy: 1e-12)
    XCTAssertEqual(full?.green ?? -1, 102.0 / 255, accuracy: 1e-12)
    XCTAssertEqual(full?.blue ?? -1, 204.0 / 255, accuracy: 1e-12)

    let short = parseDrawColour("#36c")
    XCTAssertEqual(short?.red ?? -1, 51.0 / 255, accuracy: 1e-12)
    XCTAssertEqual(short?.blue ?? -1, 204.0 / 255, accuracy: 1e-12)

    // `currentColor` and design tokens name no literal colour — the surface's
    // own foreground answers for them, rather than an invented hex.
    XCTAssertNil(parseDrawColour("currentColor"))
    XCTAssertNil(parseDrawColour("--fuaran-accent"))
    XCTAssertNil(parseDrawColour("#12345"))
    XCTAssertNil(parseDrawColour(""))
  }

  func testAnchorFractionsCoverTheWholeVocabulary() {
    XCTAssertEqual(drawingAnchorFraction(nil), 0)
    XCTAssertEqual(drawingAnchorFraction(.start), 0)
    XCTAssertEqual(drawingAnchorFraction(.middle), 0.5)
    XCTAssertEqual(drawingAnchorFraction(.end), 1)
  }

  /// The lowering must reach every chart drawing in the corpus without a decode
  /// throw, and the tilt vocabulary must actually be present in what it reads —
  /// a green that came from an empty walk proves nothing.
  func testEveryChartLoweringGoldenComposesANameAndCarriesTilts() throws {
    guard let corpus = Self.corpusDir() else {
      throw XCTSkip("wire-format-fixtures corpus not found — skipping.")
    }
    let dir = corpus.appendingPathComponent("chart-lowering")
    guard let files = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
      throw XCTSkip("no chart-lowering family in this corpus revision.")
    }
    let goldens = files.filter { $0.hasSuffix(".expected.json") }.sorted()
    XCTAssertGreaterThan(goldens.count, 20, "the chart-lowering family looks truncated")

    var named = 0
    var rotations: Set<Double> = []
    let ctx = BindingContext.empty
    for file in goldens {
      let json = try String(contentsOf: dir.appendingPathComponent(file), encoding: .utf8)
      let node = try RenderProjection.decodeNode(json)
      guard case .drawing(let spec) = node.kind else { continue }
      if drawingAccessibilityName(
        title: spec.title.map(ctx.resolveText),
        description: spec.description.map(ctx.resolveText)) != nil
      {
        named += 1
      }
      for shape in spec.shapes {
        if case .label(_, _, _, let style) = shape, let r = style.rotation { rotations.insert(r) }
      }
    }
    XCTAssertEqual(named, goldens.count, "every lowered chart announces itself")
    XCTAssertTrue(rotations.contains(-90), "the rotated y-axis title is the lowering's own")
    XCTAssertTrue(rotations.contains(-30), "…and the tilted category labels")
  }
}
