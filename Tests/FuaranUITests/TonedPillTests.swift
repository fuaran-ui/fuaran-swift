// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Phase 750 — `CellKindErased.tonedPill`, the first cell kind this projection
// carries a PAYLOAD for. Every other one is defined by a closure, which never rides
// the wire, so the case name was the whole of the information; a declared tone rule
// is data, so it has to be carried.
//
// The corpus render-coverage harness proves the canonical fixture decodes without
// hitting a fallback arm. This file pins what that harness cannot see — a coverage
// walk asks "did it decode", not "did it decode CORRECTLY":
//
//   * all three tone-map field aliases, including `tones`, which no fixture uses;
//   * the §16 `Pill`-tagged shorthand, and that a closure `Pill` is left alone;
//   * the §3.6 tone aliases inside the map, and the omit rule on `default`;
//   * the didactic refusal — that it names the offending key and teaches the seven
//     legal tones, which is the entire reason that reject fixture exists.

import XCTest

@testable import FuaranUI

final class TonedPillTests: XCTestCase {
  /// The smallest grid document carrying `kind` as its one column's cell kind.
  private func column(_ kind: String) -> String {
    """
    {"id":"g1","kind":{"$type":"DataGrid","columns":[{"field":"status","kind":\(kind),\
    "label":"Status"}],"source":{"$type":"Static","value":"<opaque>"}}}
    """
  }

  private func cellKind(_ kind: String, file: StaticString = #filePath, line: UInt = #line) throws
    -> CellKindErased
  {
    let node = try RenderProjection.decodeNode(column(kind))
    guard case .dataGrid(let spec) = node.kind, let col = spec.columns.first else {
      XCTFail("expected a one-column DataGrid", file: file, line: line)
      throw FuaranDecodeError(code: .wrongType, path: "$", message: "not a grid")
    }
    return col.kind
  }

  // ── The tone-map field aliases (§3.6) ──────────────────────────────────────

  func testEveryToneMapAliasNormalisesToMap() throws {
    for alias in ["map", "toneMap", "tones"] {
      let kind = try cellKind(
        #"{"$type":"TonedPill","field":"status","\#(alias)":{"Delayed":"Warning"}}"#)
      XCTAssertEqual(
        kind, .tonedPill(field: "status", map: ["Delayed": .warning], defaultTone: .default),
        "alias \(alias)")
    }
  }

  func testCanonicalToneMapWinsOverAnAlias() throws {
    let kind = try cellKind(
      #"{"$type":"TonedPill","field":"status","map":{"Delayed":"Warning"},"toneMap":{"Delayed":"Critical"}}"#
    )
    XCTAssertEqual(
      kind, .tonedPill(field: "status", map: ["Delayed": .warning], defaultTone: .default))
  }

  // ── The §16 `Pill`-tagged shorthand ────────────────────────────────────────

  func testPillTagCarryingAToneMapCoercesToTonedPill() throws {
    let kind = try cellKind(#"{"$type":"Pill","field":"status","map":{"Delayed":"Warning"}}"#)
    XCTAssertEqual(
      kind, .tonedPill(field: "status", map: ["Delayed": .warning], defaultTone: .default))
  }

  func testAClosurePillIsUntouched() throws {
    // The coercion keys off the tone map, so an ordinary closure `Pill` — which can
    // never carry one — still decodes to the bare case.
    let kind = try cellKind(#"{"$type":"Pill","labelFn":"<closure>","toneFn":"<closure>"}"#)
    XCTAssertEqual(kind, .pill)
  }

  // ── The Phase 460 omit rule + the §3.6 tone aliases ────────────────────────

  func testDefaultToneRestoresTheIdentityOnAbsenceAndOnAnAlias() throws {
    let absent = try cellKind(#"{"$type":"TonedPill","field":"s","map":{"a":"Info"}}"#)
    XCTAssertEqual(absent, .tonedPill(field: "s", map: ["a": .info], defaultTone: .default))
    // `Neutral` aliases to `Default`, which is the identity.
    let aliased = try cellKind(
      #"{"$type":"TonedPill","default":"Neutral","field":"s","map":{"a":"Info"}}"#)
    XCTAssertEqual(aliased, .tonedPill(field: "s", map: ["a": .info], defaultTone: .default))
  }

  func testARealDefaultToneSurvives() throws {
    let kind = try cellKind(
      #"{"$type":"TonedPill","default":"Subdued","field":"s","map":{"a":"Info"}}"#)
    XCTAssertEqual(kind, .tonedPill(field: "s", map: ["a": .info], defaultTone: .subdued))
  }

  func testToneAliasesApplyInsideTheMap() throws {
    let kind = try cellKind(
      #"{"$type":"TonedPill","field":"s","map":{"a":"Danger","b":"Positive","c":"Neutral"}}"#)
    XCTAssertEqual(
      kind,
      .tonedPill(
        field: "s", map: ["a": .critical, "b": .success, "c": .default], defaultTone: .default))
  }

  // ── The didactic refusal ───────────────────────────────────────────────────

  func testTonedPillRefusals() throws {
    let cases: [(kind: String, code: FuaranDecodeError.Code, path: String)] = [
      (
        #"{"$type":"TonedPill","field":"status","map":{"Delayed":"Urgent"}}"#, .unknownDuCase,
        "$.kind.columns[0].kind.map.Delayed"
      ),
      (
        #"{"$type":"TonedPill","field":"s","map":{"a":7}}"#, .wrongType,
        "$.kind.columns[0].kind.map.a"
      ),
      (
        #"{"$type":"TonedPill","map":{"a":"Info"}}"#, .missingField,
        "$.kind.columns[0].kind.field"
      ),
      (#"{"$type":"TonedPill","field":"s"}"#, .missingField, "$.kind.columns[0].kind.map"),
    ]
    for c in cases {
      XCTAssertThrowsError(try RenderProjection.decodeNode(column(c.kind)), c.kind) { error in
        guard let e = error as? FuaranDecodeError else {
          return XCTFail("expected a FuaranDecodeError, got \(error)")
        }
        XCTAssertEqual(e.code, c.code, c.kind)
        XCTAssertEqual(e.path, c.path, c.kind)
      }
    }
  }

  func testAnUnknownToneMapValueIsRefusedDidactically() throws {
    XCTAssertThrowsError(
      try RenderProjection.decodeNode(
        column(#"{"$type":"TonedPill","field":"status","map":{"Delayed":"Urgent"}}"#))
    ) { error in
      guard let e = error as? FuaranDecodeError else {
        return XCTFail("expected a FuaranDecodeError, got \(error)")
      }
      // The offending KEY and value, in the terms the author wrote them — "one of
      // your tones is wrong" is not actionable when the map has nine entries.
      XCTAssertTrue(e.message.contains("Delayed"), e.message)
      XCTAssertTrue(e.message.contains("Urgent"), e.message)
      // All seven legal names, so the author can fix it from the message alone.
      for tone in ToneVariant.allCases {
        XCTAssertTrue(e.message.contains(tone.rawValue), "\(e.message) omits \(tone.rawValue)")
      }
    }
  }
}
