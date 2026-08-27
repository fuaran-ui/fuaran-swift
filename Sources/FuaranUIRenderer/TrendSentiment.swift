// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The trend-sentiment projection — `Metric.trend` read through
// `Metric.trendPolarity` (WIRE_FORMAT.md §3.6.1).
//
// **What the wire asks for.** `tone` says how the reading STANDS and colours the
// TILE; `trendPolarity` says which way the quantity IMPROVES and reaches the
// TREND element alone. Sentiment is `sign(trend) × polarity`, where
// `HigherIsBetter` is `+1` and `LowerIsBetter` is `−1`: a positive product is an
// improvement, a negative product a regression, a zero trend neither. The
// numeric text — its sign included — is UNCHANGED by polarity. A falling −7.34%
// prints −7.34% under either declaration; polarity changes how the number READS,
// never what it SAYS.
//
// **Nothing here writes back to `tone`.** A surface that inferred "improving ⇒
// tile is Success" would re-create in the render the exact conflation the wire
// slot exists to remove, and would override an emitter's deliberate `Critical`
// on a metric improving from a bad place. There is no path from this file to a
// `ToneVariant`, by construction rather than by discipline.
//
// **Pure, and deliberately OUTSIDE the SwiftUI gate** — the same reasoning as
// the accessibility projection next door and the grid-cell lowering in
// `BindingContext.swift`. The decisions are the load-bearing part (which
// product reads as which sentiment, which glyph carries it, what an
// unresolvable trend does), and a helper inside `#if canImport(SwiftUI)` can
// only ever be exercised on macOS. Here they run on every platform; the thin
// view application in `FuaranNode.swift` is the only Apple-gated half.
//
// **The structural intent transfers from the reference renderers; the CSS
// constraint does not.** Those tiers emit
// `fuaran-metric-trend-{improving,regressing,unchanged}` class modifiers plus a
// glyph carrying an `aria-label`. SwiftUI has no class vocabulary, so what
// crosses is the pair — a sentiment and a non-colour channel for it — projected
// into this platform's own idiom: a `foregroundStyle` from the theme and an
// `.accessibilityLabel` on the glyph.

import Foundation
import FuaranUI

/// The rendered sentiment of a resolved trend under its declared polarity.
///
/// The raw values are the reference tiers' own sentiment names, so the
/// accessible label a Swift surface speaks is the word the HTML tiers put in
/// `aria-label` for the same node. That is the parity claim this type makes and
/// the only one it makes: the visual treatment is this platform's.
public enum TrendSentiment: String, CaseIterable, Equatable, Sendable {
  case improving
  case regressing
  case unchanged

  /// The non-colour channel. U+25B2 BLACK UP-POINTING TRIANGLE, U+25BC BLACK
  /// DOWN-POINTING TRIANGLE, U+2192 RIGHTWARDS ARROW — named in prose so a
  /// mojibake in this file is a diff a reviewer can catch rather than a rendered
  /// byte nobody pinned.
  ///
  /// Sentiment carried by colour ALONE fails WCAG 1.4.1, and §3.6.1 makes
  /// discharging that obligation non-optional while leaving HOW to the surface.
  /// The glyph tracks SENTIMENT, not the number's direction: under an inverted
  /// polarity the triangle deliberately disagrees with the sign, and that
  /// disagreement is the visible evidence the declaration was honoured.
  public var glyph: String {
    switch self {
    case .improving: return "▲"
    case .regressing: return "▼"
    case .unchanged: return "→"
    }
  }

  /// The spoken sentiment, applied to the GLYPH rather than to the trend view.
  ///
  /// On the trend view it would OVERRIDE the element's text and assistive
  /// technology would hear "improving" and lose the number; on the glyph — which
  /// otherwise announces as an unpronounceable symbol or as nothing — it adds
  /// the sentiment beside the numeric text. The reference tiers place it the
  /// same way and record the same reason.
  public var accessibilityLabel: String { rawValue }
}

/// `sentiment = sign(trend) × polarity`.
///
/// Total in both arguments and dependent on nothing else — no second binding, no
/// cross-node coordination, no state. `-0.0` compares equal to `0.0` in IEEE
/// 754, so a negative zero reads `unchanged` rather than smuggling in a
/// direction the number does not have; a NaN trend satisfies neither comparison
/// and also reads `unchanged`, which is the honest answer for a quantity that
/// did not move anywhere expressible.
public func trendSentiment(_ polarity: TrendPolarity, _ trend: Double) -> TrendSentiment {
  let direction: Double
  switch polarity {
  case .higherIsBetter: direction = 1.0
  case .lowerIsBetter: direction = -1.0
  }
  let sentiment = trend * direction
  if sentiment > 0.0 { return .improving }
  if sentiment < 0.0 { return .regressing }
  return .unchanged
}

/// The projection actually applied by the render arm: a resolved trend STRING
/// read as a number, or `nil` when it is not one.
///
/// `nil` is the surface's counterpart of the reference renderers' unresolved
/// branch, which emits the trend element with no sentiment class and no glyph.
/// This surface resolves a binding to its display string and reads a number back
/// out — the idiom `resolveFloat` already uses throughout this renderer — so a
/// trend that resolves to `—`, an i18n placeholder or a formatted string with a
/// unit yields no sentiment. Asserting nothing is the correct outcome there: a
/// sentiment invented from an unparsed string would be a claim about a number
/// nobody has.
public func trendSentiment(_ polarity: TrendPolarity, resolvedTrend: String) -> TrendSentiment? {
  guard let t = Double(resolvedTrend.trimmingCharacters(in: .whitespaces)) else { return nil }
  return trendSentiment(polarity, t)
}

#if canImport(SwiftUI)

  import SwiftUI

  /// The colour half of the channel pair, in this platform's idiom.
  ///
  /// It reaches into the tone PALETTE by sentiment — never into the node's own
  /// `tone` slot, and never back out to it. A `nil` sentiment (an unresolvable
  /// trend) takes the neutral tint, matching the reference tiers' unclassed
  /// trend element.
  func trendTint(_ sentiment: TrendSentiment?, _ tones: FuaranTonePalette) -> Color {
    switch sentiment {
    case .improving: return tones.success.accent
    case .regressing: return tones.critical.accent
    case .unchanged, nil: return tones.subdued.accent
    }
  }

#endif
