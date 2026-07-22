// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Phase 650 — render-coverage-shaped assertions that the native surface renders
// RESOLVED compute values. A decode-only surface cannot itself evaluate a
// `Binding.Transform`, so the Rust reference core resolves it and hands back a
// resolved projection (`FuaranSession.projectResolved`); the surface decodes that
// and renders it. Here we drive a live session over the shared corpus fixtures,
// decode the projection with the shipped Phase-538 decoder, and resolve each
// scalar slot through the real render-side `BindingContext` — the very arm the
// SwiftUI spine calls — asserting the evaluated value, not byte parity.
//
// These are NOT SwiftUI-guarded: `BindingContext` is the pure (platform-neutral)
// resolver, so this leg runs in the Windows `swift test` job (where the core is
// linked). The SwiftUI view spine that consumes the same resolved values is
// exercised by the macOS CI render-coverage job. Core-gated (FUARAN_CORE_AVAILABLE)
// + corpus-gated (skips on a standalone checkout).

import XCTest

#if FUARAN_CORE_AVAILABLE

  import Foundation

  @testable import FuaranUI
  @testable import FuaranUIRenderer

  final class ResolvedProjectionTests: XCTestCase {
    /// Locate the shared corpus: `<repo>/Tests/FuaranUIRendererTests/…` →
    /// `<repo>/../wire-format-fixtures`.
    static func corpusNodesDir() -> URL? {
      let here = URL(fileURLWithPath: #filePath)
      let repoRoot =
        here
        .deletingLastPathComponent()  // FuaranUIRendererTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // fuaran-swift
      let nodes =
        repoRoot
        .deletingLastPathComponent()
        .appendingPathComponent("wire-format-fixtures")
        .appendingPathComponent("nodes")
      var isDir: ObjCBool = false
      let exists = FileManager.default.fileExists(atPath: nodes.path, isDirectory: &isDir)
      return exists && isDir.boolValue ? nodes : nil
    }

    func loadFixture(_ id: String) -> String? {
      guard let dir = Self.corpusNodesDir() else { return nil }
      return try? String(
        contentsOf: dir.appendingPathComponent("\(id).json"), encoding: .utf8)
    }

    /// Depth-first search for a node by id (recurses `Box` children — sufficient
    /// for the two fixtures under test).
    func findNode(_ node: Node, _ id: String) -> Node? {
      if node.id == id { return node }
      if case .box(let box) = node.kind {
        for child in box.children {
          if let found = findNode(child, id) { return found }
        }
      }
      return nil
    }

    /// The projected tree of a fixture, decoded through the shipped Phase-538
    /// decoder — the resolved projection a real render consumes.
    func projectedTree(_ fixtureId: String) async throws -> Node? {
      guard let raw = loadFixture(fixtureId) else { return nil }
      let session = try FuaranSession(treeJSON: raw)
      return try RenderProjection.decodeNode(await session.projectResolved())
    }

    /// scalar-transform-composition: the Badge label resolves the critical count
    /// (2, a global-aggregate scalar Transform) and the Callout body resolves the
    /// param-defaulted row-field lookup — both through the render BindingContext.
    func testScalarTransformCompositionRendersResolvedValues() async throws {
      guard let tree = try await projectedTree("scalar-transform-composition") else {
        throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
      }
      let ctx = BindingContext.empty

      guard let badge = findNode(tree, "critical-count-badge"),
        case .badge(let badgeSpec) = badge.kind
      else { return XCTFail("fixture is missing the critical-count-badge") }
      XCTAssertEqual(
        ctx.resolveText(badgeSpec.label), "2",
        "the Badge label must render the resolved critical count 2 (not empty)")

      guard let callout = findNode(tree, "sla-warning"),
        case .callout(let calloutSpec) = callout.kind
      else { return XCTFail("fixture is missing the sla-warning callout") }
      XCTAssertEqual(
        ctx.resolveText(calloutSpec.body), "TCK-2041 breaches SLA in 2 hours",
        "the Callout body must render the defaulted row's resolved alert text")
    }

    /// master-detail-preselected: the detail Fact renders TCK-2041 via the seeded
    /// Selection default (left intact by the projection, resolved by the surface).
    func testMasterDetailPreselectedRendersResolvedFact() async throws {
      guard let tree = try await projectedTree("master-detail-preselected") else {
        throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
      }
      guard let fact = findNode(tree, "detail-ticket"), case .fact(let factSpec) = fact.kind
      else { return XCTFail("fixture is missing the detail-ticket fact") }
      XCTAssertEqual(
        BindingContext.empty.resolveText(factSpec.value), "TCK-2041",
        "the detail Fact must render the preselected ticket id")
    }
  }

#else

  final class ResolvedProjectionTests: XCTestCase {
    func testResolvedProjectionLegSkipsWhenCoreAbsent() throws {
      throw XCTSkip(
        "FuaranCore (Rust staticlib / XCFramework) not linked — the resolved-projection leg is a native-core build; skipping."
      )
    }
  }

#endif
