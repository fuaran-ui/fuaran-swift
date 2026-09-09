// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Phase 1548 — `FileUploadSpec.maxBytes` / `.maxFiles` (WIRE_FORMAT.md §3.6.23),
// the decode leg.
//
// The shared corpus already carries the four refusals and the two accept
// vectors, and `CorpusTests` runs them; these are the CORRECTED TWINS beside
// each refusal. A reject vector on its own proves only that SOMETHING was
// refused: a decoder that refused every `maxBytes` outright would pass all four
// and be wrong in the more expensive direction, since it would reject documents
// every other host accepts. Asserting the twin decodes — the same document with
// the one member corrected — is what makes the pair say where the boundary is.
//
// Corpus-free by construction, so they run in a standalone checkout too.

import XCTest

@testable import FuaranUI

final class UploadCeilingDecodeTests: XCTestCase {
  /// One upload document with an arbitrary ceiling clause spliced in.
  private func upload(_ clause: String, multiple: Bool = false) -> String {
    let acceptList = multiple ? #"["image/*"]"# : #"["application/pdf"]"#
    return """
      {"id":"up","kind":{"$type":"FileUpload","accept":\(acceptList),\
      "label":"Upload",\(clause)"multiple":\(multiple),"onSelect":"<closure>"}}
      """
  }

  private func spec(_ json: String, file: StaticString = #filePath, line: UInt = #line) throws
    -> FileUploadSpec
  {
    let node = try RenderProjection.decodeNode(json)
    guard case .fileUpload(let s) = node.kind else {
      XCTFail("expected .fileUpload, got \(node.kind.typeName)", file: file, line: line)
      throw FuaranDecodeError(code: .wrongType, path: "$", message: "not an upload")
    }
    return s
  }

  private func refuses(
    _ json: String, path: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try RenderProjection.decodeNode(json), file: file, line: line) { error in
      guard let e = error as? FuaranDecodeError else {
        return XCTFail("expected a typed decode error, got \(error)", file: file, line: line)
      }
      XCTAssertEqual(e.code, .wrongType, file: file, line: line)
      XCTAssertEqual(e.path, path, file: file, line: line)
    }
  }

  // ── Absence is the pre-1548 control, exactly ───────────────────────────────

  func testAnUploadDeclaringNeitherCeilingCarriesNeither() throws {
    // The polarity `nodes/upload-1.json` pins: every document written before this
    // revision is byte-identical and means what it always meant.
    let s = try spec(upload(""))
    XCTAssertNil(s.maxBytes)
    XCTAssertNil(s.maxFiles)
  }

  // ── The accept vectors' shapes, carried apart ──────────────────────────────

  func testAByteCeilingDecodesWithoutImplyingACountCeiling() throws {
    let s = try spec(upload(#""maxBytes":5242880,"#))
    XCTAssertEqual(s.maxBytes, 5_242_880)
    XCTAssertNil(s.maxFiles, "a declared maxBytes must not conjure a maxFiles")
  }

  func testACountCeilingDecodesWithoutImplyingAByteCeiling() throws {
    let s = try spec(upload(#""maxFiles":3,"#, multiple: true))
    XCTAssertEqual(s.maxFiles, 3)
    XCTAssertNil(s.maxBytes, "a declared maxFiles must not conjure a maxBytes")
  }

  func testTheLargestDeclarableCeilingIsSection71sSlotWidth() throws {
    // §7.1 — every typed integer slot is a signed 32-bit integer, so this is the
    // largest ceiling expressible, and one above it is a refusal rather than a
    // number silently wrapped into one the author did not write.
    let s = try spec(upload(#""maxBytes":2147483647,"#))
    XCTAssertEqual(s.maxBytes, 2_147_483_647)
    refuses(upload(#""maxBytes":2147483648,"#), path: "$.kind.maxBytes")
  }

  // ── The four refusals, each beside its corrected twin ──────────────────────

  func testAByteCeilingWrittenAsAStringIsRefusedAndItsTwinDecodes() throws {
    // `reject-upload-maxbytes-nonint`. A host that read the digits out of the
    // string would accept a bound no other host could.
    refuses(upload(#""maxBytes":"5242880","#), path: "$.kind.maxBytes")
    XCTAssertEqual(try spec(upload(#""maxBytes":5242880,"#)).maxBytes, 5_242_880)
  }

  func testAZeroByteCeilingIsRefusedAndItsTwinDecodes() throws {
    // `reject-upload-maxbytes-nonpositive`. A ceiling of zero is not a small
    // ceiling; it is an upload that can accept no file at all.
    refuses(upload(#""maxBytes":0,"#), path: "$.kind.maxBytes")
    refuses(upload(#""maxBytes":-1,"#), path: "$.kind.maxBytes")
    XCTAssertEqual(try spec(upload(#""maxBytes":1,"#)).maxBytes, 1)
  }

  func testAFractionalCountCeilingIsRefusedAndItsTwinDecodes() throws {
    // `reject-upload-maxfiles-nonint`. §7.1 retired truncation at every typed
    // integer slot; a host reading `3` would enforce a ceiling the document does
    // not state, and the reader would find out by losing a file.
    refuses(upload(#""maxFiles":3.5,"#, multiple: true), path: "$.kind.maxFiles")
    XCTAssertEqual(try spec(upload(#""maxFiles":3,"#, multiple: true)).maxFiles, 3)
    // …and `3.0` is the same integer spelled with a fraction-free decimal point,
    // which §7.1 accepts. Asserted because it is the boundary the refusal above
    // could otherwise be read as forbidding.
    XCTAssertEqual(try spec(upload(#""maxFiles":3.0,"#, multiple: true)).maxFiles, 3)
  }

  func testAZeroCountCeilingIsRefusedAndItsTwinDecodes() throws {
    // `reject-upload-maxfiles-nonpositive`. A multiple upload admitting zero
    // files is a control with no reachable selection.
    refuses(upload(#""maxFiles":0,"#, multiple: true), path: "$.kind.maxFiles")
    XCTAssertEqual(try spec(upload(#""maxFiles":1,"#, multiple: true)).maxFiles, 1)
  }

  // ── The inert pairing, which is NOT a refusal ──────────────────────────────

  func testACountCeilingBesideASingleFileUploadIsInertRatherThanRefused() throws {
    // §3.6.23 — a single-file upload admits one file by construction, so a
    // `maxFiles` beside `"multiple":false` does nothing. Deliberately NOT
    // refused: the bytes describe a control every host renders identically with
    // or without the member, so there is nothing for a decoder to be right
    // about, and a host refusing it would reject documents every other host
    // accepts.
    let s = try spec(upload(#""maxFiles":3,"#, multiple: false))
    XCTAssertEqual(s.maxFiles, 3)
    XCTAssertFalse(s.multiple)
  }
}
