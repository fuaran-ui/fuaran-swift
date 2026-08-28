// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// `Binding.State` slot seeding — WIRE_FORMAT.md 24.4, and the answer to the
// question this surface exists to make explicit: is the rule INHERITED from the
// core, or does it need an arm here?
//
// THE ANSWER IS BOTH, ALONG A SEAM, AND IT IS WORTH STATING RATHER THAN
// ASSUMING EITHER HALF.
//
//   * The DERIVED VALUE is inherited. This surface carries no evaluator: a
//     scalar `Transform` reaches it already folded by the core's
//     `project_resolved`, and a row-context one arrives out of band through
//     `resolved_rows`. Both read the core's own binding sources, so the core's
//     seeding pass is what fills the slot. There is no seeding arm here and
//     there must not be one — a second pass over the same tree would be a
//     second opinion about a value the core has already decided.
//   * The DECODE is NOT inherited. This surface has its own render-projection
//     decoder, and it refused `nodes/shared-source-seeded-pair` outright:
//     `"defaultValue": []` in a Transform source slot reached the row-major
//     pivot as an empty array, which "declares no schema to infer". The fixture
//     failed to decode across two corpus tests and the whole rule was
//     unreachable here whatever the core did. That arm is this surface's own,
//     and it had to be widened here.
//
// So an inheritance claim made without measuring would have been half right and
// entirely untestable. The tests below measure both halves.

import Foundation
import XCTest

@testable import FuaranUI

final class StateSeedingTests: XCTestCase {

  // ── The decode half: this surface's OWN arm ────────────────────────────────

  /// WIRE_FORMAT.md 16 — an EMPTY carried feed is the EMPTY TABLE, not a
  /// malformed one. Corpus-independent, so it runs on a standalone clone.
  func testAnEmptyTransformSourceFeedDecodesAsTheEmptyTable() throws {
    let doc = #"""
      {"id":"b","kind":{"$type":"Badge","label":{"$type":"Bound","binding":{"$type":"Transform","pipeline":[{"$type":"groupBy","aggs":[{"fn":"count","name":"n","of":"team"}],"keys":[]}],"source":{"$type":"State","defaultValue":[],"key":"members"}}},"variant":"Info"}}
      """#
    let node = try RenderProjection.decodeNode(doc)
    guard case .badge(let spec) = node.kind,
      case .bound(let binding) = spec.label,
      case .transform(_, _, let source) = binding
    else {
      return XCTFail("expected a Badge whose label is a bound Transform, got \(node.kind.typeName)")
    }
    guard case .embedded(let schema, let columns) = source else {
      return XCTFail("expected an embedded source, got \(source)")
    }
    XCTAssertTrue(schema.isEmpty, "an empty feed declares an empty schema, not a refusal")
    XCTAssertTrue(columns.isEmpty)
  }

  /// The go-red half of the arm above: widening it must not have widened the
  /// RAGGED case with it. A feed whose rows are not objects has no column set to
  /// take and is still refused — the refusal this decoder is meant to keep.
  func testARaggedTransformSourceFeedIsStillRefused() {
    let doc = #"""
      {"id":"b","kind":{"$type":"Badge","label":{"$type":"Bound","binding":{"$type":"Transform","pipeline":[{"$type":"groupBy","aggs":[{"fn":"count","name":"n","of":"team"}],"keys":[]}],"source":{"$type":"State","defaultValue":[1,2],"key":"members"}}},"variant":"Info"}}
      """#
    XCTAssertThrowsError(try RenderProjection.decodeNode(doc)) { error in
      guard let e = error as? FuaranDecodeError else {
        return XCTFail("expected a FuaranDecodeError, got \(error)")
      }
      XCTAssertEqual(e.code, .wrongType)
    }
  }

  // ── The resolution half: INHERITED from the core ───────────────────────────

  #if FUARAN_CORE_AVAILABLE

    /// The corpus fixture, resolved through the live core. This is the
    /// inheritance claim made falsifiable: the value is produced by the core's
    /// seeding pass and consumed by this surface's decoder, with nothing between
    /// them that this surface could have got right by accident.
    ///
    /// `2` is what the reference tiers render for this fixture — the grid
    /// declares two rows under `$state.members` and the badge's Transform,
    /// which carries no data of its own, derives its count over them.
    func testTheSeededPairResolvesThroughTheCoreToTheDeclaredCount() async throws {
      let wire = try seededPairWire()
      let session = try FuaranSession(treeJSON: wire)

      let projected = try RenderProjection.decodeNode(await session.projectResolved())
      XCTAssertEqual(
        badgeLabel(of: projected), .literal("2"),
        "the core's seeding pass did not reach this surface's projection")

      // The grid's rows come from the SAME slot, out of band.
      guard case .rows(let rows) = await session.resolvedRows(nodeId: "member-grid") else {
        return XCTFail("expected the grid's declared rows")
      }
      XCTAssertEqual(rows.count, 2)
    }

    /// The go-red half. An assertion nobody has watched fail is a claim about
    /// the author's confidence — so a WRITE through the session's own channel
    /// must move the derived value, which also pins 24.4's precedence
    /// (a written value wins over a seed) from this side of the seam.
    func testAWriteThroughTheSessionOverridesTheSeed() async throws {
      let session = try FuaranSession(treeJSON: try seededPairWire())
      try await session.setState(key: "members", valueJSON: #"[{"team":"Only"}]"#)

      let projected = try RenderProjection.decodeNode(await session.projectResolved())
      XCTAssertEqual(
        badgeLabel(of: projected), .literal("1"),
        "a written value did not override the seed — the assertion above would pass on a core that ignores the slot"
      )
    }

    private func seededPairWire() throws -> String {
      guard let corpus = CorpusTests.corpusDir() else {
        throw XCTSkip("wire-format-fixtures corpus not found alongside the repo")
      }
      let file = corpus.appendingPathComponent("nodes/shared-source-seeded-pair.json")
      return try String(contentsOf: file, encoding: .utf8)
    }

    /// The Info badge's label, dug out of the fixture's Box. Narrow on purpose:
    /// a projection that stopped carrying the badge fails here rather than
    /// matching something else.
    private func badgeLabel(of node: Node) -> TextSource? {
      guard case .box(let spec) = node.kind else { return nil }
      for child in spec.children {
        if case .badge(let badge) = child.kind { return badge.label }
      }
      return nil
    }

  #endif
}
