// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Phase 541 interaction round-trip gate. A `FuaranHost` wraps a session and
// re-projects its tree as observable state; the state-holder behaviour is proven
// at the host level (SwiftUI control taps need XCUITest, out of scope for a unit
// leg): dispatch/apply → session → `tree` state changes; a reject sets
// `lastError` and keeps the last-good tree; a form-control edit writes through
// the `$state` channel.
//
// The pure leg runs a native-free fake session (the `swift` job). The gated leg
// (`#if FUARAN_CORE_AVAILABLE`) drives a live `FuaranSession` — a real `EditNode`
// through the Rust validator re-projects, and a bad op surfaces a typed reject —
// exercised in the `swift-core` job.

import XCTest

#if canImport(SwiftUI)

  import FuaranUI

  @testable import FuaranUIRenderer

  @MainActor
  final class InteractionTests: XCTestCase {
    private func md(_ text: String) -> String {
      #"{"id":"root","kind":{"$type":"Markdown","text":{"$type":"Literal","text":"\#(text)"}}}"#
    }

    private func text(_ node: Node) -> String {
      guard case .markdown(let m) = node.kind, case .literal(let t) = m.text else { return "?" }
      return t
    }

    func testApplyingAnOpReprojects() async throws {
      let session = InteractionFakeSession(md("Hello"))
      let host = try await FuaranHost.start(session: session)
      XCTAssertEqual(text(host.tree), "Hello")

      await host.applyOp(md("World"))
      XCTAssertEqual(text(host.tree), "World")
      XCTAssertNil(host.lastError, "a successful apply clears lastError")
    }

    func testRejectSurfacesTypedErrorAndKeepsLastGoodTree() async throws {
      let session = InteractionFakeSession(md("Stable"))
      let host = try await FuaranHost.start(session: session)

      await host.applyOp(#"{"__reject__":true}"#)
      XCTAssertEqual((host.lastError as? InteractionReject)?.code, "VALIDATION_REJECT")
      XCTAssertEqual(text(host.tree), "Stable", "the last-good tree is retained across a reject")
    }

    func testDispatchSetStateWritesThroughTheStateChannel() async throws {
      let session = InteractionFakeSession(md("x"))
      let host = try await FuaranHost.start(session: session)

      await host.dispatch(.setState(key: "name", value: .string("Ada"), valueFrom: nil))
      let writes = await session.writes
      XCTAssertTrue(writes.contains { $0.0 == "name" && $0.1.contains("Ada") }, "saw \(writes)")
      XCTAssertNil(host.lastError)
    }

    func testWriteBackWritesThroughTheStateChannel() async throws {
      let session = InteractionFakeSession(md("x"))
      let host = try await FuaranHost.start(session: session)

      await host.writeBack(stateKey: "email", value: .string("ada@example.com"))
      let writes = await session.writes
      XCTAssertTrue(
        writes.contains { $0.0 == "email" && $0.1.contains("ada@example.com") }, "saw \(writes)")
    }

    func testStateKeyOfExtractsStateSlot() {
      XCTAssertEqual(stateKeyOf(.state(key: "k", defaultValue: .stringOpt(nil))), "k")
      XCTAssertNil(stateKeyOf(.query(name: "q", dependsOn: nil)))
      XCTAssertNil(stateKeyOf(nil))
    }

    #if FUARAN_CORE_AVAILABLE

      /// The live round-trip: a real `EditNode` through the Rust session
      /// re-projects, and a bad op surfaces a typed reject with the tree retained.
      func testLiveSessionRoundTrip() async throws {
        let tree =
          #"{"id":"h","kind":{"$type":"Heading","level":2,"text":{"$type":"Literal","text":"Hello"},"variant":"Standard"}}"#
        let session = try FuaranSession(treeJSON: tree)
        let host = try await FuaranHost.start(session: session)
        guard case .heading(let s0) = host.tree.kind else { return XCTFail("expected heading") }
        XCTAssertEqual(s0.level, 2)

        let edit =
          #"{"$type":"EditNode","target":"h","newKind":{"$type":"Heading","level":3,"text":{"$type":"Literal","text":"Hello"},"variant":"Standard"}}"#
        await host.applyOp(edit)
        XCTAssertNil(host.lastError, "a valid EditNode should not error")
        guard case .heading(let s1) = host.tree.kind else {
          return XCTFail("expected heading after edit")
        }
        XCTAssertEqual(s1.level, 3, "the round-trip should re-project the raised heading level")

        await host.applyOp(#"{"$type":"RemoveNode","target":"does-not-exist"}"#)
        XCTAssertNotNil(host.lastError, "a bad op surfaces a typed reject")
        guard case .heading = host.tree.kind else { return XCTFail("tree retained across reject") }
      }

    #endif
  }

  struct InteractionReject: Error { let code: String }

  /// A native-free `FuaranTreeSession` for the renderer interaction tests. An
  /// `actor` (the single-owner, `async` contract by construction). `applyOp`
  /// treats a `__reject__` marker as a validator reject and otherwise adopts the
  /// op payload as the replacement tree JSON.
  actor InteractionFakeSession: FuaranTreeSession {
    private var current: String
    private(set) var writes: [(String, String)] = []

    init(_ initial: String) { self.current = initial }

    func treeJSON() -> String { current }
    func projectResolved() -> String { current }

    func applyOp(_ opJSON: String) throws {
      if opJSON.contains("__reject__") { throw InteractionReject(code: "VALIDATION_REJECT") }
      current = opJSON
    }

    func setState(key: String, valueJSON: String) throws { writes.append((key, valueJSON)) }
    func setFilter(name: String, valueJSON: String) throws {
      writes.append(("filter:\(name)", valueJSON))
    }
    func setQuery(name: String, valueJSON: String) throws {
      writes.append(("query:\(name)", valueJSON))
    }

    // No evaluator here, so this fake cannot resolve rows. `.notResolved` is the
    // honest answer — and the safe one, since it renders as a loading surface
    // rather than asserting an emptiness the fake never established.
    func resolvedRows(nodeId: String) -> ResolvedRows { .notResolved }
  }

#else

  final class InteractionTests: XCTestCase {
    func testInteractionLegSkipsWhenSwiftUIAbsent() throws {
      throw XCTSkip("SwiftUI not available — the interaction host is a SwiftUI leg; skipping.")
    }
  }

#endif
