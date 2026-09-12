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

    // A Badge whose label is a scalar Transform (count of a 2-row embedded
    // frame). The decode-only surface cannot evaluate the Transform itself — the
    // core's resolved projection (Phase 650) folds it to the literal "2".
    private let scalarTransformTree = #"""
      {"id":"root","kind":{"$type":"Box","children":[{"id":"count-badge","kind":{"$type":"Badge","label":{"$type":"Bound","binding":{"$type":"Transform","pipeline":[{"$type":"groupBy","aggs":[{"fn":"count","name":"n","of":"id"}],"keys":[]}],"source":{"columns":{"id":{"values":["A","B"]}},"schema":[{"name":"id","type":"string"}]}}},"variant":"Neutral"}}],"layout":{"$type":"Auto"},"role":"Group"}}
      """#

    // A grid whose rows come from an embedded Transform — the shape a decode-only
    // surface cannot resolve for itself, plus a sibling of a kind with no row
    // source so the NO_ROW_SOURCE arm has a real node to be asked about.
    private let boundGridTree = #"""
      {"id":"root","kind":{"$type":"Box","children":[{"id":"shipments","kind":{"$type":"DataGrid","columns":[{"field":"status","kind":{"$type":"TonedPill","default":"Subdued","field":"status","map":{"Delayed":"Warning"}},"label":"Status"}],"rowKeyField":"status","source":{"$type":"Transform","pipeline":[],"source":{"columns":{"status":{"validity":[true,true],"values":["Delayed","Other"]}},"schema":[{"name":"status","type":"string"}]}}}},{"id":"heading","kind":{"$type":"Heading","level":1,"text":"Shipments","variant":"Standard"}}],"layout":{"$type":"Auto"},"role":"Group"}}
      """#

    // A grid bound to a Query no host has fed — the unresolved case.
    private let queryGridTree = #"""
      {"id":"g","kind":{"$type":"DataGrid","columns":[],"rowKeyField":"id","source":{"$type":"Query","dependsOn":[],"name":"shipments"}}}
      """#

    /// projectResolved folds a scalar-slot Transform to the literal it evaluates
    /// to; the raw treeJSON still carries the unresolved Transform (additive).
    func testProjectResolvedFoldsScalarTransform() async throws {
      let session = try FuaranSession(treeJSON: scalarTransformTree)

      let raw = await session.treeJSON()
      XCTAssertTrue(
        raw.contains(#""$type":"Transform""#),
        "treeJSON keeps the raw Transform (the resolved projection is additive)")

      let projected = try RenderProjection.decodeNode(await session.projectResolved())
      guard case .box(let box) = projected.kind, let badge = box.children.first,
        case .badge(let spec) = badge.kind
      else { return XCTFail("expected a Box > Badge projection") }
      XCTAssertEqual(
        spec.label, .literal("2"),
        "the Badge label Transform must fold to the literal count 2")
    }

    /// The Phase 752 rows hand-off, against the live core. The premise is
    /// asserted rather than assumed: `projectResolved` still carries the raw
    /// Transform, because a resolved COLLECTION cannot ride a `Static` slot
    /// (§2 rule 11) — which is the whole reason this call exists. If a future
    /// change ever does fold rows into the tree, this fails and the seam gets
    /// revisited rather than quietly outliving its reason.
    func testResolvedRowsHandsOverWhatTheTreeCannotCarry() async throws {
      let session = try FuaranSession(treeJSON: boundGridTree)

      let projected = await session.projectResolved()
      XCTAssertTrue(
        projected.contains(#""$type":"Transform""#),
        "the resolved projection cannot carry row-context Transforms")

      guard case .rows(let rows) = await session.resolvedRows(nodeId: "shipments") else {
        return XCTFail("expected resolved rows")
      }
      XCTAssertEqual(rows.count, 2)
      XCTAssertEqual(rows.first, .object(["status": .string("Delayed")]))
    }

    /// The three outcomes stay apart across the boundary. Collapsing the middle
    /// one into zero rows is the defect this seam was shaped to prevent: it
    /// would render "no data" for "not yet".
    func testTheThreeRowOutcomesAreDistinguishable() async throws {
      let session = try FuaranSession(treeJSON: boundGridTree)
      // A real node of a kind with no row source, and an id naming nothing.
      let heading = await session.resolvedRows(nodeId: "heading")
      XCTAssertEqual(heading, .noRowSource)
      let missing = await session.resolvedRows(nodeId: "nope")
      XCTAssertEqual(missing, .noRowSource)

      // A grid bound to a Query the host has not fed yet — loading, not empty.
      let pending = try FuaranSession(treeJSON: queryGridTree)
      let unfed = await pending.resolvedRows(nodeId: "g")
      XCTAssertEqual(unfed, .notResolved)
      // Fed, it resolves — including to genuinely zero rows, the empty state.
      try await pending.setQuery(name: "shipments", valueJSON: "[]")
      let fed = await pending.resolvedRows(nodeId: "g")
      XCTAssertEqual(fed, .rows([]))
    }

    // ── Placement (Phase 833; `move` Phase 1673) ─────────────────────────────
    //
    // A drag-move EXERCISED, not merely declared in a header. The verb existed on
    // the Rust library surface from Phase 833 and was reachable from nowhere
    // else: this projection is decode-only, so without the C-ABI entry point the
    // only way to move a node from Swift was to author the ops by hand — a second
    // implementation of an algebra this core is the reference for.

    private var placementTree: String {
      #"""
      {"id":"root","kind":{"$type":"Box","children":[{"id":"left","kind":{"$type":"Box","children":[{"id":"a","kind":{"$type":"Markdown","text":"A"}},{"id":"b","kind":{"$type":"Markdown","text":"B"}}],"layout":{"$type":"Flex","direction":"Vertical","wrap":false},"role":"Group"}},{"id":"right","kind":{"$type":"Box","children":[],"layout":{"$type":"Flex","direction":"Vertical","wrap":false},"role":"Group"}}],"layout":{"$type":"Flex","direction":"Vertical","wrap":false},"role":"Group"}}
      """#
    }

    /// The ids of a Box's children, read off the session's OWN tree — so what is
    /// asserted is the tree the core holds, never a Swift-side echo of the
    /// request. Box-only, which is all the fixture above contains; a non-Box
    /// parent reads as childless and would fail the assertion loudly rather than
    /// quietly matching.
    private func childIds(_ treeJSON: String, of parentId: String) throws -> [String] {
      let root = try RenderProjection.decodeNode(treeJSON)
      func kids(_ node: Node) -> [Node] {
        if case .box(let spec) = node.kind { return spec.children }
        return []
      }
      func find(_ node: Node) -> Node? {
        if node.id == parentId { return node }
        for child in kids(node) {
          if let hit = find(child) { return hit }
        }
        return nil
      }
      guard let parent = find(root) else {
        XCTFail("no node '\(parentId)' in the session tree")
        return []
      }
      return kids(parent).map(\.id)
    }

    /// One call moves a node between containers, and the node KEEPS ITS ID — the
    /// property that separates a move from a duplicate, and the reason it cannot
    /// be spelled as place-then-remove.
    func testMoveRelocatesANodeAndKeepsItsId() async throws {
      let session = try FuaranSession(treeJSON: placementTree)
      let op = try await session.move(source: "a", parentId: "right", placement: .last)
      XCTAssertTrue(op.contains("\"MoveNode\""), "expected a MoveNode op, got: \(op)")

      let tree = await session.treeJSON()
      XCTAssertEqual(
        try childIds(tree, of: "left"), ["b"],
        "the moved node should have left its old parent")
      XCTAssertEqual(
        try childIds(tree, of: "right"), ["a"],
        "the moved node should have arrived, under its own id")
    }

    /// A move with an anchor lands in the right PLACE, not merely under the right
    /// parent — the reorder the core folds into the same call.
    func testMoveBeforeAnAnchorLandsInPosition() async throws {
      let session = try FuaranSession(treeJSON: placementTree)
      _ = try await session.move(source: "right", parentId: "left", placement: .before("b"))
      // Bound first: XCTAssert* take AUTOCLOSURES, which cannot carry an `await`.
      let tree = await session.treeJSON()
      XCTAssertEqual(try childIds(tree, of: "left"), ["a", "right", "b"])
    }

    /// A refusal is TYPED and the held tree is untouched — the pre-stated
    /// apply-side rejection a drag UI greys out on, rather than a failed apply.
    func testMoveIntoItselfIsRefusedAndChangesNothing() async throws {
      let session = try FuaranSession(treeJSON: placementTree)
      let before = await session.treeJSON()
      do {
        _ = try await session.move(source: "left", parentId: "left", placement: .last)
        XCTFail("moving a node into itself should throw")
      } catch let e as FuaranError {
        XCTAssertEqual(e.errorClass, "placement")
        XCTAssertEqual(e.code, "MoveIntoSelf")
      }
      let after = await session.treeJSON()
      XCTAssertEqual(before, after, "a refused move must change nothing")
    }

    /// The request encoder ESCAPES rather than splicing an id into JSON and
    /// hoping. An unescaped quote would close the string and the core would
    /// report a parse failure — a Swift-side defect wearing a core-side error's
    /// clothes, and indistinguishable from one until someone used an awkward id.
    func testAQuoteInANodeIdIsEscapedRatherThanBreakingTheRequest() async throws {
      let session = try FuaranSession(treeJSON: placementTree)
      do {
        _ = try await session.move(source: "no\"such", parentId: "right", placement: .last)
        XCTFail("expected a refusal for an absent node")
      } catch let e as FuaranError {
        // The core READ the document and judged its content: the id is absent.
        // Unescaped, this would have been a `request` parse error instead.
        XCTAssertEqual(e.errorClass, "placement", "got: \(e)")
        XCTAssertEqual(e.code, "NodeNotFound", "got: \(e)")
      }
    }

  #else

    func testSessionLegSkipsWhenCoreAbsent() throws {
      throw XCTSkip(
        "FuaranCore (Rust staticlib / XCFramework) not linked — the C-ABI session leg is a native-core build; skipping."
      )
    }

  #endif
}
