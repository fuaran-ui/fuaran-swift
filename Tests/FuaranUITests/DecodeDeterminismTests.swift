// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// WIRE_FORMAT.md §20 decode determinism — the two rows this surface answered
// differently, and the corrected twin beside each.
//
// The corpus pins every §20 row with a reject fixture and `CorpusTests` runs
// them. What the corpus cannot carry is the twin: a refusal-only family passes
// on a decoder that refuses everything, and one of the two defects here is
// precisely a case where refusing more would have looked like a fix.
//
// Both are rows that change what a document MEANS rather than whether it is
// accepted, which is why neither was visible from inside this host. A repeated
// member took the LAST occurrence, where the reference host took the first. And
// a high surrogate escape combined with ANY following `\u` escape, so
// `\uD83DA` produced a scalar nobody wrote out of an emoji lead and a capital A.

import Foundation
import XCTest

@testable import FuaranUI

final class DecodeDeterminismTests: XCTestCase {
  /// The decode's verdict as a bare string, so a test asserts on the CODE rather
  /// than merely on "it threw".
  private func verdict(_ json: String) -> String {
    do {
      _ = try RenderProjection.decodeNode(json)
      return "ACCEPTED"
    } catch let e as FuaranDecodeError {
      return e.code.rawValue
    } catch {
      return "UNTYPED(\(error))"
    }
  }

  private func markdown(_ text: String) -> String {
    "{\"id\":\"markdown-1\",\"kind\":{\"$type\":\"Markdown\",\"text\":\"\(text)\"}}"
  }

  // ── §20.2 row 1: a repeated member ────────────────────────────────────────

  func testARepeatedMemberIsRefused() {
    XCTAssertEqual(
      verdict("{\"id\":\"markdown-1\",\"id\":\"smuggled\",\"kind\":{\"$type\":\"Markdown\",\"text\":\"x\"}}"),
      "INVALID_JSON")
  }

  func testARepeatedMemberIsRefusedInANestedObjectToo() {
    // The row binds every object, not the root one. A check written at the entry
    // point alone passes the case above and leaves the class open.
    XCTAssertEqual(
      verdict("{\"id\":\"n\",\"kind\":{\"$type\":\"Markdown\",\"text\":\"x\",\"text\":\"y\"}}"),
      "INVALID_JSON")
  }

  func testTheSameKeyInSiblingObjectsIsNotARepeat() {
    // Non-vacuity: two objects each carrying "id" is the ordinary shape of every
    // tree, and a key set that was not scoped to its own object would refuse it.
    let doc =
      "{\"id\":\"n\",\"kind\":{\"$type\":\"Box\",\"role\":\"Group\","
      + "\"layout\":{\"$type\":\"Flex\",\"direction\":\"Vertical\",\"wrap\":false},"
      + "\"children\":[{\"id\":\"a\",\"kind\":{\"$type\":\"Markdown\",\"text\":\"x\"}},"
      + "{\"id\":\"b\",\"kind\":{\"$type\":\"Markdown\",\"text\":\"y\"}}]}}"
    XCTAssertEqual(verdict(doc), "ACCEPTED")
  }

  // ── §20.2 row 6: unpaired surrogates ──────────────────────────────────────

  func testAHighSurrogateFollowedByANonLowEscapeIsRefused() {
    // THE defect this file exists for. The parser required only that the next two
    // scalars were `\u` and then combined whatever quad followed, so this produced
    // U+1F441 — a scalar the author never wrote — with no error anywhere.
    XCTAssertEqual(verdict(markdown("\\uD83DA")), "INVALID_JSON")
    XCTAssertEqual(verdict(markdown("\\uD83D\\u0041")), "INVALID_JSON")
    XCTAssertEqual(verdict(markdown("\\uD83D\\uD83D")), "INVALID_JSON")
  }

  func testALoneHighSurrogateIsRefused() {
    XCTAssertEqual(verdict(markdown("Updated \\uD83D hourly.")), "INVALID_JSON")
  }

  func testALoneLowSurrogateIsRefused() {
    // Refused because `Unicode.Scalar(0xDC00)` is nil — a surrogate is not a
    // Unicode scalar value. Asserted rather than assumed: it is exactly the kind
    // of coverage that disappears in a later refactor of the escape reader.
    XCTAssertEqual(verdict(markdown("Updated \\uDE00 hourly.")), "INVALID_JSON")
  }

  func testASplitPairIsRefused() {
    // Both halves present but separated. A host that counts surrogates rather
    // than pairing them adjacently reassembles a scalar nobody wrote.
    XCTAssertEqual(verdict(markdown("\\uD83D Updated \\uDE00 hourly.")), "INVALID_JSON")
  }

  func testAWellFormedSurrogatePairStillDecodes() {
    // The corrected twin, and the one that matters most: this row's fix TIGHTENS
    // the escape reader, so refusing every escape would have looked like a fix.
    XCTAssertEqual(verdict(markdown("Updated \\uD83D\\uDE00 hourly.")), "ACCEPTED")
  }

  func testAnAstralCharacterWrittenLiterallyStillDecodes() {
    XCTAssertEqual(verdict(markdown("Updated \u{1F600} hourly.")), "ACCEPTED")
  }

  func testAnOrdinaryBMPEscapeStillDecodes() {
    XCTAssertEqual(verdict(markdown("caf\\u00e9")), "ACCEPTED")
  }
}
