// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The trend-sentiment projection (WIRE_FORMAT.md §3.6.1). These assertions run
// on EVERY platform, not only macOS — which is the reason the projection sits
// outside the `#if canImport(SwiftUI)` gate at all. The thin colour half is
// Apple-gated and is exercised by the macOS CI job; the decisions are here.

import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class TrendSentimentTests: XCTestCase {
  /// `sentiment = sign(trend) × polarity`, the whole table. Note the two
  /// diagonals: the SAME number reads oppositely under the two declarations, and
  /// that is the entire content of the slot.
  func testSentimentIsSignTimesPolarity() {
    XCTAssertEqual(trendSentiment(.higherIsBetter, 7.34), .improving)
    XCTAssertEqual(trendSentiment(.higherIsBetter, -7.34), .regressing)
    XCTAssertEqual(trendSentiment(.lowerIsBetter, 7.34), .regressing)
    XCTAssertEqual(trendSentiment(.lowerIsBetter, -7.34), .improving)
    XCTAssertEqual(trendSentiment(.higherIsBetter, 0.0), .unchanged)
    XCTAssertEqual(trendSentiment(.lowerIsBetter, 0.0), .unchanged)
  }

  /// The corpus fixture's own node, read as the renderer reads it: a falling
  /// −7.34% under `LowerIsBetter` is an IMPROVEMENT, on a tile whose `tone` says
  /// `Warning`. That pair on one node is the case a single `tone` slot could
  /// never express, and it is why the field exists.
  func testTheCorpusPairImprovesOnAWarningTile() {
    XCTAssertEqual(trendSentiment(.lowerIsBetter, -7.34), .improving)
    // …and nothing in this file can reach a `ToneVariant`. The tile's tone is
    // untouched by construction, not by discipline.
  }

  /// `-0.0 == 0.0` in IEEE 754, so a negative zero must not smuggle in a
  /// direction the number does not have; a NaN satisfies neither comparison.
  func testZeroAndNaNReadUnchanged() {
    XCTAssertEqual(trendSentiment(.higherIsBetter, -0.0), .unchanged)
    XCTAssertEqual(trendSentiment(.lowerIsBetter, -0.0), .unchanged)
    XCTAssertEqual(trendSentiment(.higherIsBetter, Double.nan), .unchanged)
  }

  /// The non-colour channel. Colour alone fails WCAG 1.4.1, and §3.6.1 makes
  /// discharging that obligation non-optional while leaving HOW to the surface.
  /// The glyph tracks SENTIMENT rather than the number's direction — under an
  /// inverted polarity the triangle deliberately disagrees with the sign.
  func testGlyphAndSpokenLabelPerSentiment() {
    XCTAssertEqual(TrendSentiment.improving.glyph, "\u{25B2}")
    XCTAssertEqual(TrendSentiment.regressing.glyph, "\u{25BC}")
    XCTAssertEqual(TrendSentiment.unchanged.glyph, "\u{2192}")
    XCTAssertEqual(TrendSentiment.improving.accessibilityLabel, "improving")
    XCTAssertEqual(TrendSentiment.regressing.accessibilityLabel, "regressing")
    XCTAssertEqual(TrendSentiment.unchanged.accessibilityLabel, "unchanged")
    // The glyph for a FALLING number under an inverted polarity is the UP
    // triangle. If this ever reads ▼ the declaration stopped being honoured.
    XCTAssertEqual(trendSentiment(.lowerIsBetter, -7.34).glyph, "\u{25B2}")
  }

  /// The spoken labels are the reference tiers' own sentiment names, so a Swift
  /// surface speaks the word the HTML tiers put in `aria-label` for the same
  /// node. That is the parity claim this type makes, and the only one.
  func testSpokenLabelsMatchTheReferenceVocabulary() {
    XCTAssertEqual(
      TrendSentiment.allCases.map(\.accessibilityLabel),
      ["improving", "regressing", "unchanged"])
  }

  /// The resolved-string entry point. A trend that does not read as a number
  /// yields NO sentiment — the surface's counterpart of the reference
  /// renderers' unresolved branch, which emits an unclassed trend element with
  /// no glyph. Inventing a sentiment there would be a claim about a number
  /// nobody has.
  func testUnparseableResolvedTrendYieldsNoSentiment() {
    XCTAssertNil(trendSentiment(.higherIsBetter, resolvedTrend: "—"))
    XCTAssertNil(trendSentiment(.higherIsBetter, resolvedTrend: "[i18n:trend]"))
    XCTAssertNil(trendSentiment(.higherIsBetter, resolvedTrend: "-7.34%"))
    XCTAssertNil(trendSentiment(.higherIsBetter, resolvedTrend: ""))
  }

  func testParseableResolvedTrendProjects() {
    XCTAssertEqual(trendSentiment(.lowerIsBetter, resolvedTrend: " -7.34 "), .improving)
    XCTAssertEqual(trendSentiment(.higherIsBetter, resolvedTrend: "-7.34"), .regressing)
    XCTAssertEqual(trendSentiment(.higherIsBetter, resolvedTrend: "0"), .unchanged)
  }
}
