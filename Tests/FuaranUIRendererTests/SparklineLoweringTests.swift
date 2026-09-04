// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The `sparkline-lowering/` conformance leg (Phase 1099).
//
// **The goldens are the contract, and this suite is the whole of this surface's
// claim to them.** Each vector pairs a neutral resolved series with the canonical
// wire JSON of the `Drawing` node the lowering must produce, so the assertion is
// not "does this look like a sparkline" but "does this surface produce the same
// geometry every other adopting host does". The family is deliberately NOT
// indexed by the corpus `manifest.json` — a codec runner dispatches on that
// manifest's `kind` and a lowering is not a round-trip — so it is located by
// directory here rather than through the manifest reader the other legs use.
//
// **The expected side is DECODED rather than string-compared**, and that is the
// one design decision in this file. This surface never canonically encodes, so it
// has no bytes to compare; what it can do is decode the golden through its own
// production decoder and compare the two `DrawingSpec` values structurally. That
// is a strictly stronger check than it sounds — a lowering that got the geometry
// right and the STYLE wrong, or the viewBox wrong, or emitted two shapes, fails
// here — and it exercises the decoder against the golden at the same time.
//
// **Equality is NaN-aware, and it has to be.** `Double` equality says
// `NaN != NaN`, so `DrawingSpec: Equatable` would report the `nonfinite-sentinel`
// vector as a mismatch however perfectly it matched. The comparison below treats
// two non-finite ordinates as equal when they are the same non-finite value,
// which is the question the vector is actually asking — and it is confined to
// this comparison rather than being given to the model, where it would make an
// equality nobody else expects.

import Foundation
import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class SparklineLoweringTests: XCTestCase {
  /// `<repo>/Tests/FuaranUIRendererTests/…` → `<repo>/../wire-format-fixtures/sparkline-lowering`.
  private static var familyDir: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("wire-format-fixtures")
      .appendingPathComponent("sparkline-lowering")
  }

  /// The corpus, or the right kind of stop — the `RenderObligationTests` posture.
  ///
  /// A missing family has two meanings and collapsing them into one clean skip is
  /// a vacuous green: on a standalone clone the skip is honest; where the corpus
  /// is plainly here and only this family is not, the gate would certify NOTHING
  /// while reporting success.
  private func requireFamily() throws -> URL {
    let dir = Self.familyDir
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: dir.path, isDirectory: &isDir), isDir.boolValue {
      return dir
    }
    let corpus = dir.deletingLastPathComponent()
    if FileManager.default.fileExists(atPath: corpus.path, isDirectory: &isDir), isDir.boolValue {
      XCTFail(
        "the wire-format-fixtures corpus is present at \(corpus.path) but sparkline-lowering/ is "
          + "not — this gate certified NOTHING. If the family moved or was renamed, correct the "
          + "locator rather than letting the harness skip.")
      return dir
    }
    throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
  }

  /// The resolved series a vector's `.input.json` carries, read with the
  /// production decoder's own sentinel rule so a runner cannot disagree with the
  /// decoder about what `"NaN"` means.
  private func series(_ url: URL) throws -> [Double] {
    let json = try JSON.parse(try String(contentsOf: url, encoding: .utf8))
    guard case .object(let root) = json, case .array(let items)? = root["series"] else {
      XCTFail("\(url.lastPathComponent): no `series` array")
      return []
    }
    return try items.enumerated().map { try Decode.float("$.series[\($0.0)]", $0.1) }
  }

  /// The `DrawingSpec` a vector's `.expected.json` carries, or `nil` for the
  /// literal `null` that means "nothing to draw".
  private func expected(_ url: URL) throws -> DrawingSpec? {
    let text = try String(contentsOf: url, encoding: .utf8)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    if text == "null" { return nil }
    guard case .drawing(let spec) = try RenderProjection.decodeNode(text).kind else {
      XCTFail("\(url.lastPathComponent): the expected node is not a Drawing")
      return nil
    }
    return spec
  }

  // ── NaN-aware structural comparison ────────────────────────────────────────

  private func sameNumber(_ a: Double, _ b: Double) -> Bool {
    if a.isNaN && b.isNaN { return true }
    return a == b
  }

  private func samePoints(_ a: [DrawPoint], _ b: [DrawPoint]) -> Bool {
    a.count == b.count
      && zip(a, b).allSatisfy { sameNumber($0.x, $1.x) && sameNumber($0.y, $1.y) }
  }

  private func assertSame(_ produced: DrawingSpec, _ golden: DrawingSpec, _ name: String) {
    XCTAssertEqual(produced.viewBox, golden.viewBox, "\(name): viewBox")
    XCTAssertEqual(produced.style, golden.style, "\(name): root style")
    XCTAssertNil(produced.title, "\(name): a sparkline carries no accessible name of its own")
    XCTAssertNil(produced.description, "\(name): …and no description either")
    XCTAssertEqual(produced.shapes.count, 1, "\(name): exactly one shape")
    XCTAssertEqual(golden.shapes.count, 1, "\(name): the golden carries exactly one shape")
    guard case .polyline(let mine, let myStyle)? = produced.shapes.first,
      case .polyline(let theirs, let theirStyle)? = golden.shapes.first
    else {
      return XCTFail("\(name): expected a polyline on both sides")
    }
    XCTAssertEqual(myStyle, theirStyle, "\(name): stroke chrome")
    XCTAssertTrue(
      samePoints(mine, theirs),
      "\(name): geometry differs\n  produced: \(mine)\n  golden:   \(theirs)")
  }

  // ── The gate ───────────────────────────────────────────────────────────────

  func testEveryGoldenVectorIsReproduced() throws {
    let dir = try requireFamily()
    let names = try FileManager.default.contentsOfDirectory(atPath: dir.path)
      .filter { $0.hasSuffix(".input.json") }
      .map { String($0.dropLast(".input.json".count)) }
      .sorted()

    XCTAssertGreaterThan(
      names.count, 0,
      "sparkline-lowering/ carries no input vectors — this gate is asserting nothing")

    for name in names {
      let input = try series(dir.appendingPathComponent("\(name).input.json"))
      let golden = try expected(dir.appendingPathComponent("\(name).expected.json"))
      let produced = sparklineDrawing(series: input)

      switch (produced, golden) {
      case (nil, nil):
        // The `empty` vector: nothing to draw, and the fallback the arm renders
        // instead is a HOST element rather than a Shape, so the lowering must
        // not pretend to express it with an empty canvas.
        continue
      case (let mine?, let theirs?):
        assertSame(mine, theirs, name)
      case (nil, _?):
        XCTFail("\(name): the lowering drew nothing where the golden draws a picture")
      case (_?, nil):
        XCTFail("\(name): the lowering drew a picture where the golden draws nothing")
      }
    }
    print("SPARKLINE LOWERING: \(names.count) golden vectors reproduced")
  }

  // ── The go-red proof ───────────────────────────────────────────────────────

  func testTheComparisonCanFail() throws {
    // Without this, every assertion above could be vacuous — a comparison that
    // accepts anything reports success on a lowering that draws the wrong
    // picture. Each perturbation is one the goldens are specifically shaped to
    // catch.
    let series: [Double] = [1, 2, 3, 2, 4]
    guard let ok = sparklineDrawing(series: series) else {
      return XCTFail("the ordinary vector must lower to a drawing")
    }
    guard case .polyline(let points, _)? = ok.shapes.first else {
      return XCTFail("expected a polyline")
    }

    // The geometry is not merely "some ascending line": these are the golden's
    // own numbers, and a lowering off by the one-unit inset or the 28-unit
    // span misses every one of them.
    XCTAssertEqual(points.map(\.x), [0, 25, 50, 75, 100])
    XCTAssertEqual(points.map(\.y), [29, 19.67, 10.33, 19.67, 1])

    // The flat guard DECIDES the flat-boundary vector rather than the
    // arithmetic happening to agree: a range of 5e-10 is inside the epsilon.
    guard let flat = sparklineDrawing(series: [1, 1.0000000005, 1]),
      case .polyline(let flatPoints, _)? = flat.shapes.first
    else { return XCTFail("expected a polyline for the flat-boundary series") }
    XCTAssertEqual(flatPoints.map(\.y), [29, 29, 29], "the guard collapses the range to 1.0")

    // A lone point is CENTRED, not divided by zero.
    guard let single = sparklineDrawing(series: [42]),
      case .polyline(let singlePoints, _)? = single.shapes.first
    else { return XCTFail("expected a polyline for a single-point series") }
    XCTAssertEqual(singlePoints.map(\.x), [50])

    // Nothing to draw lowers to nil, never to an empty canvas.
    XCTAssertNil(sparklineDrawing(series: []))

    // And the NaN-aware comparison is not blanket-permissive: it must still
    // separate a NaN from a number, or the sentinel vector would pass against
    // any geometry at all.
    XCTAssertTrue(sameNumber(Double.nan, Double.nan))
    XCTAssertFalse(sameNumber(Double.nan, 0))
    XCTAssertFalse(sameNumber(Double.infinity, Double.nan))
    XCTAssertTrue(sameNumber(Double.infinity, Double.infinity))
  }

  func testTheSeriesReachesTheLoweringFromADecodedNode() throws {
    // The lowering is only worth anything if the wire's own series reaches it.
    // This is the arm's path in miniature: decode the corpus's canonical
    // sparkline shape, resolve the slot through the render context, lower.
    let json = #"""
      {"id":"spark-1","kind":{"$type":"Sparkline","source":{"$type":"Static","value":[1,2,3,2,4]}}}
      """#
    guard case .sparkline(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected a Sparkline node")
    }
    let resolved = BindingContext.empty.resolveNumbers(spec.source)
    XCTAssertEqual(resolved, [1, 2, 3, 2, 4], "the typed series survives resolution")
    XCTAssertNotNil(sparklineDrawing(series: resolved))

    // The sentinel shape too — this is the element class a display-string round
    // trip would have destroyed, which is why `resolveNumbers` reads the typed
    // payload rather than parsing `flatten`'s output back.
    let sentinelJSON = #"""
      {"id":"s","kind":{"$type":"Sparkline","source":{"$type":"Static","value":[1,"NaN",3]}}}
      """#
    guard case .sparkline(let sentinelSpec) = try RenderProjection.decodeNode(sentinelJSON).kind
    else { return XCTFail("expected a Sparkline node") }
    let sentinel = BindingContext.empty.resolveNumbers(sentinelSpec.source)
    XCTAssertEqual(sentinel.count, 3)
    XCTAssertTrue(sentinel[1].isNaN, "the sentinel survives as a non-finite value, not as 0")
  }
}
