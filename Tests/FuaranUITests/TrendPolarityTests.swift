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
      // `trendPolarity` is a BARE enum — a plain string in a named field, with
      // no `$type` member in the document at that position — so the reject path
      // is the field's own, with NO `.$type` suffix (Phase 1073;
      // `WIRE_FORMAT.md` §6's suffix rule is conditioned on the discriminator
      // being at fault, and here there is no discriminator on the wire to be at
      // fault). Asserted by EQUALITY, deliberately: this host emitted
      // `$.kind.trendPolarity.$type` from one helper serving both populations,
      // and a PREFIX assertion — here and in the corpus reject harness alike —
      // is exactly what let that divergence live unnoticed, because a spurious
      // suffix passes a prefix match.
      XCTAssertEqual(e.path, "$.kind.trendPolarity")
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
