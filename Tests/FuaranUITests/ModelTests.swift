// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Focused unit checks over the sealed model + render-projection decoder that do
// not depend on the shared corpus (so they run even in a standalone checkout).

import XCTest

@testable import FuaranUI

final class ModelTests: XCTestCase {
  func testHeadingDecodesToTypedShape() throws {
    let json = #"""
      {"id":"heading-1","kind":{"$type":"Heading","level":2,"text":{"$type":"Literal","text":"Channel performance"},"variant":"Standard"}}
      """#
    let node = try RenderProjection.decodeNode(json)
    XCTAssertEqual(node.id, "heading-1")
    guard case .heading(let spec) = node.kind else {
      return XCTFail("expected .heading, got \(node.kind.typeName)")
    }
    XCTAssertEqual(spec.level, 2)
    XCTAssertEqual(spec.text, .literal("Channel performance"))
    XCTAssertEqual(spec.variant, .standard)
    XCTAssertEqual(node.kind.category, .display)
  }

  func testBareStringTextShorthandDecodes() throws {
    // §16 shorthand: Markdown.text may be a bare JSON string.
    let json = #"{"id":"m","kind":{"$type":"Markdown","text":"hello **world**"}}"#
    let node = try RenderProjection.decodeNode(json)
    guard case .markdown(let spec) = node.kind else { return XCTFail("expected markdown") }
    XCTAssertEqual(spec.text, .literal("hello **world**"))
  }

  func testLegacyCardUpgradesToBox() throws {
    let json = #"{"id":"c","kind":{"$type":"Card","children":[],"heading":"Title"}}"#
    let node = try RenderProjection.decodeNode(json)
    guard case .box(let spec) = node.kind else { return XCTFail("expected box") }
    XCTAssertEqual(spec.role, .card)
    XCTAssertEqual(node.kind.typeName, "Box")
  }

  func testUnknownKindHardRefuses() {
    let json = #"{"id":"x","kind":{"$type":"Hologram"}}"#
    XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
      guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
      XCTAssertEqual(e.code, .wrongNodeKind)
    }
  }

  func testEmptyIdRejected() {
    let json = #"{"id":"","kind":{"$type":"Markdown","text":"x"}}"#
    XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
      XCTAssertEqual((error as? FuaranDecodeError)?.code, .emptyNodeId)
    }
  }

  func testMissingFieldReported() {
    // Heading requires `level`.
    let json = #"{"id":"h","kind":{"$type":"Heading","text":"x","variant":"Standard"}}"#
    XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
      let e = error as? FuaranDecodeError
      XCTAssertEqual(e?.code, .missingField)
      XCTAssertEqual(e?.path, "$.kind.level")
    }
  }

  func testStyleAndDefaultsRoundTrip() throws {
    let json = #"""
      {"id":"n","kind":{"$type":"Markdown","text":"x"},"style":{"emphasis":"Loud","tone":"Brand","weight":"Standard","role":"Data","voice":"Display"}}
      """#
    let node = try RenderProjection.decodeNode(json)
    XCTAssertEqual(node.style.emphasis, .loud)
    XCTAssertEqual(node.style.tone, .brand)
    XCTAssertEqual(node.style.role, .data)
    XCTAssertEqual(node.style.voice, .display)
  }
}
