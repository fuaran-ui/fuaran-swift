// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Phase 541 tone-bridge gate. The tone palette + typography/spacing tokens
// are pure (scheme-independent construction), so they are proven headlessly:
// the light and dark palettes differ per tone token (the "differs visibly and
// correctly between light and dark" acceptance, established at the palette level
// rather than by pixel-diffing a live view), the badge vocabulary maps onto the
// palette, and the emphasis/spacing/heading tokens ramp as specified. Skips
// cleanly where SwiftUI is unavailable.

import XCTest

#if canImport(SwiftUI)

  import FuaranUI
  import SwiftUI

  @testable import FuaranUIRenderer

  final class ThemeTests: XCTestCase {
    func testLightAndDarkTonesDifferPerToken() {
      for tone in ToneVariant.allCases {
        XCTAssertNotEqual(
          LightTones.swatch(tone).container, DarkTones.swatch(tone).container,
          "\(tone) container should differ between light and dark")
      }
    }

    func testBadgeMapsOntoThePalette() {
      XCTAssertEqual(LightTones.badge(.neutral).container, LightTones.subdued.container)
      XCTAssertEqual(LightTones.badge(.brand).container, LightTones.brand.container)
      XCTAssertEqual(DarkTones.badge(.critical).container, DarkTones.critical.container)
    }

    func testEmphasisTypographyTokens() {
      XCTAssertEqual(emphasisWeight(.loud), .bold)
      XCTAssertEqual(emphasisWeight(.quiet), .light)
      XCTAssertEqual(emphasisWeight(.normal), .regular)
      XCTAssertGreaterThan(emphasisScale(.loud), emphasisScale(.normal))
      XCTAssertLessThan(emphasisScale(.quiet), emphasisScale(.normal))
    }

    func testSpacingTokensIncreaseWithDensity() {
      XCTAssertLessThan(FuaranSpacing.pad(.compact), FuaranSpacing.pad(.standard))
      XCTAssertLessThan(FuaranSpacing.pad(.standard), FuaranSpacing.pad(.spacious))
      XCTAssertLessThan(FuaranSpacing.gap(.compact), FuaranSpacing.gap(.spacious))
    }

    func testHeadingSizeShrinksWithLevel() {
      XCTAssertGreaterThan(headingSize(.standard, 1), headingSize(.standard, 3))
      XCTAssertGreaterThan(headingSize(.standard, 3), headingSize(.standard, 6))
    }
  }

#else

  final class ThemeTests: XCTestCase {
    func testThemeLegSkipsWhenSwiftUIAbsent() throws {
      throw XCTSkip("SwiftUI not available — the tone bridge is a SwiftUI leg; skipping.")
    }
  }

#endif
