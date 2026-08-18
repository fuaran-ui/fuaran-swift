// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Drawing render arm on the macOS rig — the half no other platform can run.
//
// The headline test is the ROTATION PROBE. Everything else about the rotation
// sign is settled in the pure lowering, on every platform; the one claim that
// cannot be settled there is that SwiftUI's own rotation shares the wire's
// convention, because "a positive angle turns clockwise" is a fact about a
// framework, not about arithmetic. So it is not asserted in prose: a marker is
// RASTERISED through `ImageRenderer` and the drawn pixels are compared against
// what the pure `svgRotate` predicts — with the flipped prediction asserted NOT
// to match, so a probe that passed by symmetry would be caught.
//
// The probe carries its own orientation control, because a vertically flipped
// read-back would make a wrong answer look right; the control marker is placed
// asymmetrically so a flip is diagnosed rather than absorbed.

import XCTest

#if canImport(SwiftUI)

  import CoreGraphics
  import Foundation
  import SwiftUI

  @testable import FuaranUI
  @testable import FuaranUIRenderer

  @MainActor
  final class DrawingRenderTests: XCTestCase {

    // ── The rasterised rotation probe ────────────────────────────────────────

    private static let side: CGFloat = 200
    private static let pivot = CGPoint(x: 100, y: 100)

    /// Rasterise `view` at 1× and return the centroid of its opaque pixels, in
    /// the same y-down coordinates SwiftUI laid it out in.
    private func opaqueCentroid<V: View>(_ view: V) throws -> CGPoint {
      let renderer = ImageRenderer(content: view)
      renderer.scale = 1
      guard let image = renderer.cgImage else {
        throw XCTSkip(
          "ImageRenderer produced no image on this rig — the rasterised probe cannot run.")
      }
      let w = image.width
      let h = image.height
      var bytes = [UInt8](repeating: 0, count: w * h * 4)
      let ok: Bool = bytes.withUnsafeMutableBytes { raw -> Bool in
        guard
          let ctx = CGContext(
            data: raw.baseAddress, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return false }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return true
      }
      guard ok else { throw XCTSkip("no bitmap context available on this rig.") }

      var sumX = 0.0
      var sumY = 0.0
      var count = 0.0
      for y in 0..<h {
        for x in 0..<w where bytes[(y * w + x) * 4 + 3] > 128 {
          sumX += Double(x)
          sumY += Double(y)
          count += 1
        }
      }
      guard count > 0 else {
        throw XCTSkip("the probe rendered no opaque pixels on this rig.")
      }
      return CGPoint(x: sumX / count + 0.5, y: sumY / count + 0.5)
    }

    /// A single opaque marker centred on `at`, inside the probe's square, with
    /// an optional rotation about the probe's pivot.
    private func marker(at point: CGPoint, degrees: Double) -> some View {
      ZStack(alignment: .topLeading) {
        Rectangle()
          .fill(Color.black)
          .frame(width: 6, height: 6)
          .position(x: point.x, y: point.y)
      }
      .frame(width: Self.side, height: Self.side, alignment: .topLeading)
      .rotationEffect(
        .degrees(degrees),
        anchor: UnitPoint(x: Self.pivot.x / Self.side, y: Self.pivot.y / Self.side))
    }

    func testSwiftUIRotationSharesTheWiresClockwisePositiveConvention() throws {
      // (1) ORIENTATION CONTROL. An unrotated marker, placed asymmetrically in
      // y, so a vertically flipped read-back cannot pass as a correct one.
      let control = try opaqueCentroid(marker(at: CGPoint(x: 160, y: 40), degrees: 0))
      XCTAssertEqual(
        Double(control.x), 160, accuracy: 2, "probe read-back is horizontally displaced")
      XCTAssertEqual(
        Double(control.y), 40, accuracy: 2,
        "probe read-back is vertically flipped or displaced — centroid \(control)")

      // (2) THE PROBE. A marker 60 points to the RIGHT of the pivot, turned by
      // the lowering's own default tilt.
      let degrees = -30.0
      let start = CGPoint(x: Self.pivot.x + 60, y: Self.pivot.y)
      let drawn = try opaqueCentroid(marker(at: start, degrees: degrees))

      let predicted = svgRotate(
        x: Double(start.x), y: Double(start.y), aboutX: Double(Self.pivot.x),
        aboutY: Double(Self.pivot.y), degrees: degrees)
      XCTAssertEqual(
        Double(drawn.x), predicted.x, accuracy: 2,
        "drawn \(drawn) vs the wire's own rotation \(predicted)")
      XCTAssertEqual(
        Double(drawn.y), predicted.y, accuracy: 2,
        "drawn \(drawn) vs the wire's own rotation \(predicted) — a mismatch here means "
          + "SwiftUI and the wire disagree about the sign, and the render arm must convert")

      // (3) THE GO-RED GUARD. The flipped prediction must NOT describe the same
      // pixels, or the probe passed by symmetry rather than by agreement.
      let flipped = svgRotate(
        x: Double(start.x), y: Double(start.y), aboutX: Double(Self.pivot.x),
        aboutY: Double(Self.pivot.y), degrees: -degrees)
      XCTAssertGreaterThan(
        abs(Double(drawn.y) - flipped.y), 30,
        "the probe cannot distinguish the two signs — it proves nothing as written")
    }

    /// The pivot is invariant under rotation — the property the render arm's
    /// zero-size anchor construction exists to preserve, checked in pixels.
    func testAMarkerOnThePivotDoesNotMoveWhenRotated() throws {
      let onPivot = try opaqueCentroid(marker(at: Self.pivot, degrees: -75))
      XCTAssertEqual(Double(onPivot.x), Double(Self.pivot.x), accuracy: 2)
      XCTAssertEqual(Double(onPivot.y), Double(Self.pivot.y), accuracy: 2)
    }

    // ── The arm itself builds, for every shape in the corpus fixtures ────────

    private func drawingFixture(_ relativePath: String) throws -> DrawingSpec {
      guard let corpus = RenderCoverageTests.corpusDir() else {
        throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
      }
      let url = corpus.appendingPathComponent(relativePath)
      guard FileManager.default.fileExists(atPath: url.path) else {
        throw XCTSkip("corpus fixture \(relativePath) not present in this corpus revision.")
      }
      let node = try RenderProjection.decodeNode(try String(contentsOf: url, encoding: .utf8))
      guard case .drawing(let spec) = node.kind else {
        throw XCTSkip("\(relativePath) is not a Drawing fixture")
      }
      return spec
    }

    /// Every shape in the rotated + tipped fixtures projects through a real arm
    /// of the exhaustive shape spine — including the tip modifier and the
    /// rotation modifier, which are only reachable on this rig.
    func testEveryShapeInTheRotatedAndTippedFixturesProjects() throws {
      for path in [
        "nodes/drawing-rotated-labels.json", "nodes/drawing-tipped-shapes.json",
        "nodes/drawing-1.json",
      ] {
        let spec = try drawingFixture(path)
        XCTAssertGreaterThan(spec.shapes.count, 0, path)
        let t = DrawingTransform(viewBox: spec.viewBox, width: 400, height: 240)
        for shape in spec.shapes {
          _ = fuaranDrawShapeView(shape, inherited: spec.style, t: t, ctx: .empty)
        }
        _ = FuaranDrawing(spec, .empty).body
      }
    }

    /// A lowered chart golden renders through the node spine, and its root
    /// carries the composed name the web surface announces.
    func testALoweredChartRendersAndAnnouncesItsSummary() throws {
      let spec = try drawingFixture("chart-lowering/bar-tilt-boundary.expected.json")
      let coverage = RenderCoverage()
      let ctx = BindingContext(state: [:], coverage: coverage)
      _ = fuaranNodeBody(Node(id: "probe", kind: .drawing(spec)), ctx)
      XCTAssertTrue(coverage.fallbacks.isEmpty, "fallback-arm hits: \(coverage.fallbacks.sorted())")
      XCTAssertEqual(coverage.kinds["Drawing"], 1)

      let name = drawingAccessibilityName(
        title: spec.title.map(ctx.resolveText), description: spec.description.map(ctx.resolveText))
      XCTAssertEqual(
        name,
        "At the tilt-to-vertical boundary. Bar chart. 1 series: count. 4 categories: "
          + "11111111111111111110 to 11111111111111111113. Peak count at "
          + "11111111111111111113, 47.")
    }
  }

#else

  final class DrawingRenderTests: XCTestCase {
    func testDrawingRenderLegSkipsWhenSwiftUIAbsent() throws {
      throw XCTSkip(
        "SwiftUI not available on this platform — the Drawing render arm is a SwiftUI "
          + "(macOS-reference) leg; its pure lowering is covered by DrawingLoweringTests. Skipping."
      )
    }
  }

#endif
