// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The `Sparkline` render lowering (Phase 1099) — a resolved series turned into
// the `Drawing` this surface already knows how to paint.
//
// ## The posture, stated because it was a decision and not a default
//
// `Sparkline` carries a bare bound series and nothing else, so every host that
// draws one has to turn that series into geometry. Until this file, THIS surface
// did not draw one at all: the render arm was a fixed grey rounded rectangle
// taking no arguments, which meant the series was not merely unpainted but
// structurally UNREACHABLE — a slot that decoded, validated, rendered and did
// nothing. That is the shape a hand-copied or placeholder render path takes
// exactly before it starts to disagree with every other host.
//
// **The alternative was legitimate and was rejected on its merits.** A host may
// decline the lowering and pin its placeholder as a tested contract instead; the
// declining hosts do exactly that. This surface adopts, for two reasons specific
// to it. It already carries a full vector `Drawing` arm — a real canvas, a real
// polyline, real style inheritance — so lowering costs a pure function and
// reuses a seam rather than adding a renderer. And the geometry is a CONTRACT
// pinned by shared goldens, so the arithmetic below is not this surface's
// opinion about how a sparkline should look; it is the one every conformant host
// draws, and a divergence in it is a failing test rather than an argument.
//
// **No hand-written vector output survives here**: the lowering emits the wire's
// own `DrawingSpec`, which the existing drawing canvas renders. There is one
// picture-drawing path on this surface and the sparkline now goes through it.
//
// ## What the goldens fix
//
// Over a series of `n` values with `min` and `max`:
//
// | | |
// |---|---|
// | canvas | `viewBox="0 0 100 30"` |
// | `range` | `max - min`, or **`1.0` when `max - min < 1e-9`** — a constant series sits on its own line rather than dividing by zero |
// | `x` | `i / (n - 1) * 100`, and **`50` when `n = 1`** — a lone point is centred |
// | `y` | `30 - (v - min) / range * 28 - 1` — one unit of inset at each edge, so a peak is not clipped by the stroke |
// | rounding | round-half-up to 2 decimal places, on BOTH coordinates |
// | chrome | one polyline, `stroke = currentColor`, `strokeWidth = 1.5`, no fill |
// | title / desc | **none** — a sparkline has no spec to generate a summary from, so it carries no accessible name of its own |
//
// **A case with nothing to draw lowers to `nil`.** An empty (or absent) series
// has no polyline, and the fallback a host renders instead is a HOST element
// rather than a `Shape` — so the lowering cannot express it and must not pretend
// to by emitting an empty canvas. `nil` is that fact, and the arm renders its own
// placeholder for it.
//
// **Non-finite values are NOT special-cased**, and that is the rule rather than
// an oversight: they propagate through the arithmetic above and reach the picture
// as whatever it makes of them. This is the input class where a hand-copied path
// drifts first, which is why the goldens pin it — and why the min/max fold below
// is written out rather than delegated to a standard-library reduction whose NaN
// ordering is a language's own choice. With a `<`-comparing fold, a series
// carrying both infinities yields `min = -∞` and `max = +∞`, hence an infinite
// range, hence a NaN ordinate at every point; that is what the shared
// `nonfinite-sentinel` vector records, and it is a fact about the ARITHMETIC, not
// about any host.
//
// Pure, and deliberately OUTSIDE the SwiftUI gate — the `DrawingLowering.swift`
// reasoning, which this file sits beside for exactly that purpose.

import Foundation
import FuaranUI

/// The sparkline canvas — fixed by the goldens, not a host choice.
public let sparklineViewBox = ViewBox(minX: 0, minY: 0, width: 100, height: 30)

/// The flat-series guard: a range below this collapses to `1.0`.
///
/// The `flat-boundary` vector sits just INSIDE it deliberately, so the guard
/// decides the picture rather than the arithmetic happening to agree — a host
/// that dropped the guard and relied on the division being "close enough" fails
/// there and nowhere else.
public let sparklineFlatEpsilon = 1e-9

/// Round half-up to two decimal places.
///
/// Written out rather than taken from a formatter: `.rounded()` is
/// round-half-away-from-zero and a formatter's mode is a locale's business,
/// where this is a contract two hosts have to agree on to the digit. Non-finite
/// input passes through unchanged, which is what lets the sentinel vector's
/// ordinates stay non-finite instead of collapsing to zero here.
public func sparklineRound2(_ value: Double) -> Double {
  guard value.isFinite else { return value }
  return (value * 100 + 0.5).rounded(.down) / 100
}

/// The series' extent, folded with `<` / `>` rather than by a library reduction.
///
/// The comparison semantics ARE the contract for a series carrying non-finite
/// values — every `<` against a NaN is false, so a NaN never becomes the extent
/// while an infinity always does — and a standard library is entitled to order
/// NaN however it likes. Writing the fold is how this surface stops inheriting
/// that choice.
func sparklineExtent(_ series: [Double]) -> (min: Double, max: Double)? {
  guard var lo = series.first else { return nil }
  var hi = lo
  for value in series.dropFirst() {
    if value < lo { lo = value }
    if value > hi { hi = value }
  }
  return (lo, hi)
}

/// Lower a RESOLVED sparkline series to the `Drawing` that draws it, or `nil`
/// where there is nothing to draw.
///
/// The series is the resolved value of `SparklineSpec.source`: a host runs its
/// own binding resolution first, so nothing here reads a `Binding` — the same
/// division `mediaPlaybackPlan` makes, and for the same reason.
public func sparklineDrawing(series: [Double]) -> DrawingSpec? {
  guard let extent = sparklineExtent(series) else { return nil }

  let spread = extent.max - extent.min
  // NOT `abs(spread) < eps`: the goldens' guard is the difference itself, and a
  // NaN spread satisfies neither comparison, so it falls through to the division
  // exactly as the sentinel vector requires.
  let range = spread < sparklineFlatEpsilon ? 1.0 : spread

  let points = series.enumerated().map { (index, value) -> DrawPoint in
    // A lone point is CENTRED rather than divided by zero — the `n = 1` case is
    // a placement rule, not an arithmetic accident.
    let x = series.count == 1 ? 50.0 : Double(index) / Double(series.count - 1) * 100.0
    let y = 30.0 - (value - extent.min) / range * 28.0 - 1.0
    return DrawPoint(x: sparklineRound2(x), y: sparklineRound2(y))
  }

  return DrawingSpec(
    viewBox: sparklineViewBox,
    shapes: [
      .polyline(
        points: points,
        style: DrawStyle(
          // The wire's own style shape, so the existing drawing canvas reads
          // this exactly as it reads an authored `Drawing` — no second styling
          // path, which is the point of lowering rather than hand-drawing.
          stroke: .staticValue(.ast(.string("currentColor"))),
          strokeWidth: .staticValue(.ast(.number(1.5)))))
    ],
    // The open-shape default: no fill on the shape, nothing at the root.
    style: .empty,
    // NONE, deliberately. A sparkline has no spec to generate a summary from,
    // so it carries no accessible name of its own — and inventing one here
    // would announce a claim about a series nobody made.
    title: nil,
    description: nil)
}
