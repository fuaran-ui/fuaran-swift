// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Escape-TEXT builders for the decoder fuzz leg, and the one reason they are a
// separate file rather than four lines at the top of `DecoderFuzzTests.swift`.
//
// The fuzz leg's most productive alphabet entries are the six-character JSON
// escape SEQUENCES — a backslash, a `u`, and four hex digits — because those are
// what the decoder's unescape path actually consumes. Writing them as source
// literals is a standing hazard in every direction: a Swift interpolated string
// turns `\u{...}` into the character, a raw string does not but looks identical
// at a glance, and any tool between an author and the file (an editor's
// normaliser, a copy through a rendered buffer, a generator) can quietly resolve
// one into the character it denotes. That failure is SILENT and it inverts the
// test: the harness then feeds the decoder a lone-surrogate CHARACTER — which a
// Swift `String` cannot even hold, so what it really feeds is U+FFFD — instead of
// the escape text whose handling is under test, and every assertion still passes.
//
// It is not hypothetical here: it happened once while this leg was being written,
// and the tell was a NUL byte in the source file (from a NUL-escape
// literal that had been resolved into the character it denotes), which made git classify the file as binary.
//
// So the escapes are BUILT, from code points, and no literal `\u` sequence
// appears anywhere in this leg's source. A build cannot resolve what is not
// written down, and `theEscapeBuildersProduceEscapeTEXT` below pins that the
// builders return text rather than characters — the one assertion that keeps the
// rest of the leg honest.

import XCTest

@testable import FuaranUI

/// A single REVERSE SOLIDUS character, from its code point.
let fuzzBackslash = "\u{5C}"

/// The six-character TEXT of a JSON `\u` escape — never the scalar it denotes.
func fuzzEsc(_ hex: String) -> String { fuzzBackslash + "u" + hex }

/// A two-character JSON escape's TEXT: `fuzzEsc2("n")` is a backslash then `n`.
func fuzzEsc2(_ c: String) -> String { fuzzBackslash + c }

/// A one-member JSON document whose `a` member carries `body` verbatim. Escape
/// text passes through untouched, which is the whole point.
func fuzzDoc(_ body: String) -> String { "{\"a\":\"" + body + "\"}" }

/// A single CHARACTER from its code point — the deliberate opposite of
/// ``fuzzEsc(_:)``, and written this way for the same reason: the hostile-character
/// alphabet and the decoded-value expectations both need real scalars, and a
/// source literal spelling one is the same standing hazard read from the other
/// end. An unassigned or surrogate code point has no scalar and yields `"?"`,
/// which is inert in every alphabet it appears in.
func fuzzChar(_ v: UInt32) -> String { Unicode.Scalar(v).map(String.init) ?? "?" }

final class DecoderFuzzEscapeBuilderTests: XCTestCase {
  /// The pin under the note above. Each builder must return TEXT whose first
  /// scalar is a backslash and whose length is the escape's length — never the
  /// one-scalar character the escape denotes.
  func testTheEscapeBuildersProduceEscapeTEXT() throws {
    XCTAssertEqual(Array(fuzzBackslash.unicodeScalars).map { $0.value }, [0x5C])

    let high = fuzzEsc("D83D")
    XCTAssertEqual(high.unicodeScalars.count, 6, "an escape must be six characters of text")
    XCTAssertEqual(
      Array(high.unicodeScalars).map { $0.value },
      [0x5C, 0x75, 0x44, 0x38, 0x33, 0x44])  // `\` `u` `D` `8` `3` `D`

    // The case the note is really about: a lone surrogate has no scalar, so if
    // this ever became "the character" it would silently be U+FFFD.
    let lone = fuzzEsc("DC00")
    XCTAssertFalse(
      lone.unicodeScalars.contains { $0.value == 0xFFFD },
      "a lone-surrogate escape resolved into a replacement character — the source was mangled")

    XCTAssertEqual(fuzzEsc2("n").unicodeScalars.count, 2)
    XCTAssertEqual(fuzzDoc(fuzzEsc("0041")), "{\"a\":\"" + fuzzBackslash + "u0041\"}")

    // And the round trip that proves the builders address the decoder's unescape
    // path at all: six characters of text in, one scalar out.
    guard case .object(let o) = try JSON.parse(fuzzDoc(fuzzEsc("0041"))),
      case .string(let s)? = o["a"]
    else { return XCTFail("the built document did not parse as an object with an `a` string") }
    XCTAssertEqual(s, "A")
  }
}
