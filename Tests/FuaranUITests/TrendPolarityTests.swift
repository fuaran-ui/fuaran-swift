// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// `Metric.trendPolarity` (WIRE_FORMAT.md §3.6.1) on the decode side. The corpus
// fixture `nodes/metric-inverted-polarity.json` proves the POSITIVE case through
// the ordinary corpus leg; everything a fixture cannot prove — the default when
// the slot is absent, the refusal of the reserved spelling, byte-shape
// independence from `trend` — is asserted here.

import XCTest

@testable import FuaranUI

final class TrendPolarityTests: XCTestCase {
  private func metric(_ inner: String) -> String {
    #"{"id":"m","kind":{"$type":"Metric","label":"Revenue","value":{"$type":"Static","value":42.0}"#
      + inner + "}}"
  }

  /// Absent means `HigherIsBetter`. This is a DEFAULT, not a third state — which
  /// is why the model slot is total rather than an `Optional`, and why this
  /// assertion is about a value rather than about `nil`.
  func testAbsentPolarityIsHigherIsBetter() throws {
    let node = try RenderProjection.decodeNode(metric(""))
    guard case .metric(let spec) = node.kind else { return XCTFail("expected .metric") }
    XCTAssertEqual(spec.trendPolarity, .higherIsBetter)
  }

  func testDeclaredPolarityDecodes() throws {
    let node = try RenderProjection.decodeNode(
      metric(#","trend":{"$type":"Static","value":-7.34},"trendPolarity":"LowerIsBetter""#))
    guard case .metric(let spec) = node.kind else { return XCTFail("expected .metric") }
    XCTAssertEqual(spec.trendPolarity, .lowerIsBetter)
    XCTAssertNotNil(spec.trend)
  }

  /// Clause 4: a polarity with no `trend` is legal and inert. It is KEPT rather
  /// than dropped — dropping it would silently rewrite the author's document
  /// because this surface judged the declaration pointless.
  func testInertPolarityWithNoTrendSurvives() throws {
    let node = try RenderProjection.decodeNode(metric(#","trendPolarity":"LowerIsBetter""#))
    guard case .metric(let spec) = node.kind else { return XCTFail("expected .metric") }
    XCTAssertEqual(spec.trendPolarity, .lowerIsBetter)
    XCTAssertNil(spec.trend)
  }

  /// The whole point of modelling the reserved case as ABSENCE from the case set
  /// rather than as a case the decoder refuses: default-deny does the work, the
  /// expected list cannot advertise a spelling the format does not accept, and
  /// no `switch` anywhere carries a dead arm.
  func testReservedNeutralIsRefusedByDefaultDeny() {
    XCTAssertThrowsError(
      try RenderProjection.decodeNode(metric(#","trendPolarity":"Neutral""#))
    ) { error in
      guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
      XCTAssertEqual(e.code, .unknownDuCase)
      // The canonical two-name expected list — the diagnostic every future
      // unknown-spelling failure prints. `Neutral` must not appear in it.
      XCTAssertTrue(
        e.message.contains("TrendPolarity: HigherIsBetter | LowerIsBetter"),
        "expected-list diagnostic drifted: \(e.message)")
      // Scoped to the EXPECTED-LIST half deliberately. The message also echoes
      // the rejected spelling as the `got` value, so a bare
      // `message.contains("Neutral")` reads red on a correct refusal — it did,
      // on the first run of this test, which is the probe verifying itself.
      guard let expectedList = e.message.range(of: "expected ").map({ e.message[$0.upperBound...] })
      else { return XCTFail("no expected-list in \(e.message)") }
      XCTAssertFalse(
        expectedList.contains("Neutral"), "the reserved case leaked into the expected list")
      // The path carries this host's family-wide `.$type` suffix (see the
      // reject-path note below); the corpus-stated prefix is what conformance
      // matches on, and both halves are pinned so a divergence in THIS slot
      // alone would go red.
      XCTAssertTrue(e.path.hasPrefix("$.kind.trendPolarity"), "path was \(e.path)")
    }
  }

  /// Neither the boolean spelling §3.6.1 refuses nor a direction word is
  /// aliased. Accepting either would decide, silently, a question the wire
  /// deliberately left to a declaration.
  func testNoAliasArmIsRegistered() {
    for spelling in ["Inverted", "Descending", "lowerIsBetter", "true"] {
      XCTAssertThrowsError(
        try RenderProjection.decodeNode(metric(#","trendPolarity":"\#(spelling)""#)),
        "'\(spelling)' must not be accepted")
    }
  }

  /// A wrong-TYPE polarity is a type error, not an unknown case — the slot is a
  /// bare string and a bool in it is the spelling the enum exists to refuse.
  func testBooleanPolarityIsRefused() {
    XCTAssertThrowsError(try RenderProjection.decodeNode(metric(#","trendPolarity":true"#)))
  }
}
