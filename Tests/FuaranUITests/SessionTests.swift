// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The C-ABI session round-trip: seed a `FuaranSession` from a fixture tree →
// apply a TreeOp through the session → read back tree_json → re-project with the
// Phase 538 decoder → assert the expected native model shape. Exercises the live
// Rust reference core end-to-end. Skips cleanly when the native core is not
// linked (the FUARAN_CORE_AVAILABLE flag is unset — e.g. a machine without the
// Rust staticlib / XCFramework leg).

import XCTest

@testable import FuaranUI

final class SessionTests: XCTestCase {
  #if FUARAN_CORE_AVAILABLE

    private let headingTree = #"""
      {"id":"h","kind":{"$type":"Heading","level":2,"text":{"$type":"Literal","text":"Hello"},"variant":"Standard"}}
      """#

    /// new → tree_json → decode: the seeded tree round-trips through the core and
    /// re-projects into the sealed model.
    func testNewReadRoundTrip() async throws {
      let session = try FuaranSession(treeJSON: headingTree)
      let json = await session.treeJSON()
      let node = try RenderProjection.decodeNode(json)
      XCTAssertEqual(node.id, "h")
      guard case .heading(let spec) = node.kind else {
        return XCTFail("expected .heading, got \(node.kind.typeName)")
      }
      XCTAssertEqual(spec.level, 2)
      XCTAssertEqual(spec.text, .literal("Hello"))
    }

    /// Apply an `EditNode` TreeOp through the session, then observe the mutation
    /// by reading tree_json back and decoding it.
    func testApplyEditNodeMutatesTree() async throws {
      let session = try FuaranSession(treeJSON: headingTree)
      let op = #"""
        {"$type":"EditNode","target":"h","newKind":{"$type":"Heading","level":3,"text":{"$type":"Literal","text":"Hello"},"variant":"Standard"}}
        """#
      try await session.applyOp(op)
      let node = try RenderProjection.decodeNode(await session.treeJSON())
      guard case .heading(let spec) = node.kind else { return XCTFail("expected heading") }
      XCTAssertEqual(spec.level, 3, "EditNode should have raised the heading level to 3")
    }

    /// A structurally-valid but non-applicable op (unknown target) surfaces a
    /// typed `FuaranError` with the canonical code — no silent-nil path.
    func testApplyBadOpThrowsTypedError() async throws {
      let session = try FuaranSession(treeJSON: headingTree)
      let op = #"""
        {"$type":"RemoveNode","target":"does-not-exist"}
        """#
      do {
        try await session.applyOp(op)
        XCTFail("expected applyOp to throw for an unknown target")
      } catch let e as FuaranError {
        XCTAssertFalse(e.code.isEmpty)
      }
    }

    /// A malformed tree fails `session_new`; the failure surfaces as a thrown
    /// `FuaranError` (the core's last-error envelope), never a nil session.
    func testInvalidTreeThrowsOnOpen() {
      XCTAssertThrowsError(try FuaranSession(treeJSON: "{ not json")) { error in
        XCTAssertTrue(error is FuaranError, "expected FuaranError, got \(type(of: error))")
      }
    }

    /// The session renders its tree to a non-empty HTML fragment.
    func testRenderProducesHtml() async throws {
      let session = try FuaranSession(treeJSON: headingTree)
      let html = await session.render()
      XCTAssertFalse(html.isEmpty, "render() should produce a non-empty HTML fragment")
      XCTAssertTrue(html.contains("Hello"), "rendered HTML should contain the heading text")
    }

  #else

    func testSessionLegSkipsWhenCoreAbsent() throws {
      throw XCTSkip(
        "FuaranCore (Rust staticlib / XCFramework) not linked — the C-ABI session leg is a native-core build; skipping."
      )
    }

  #endif
}
