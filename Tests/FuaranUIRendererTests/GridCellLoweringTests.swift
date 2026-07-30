// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Phase 752 — the grid-cell lowering, tested on EVERY platform.
//
// The SwiftUI renderer itself is behind `#if canImport(SwiftUI)`, so its arms are
// only exercised by the macOS CI job. That is a poor home for the load-bearing
// semantics, so the lowering functions live in the pure `BindingContext.swift`
// instead and are exercised here — on Windows and Linux too, where the renderer
// compiles to nothing.
//
// What matters most is the UNMAPPED value. A per-surface copy of a
// lookup-with-fallback is exactly how two hosts come to disagree about a value
// the tone map does not mention, and it is the case a parity test misses most
// easily — so it is asserted directly rather than inferred from a rendered view.

import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class GridCellLoweringTests: XCTestCase {
  private func row(_ pairs: [String: JSON]) -> JSON { .object(pairs) }

  // ── The tone lowering ──────────────────────────────────────────────────────

  private let shipmentTones: [String: ToneVariant] = [
    "On time": .success, "Delayed": .warning, "Cancelled": .critical,
  ]

  func testAMappedValueTakesItsDeclaredTone() {
    for (value, want) in [("On time", ToneVariant.success), ("Delayed", .warning)] {
      let lowered = tonedPillOf(row(["status": .string(value)]), "status", shipmentTones, .subdued)
      XCTAssertEqual(lowered.label, value)
      XCTAssertEqual(lowered.tone, want)
    }
  }

  func testAnUnmappedValueTakesTheDefaultTone() {
    // The case that matters: the map does not mention "Unknown", so the pill
    // takes `defaultTone` — NOT the identity, and not the first map entry.
    let lowered = tonedPillOf(
      row(["status": .string("Unknown")]), "status", shipmentTones, .subdued)
    XCTAssertEqual(lowered.label, "Unknown")
    XCTAssertEqual(lowered.tone, .subdued)
  }

  func testAnAbsentDefaultFallsBackToTheIdentityTone() {
    let lowered = tonedPillOf(
      row(["status": .string("Unknown")]), "status", shipmentTones, .default)
    XCTAssertEqual(lowered.tone, .default)
  }

  func testARowMissingTheNamedFieldLowersToAnEmptyDefaultPill() {
    // Never a crash and never a dropped cell: the projection is empty, so the
    // label is empty and the tone is the default.
    let lowered = tonedPillOf(row(["other": .string("x")]), "status", shipmentTones, .subdued)
    XCTAssertEqual(lowered.label, "")
    XCTAssertEqual(lowered.tone, .subdued)
  }

  func testTheToneMapKeysOnTheRawDatumNotAFormattedOne() {
    // A numeric field keys by its canonical text, through the module's one
    // number printer — `3`, not `3.0`, so an author's map entry matches.
    let lowered = tonedPillOf(row(["level": .number(3)]), "level", ["3": .critical], .default)
    XCTAssertEqual(lowered.label, "3")
    XCTAssertEqual(lowered.tone, .critical)
  }

  // ── The row-field projection ───────────────────────────────────────────────

  func testProjectionCoversTheScalarJSONShapes() {
    let r = row([
      "s": .string("text"), "b": .bool(true), "n": .number(42), "f": .number(1.5),
      "z": .null, "arr": .array([]), "obj": .object([:]),
    ])
    XCTAssertEqual(projectRowFieldString(r, "s"), "text")
    XCTAssertEqual(projectRowFieldString(r, "b"), "true")
    XCTAssertEqual(projectRowFieldString(r, "n"), "42")
    XCTAssertEqual(projectRowFieldString(r, "f"), "1.5")
    // Structural and null values have no cell text — empty, never "null".
    for key in ["z", "arr", "obj", "absent"] {
      XCTAssertEqual(projectRowFieldString(r, key), "", key)
    }
  }

  func testProjectionOfANonObjectRowIsEmpty() {
    XCTAssertEqual(projectRowFieldString(.array([]), "any"), "")
  }

  // ── CellFormat ─────────────────────────────────────────────────────────────

  func testFormatsApplyToNumericText() {
    XCTAssertEqual(formatCellValue("1234.5", .currency(code: "GBP")), "GBP 1234.50")
    XCTAssertEqual(formatCellValue("0.07", .percent(decimals: 0)), "7%")
    XCTAssertEqual(formatCellValue("3.14159", .number(decimals: 2)), "3.14")
  }

  func testNonNumericTextIsLeftAlone() {
    // A currency format over a string cell must not mangle it — the format is a
    // numeric rendering, and there is no number here.
    XCTAssertEqual(formatCellValue("Delayed", .currency(code: "GBP")), "Delayed")
    XCTAssertEqual(formatCellValue("", .number(decimals: 2)), "")
  }

  // ── The rows channel ───────────────────────────────────────────────────────

  func testAnAbsentRowsEntryReadsAsNotResolvedNotEmpty() {
    // The distinction the whole seam exists to preserve: nothing seeded means
    // "not yet", which renders as loading — never as an empty grid.
    XCTAssertEqual(BindingContext.empty.rows(for: "grid"), .notResolved)
    let seeded = BindingContext(rows: ["grid": .rows([])])
    XCTAssertEqual(seeded.rows(for: "grid"), .rows([]))
  }
}
