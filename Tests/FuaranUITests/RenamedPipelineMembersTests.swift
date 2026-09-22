// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Phase 1827 — the renamed transform-pipeline members on the Swift surface.
//
// Substrate 0.28.0 renamed a `project` step's `cols` to `columns`, and a sort
// key's — and so a `window` step's frame-ordering entry's — `col` to `column`.
// The pre-rename spellings stay decode aliases; a step or key carrying BOTH is
// refused, which is a STRICTER rule than the §3.6 lenient aliases beside it
// (those resolve to the canonical name). See `Decode.reqRenamed` for why.
//
// Why this file exists when the corpus harness already sweeps every fixture.
// `CorpusTests.testEveryNodeFixtureDecodes` and
// `CorpusTests.testEveryRejectFixtureIsRefused` quantify over whatever the
// corpus happens to hold, so they would go GREEN AND EMPTY if these fixtures
// were ever renamed or dropped — coverage that can vanish silently is not
// coverage of this rule. The tests below NAME the fixtures, so
// an absent one fails rather than disappears, and they assert the decoded
// SEMANTICS (which column is projected, which column is sorted on) rather than
// only that a decode succeeded. The quiet failure this phase exists to prevent
// — an empty projection, an unsorted grid — is precisely a successful decode.

import Foundation
import XCTest

@testable import FuaranUI

final class RenamedPipelineMembersTests: XCTestCase {

  // ── The rule, read straight off the decode site ───────────────────────────

  /// A pipeline path deep enough to carry the corpus's recorded reject prefix.
  private static let stepPath = "$.kind.source.pipeline[0]"

  private func step(_ json: String) throws -> TransformStep {
    try Decode.transformStep(Self.stepPath, try JSON.parse(json))
  }

  private func key(_ json: String) throws -> SortKey {
    try Decode.sortKey("\(Self.stepPath).by[0]", try JSON.parse(json))
  }

  /// Asserts the decode refused with the corpus's recorded code, at a path the
  /// corpus's recorded prefix covers.
  private func expectWrongType(
    _ body: @autoclosure () throws -> Any, _ what: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    do {
      _ = try body()
      XCTFail(
        "\(what): decode ACCEPTED a step carrying both spellings. Accepting either silently "
          + "projects or sorts by a column the author may never have meant.",
        file: file, line: line)
    } catch let e as FuaranDecodeError {
      XCTAssertEqual(
        e.code, .wrongType, "\(what): wrong code — \(e.path): \(e.message)",
        file: file, line: line)
      XCTAssertTrue(
        e.path.hasPrefix("$.kind.source.pipeline"),
        "\(what): refused at \(e.path), which the corpus's recorded "
          + "`$.kind.source.pipeline` prefix does not cover",
        file: file, line: line)
    } catch {
      XCTFail("\(what): refused with a non-decode error: \(error)", file: file, line: line)
    }
  }

  private static let pair = ColPair(a: "dept", b: "team")

  func testProjectReadsTheCanonicalColumns() throws {
    XCTAssertEqual(
      try step(#"{"$type":"project","columns":[{"a":"dept","b":"team"}]}"#),
      .project(cols: [Self.pair]))
  }

  func testProjectReadsTheLegacyColsAsAnAlias() throws {
    XCTAssertEqual(
      try step(#"{"$type":"project","cols":[{"a":"dept","b":"team"}]}"#),
      .project(cols: [Self.pair]))
  }

  func testProjectCarryingBothSpellingsIsRefused() {
    expectWrongType(
      try self.step(
        #"{"$type":"project","columns":[{"a":"dept","b":"dept"}],"cols":[{"a":"dept","b":"team"}]}"#
      ),
      "project step")
  }

  func testProjectCarryingNeitherSpellingNamesTheCanonicalOne() {
    // The absence message must teach the CURRENT vocabulary, not the one the
    // author is being moved off.
    do {
      _ = try step(#"{"$type":"project"}"#)
      XCTFail("a project step with no column list decoded")
    } catch let e as FuaranDecodeError {
      XCTAssertEqual(e.code, .missingField)
      XCTAssertTrue(
        e.path.hasSuffix(".columns"), "absence reported at \(e.path) — expected the canonical name")
    } catch {
      XCTFail("unexpected error: \(error)")
    }
  }

  func testSortKeyReadsTheCanonicalColumn() throws {
    XCTAssertEqual(
      try key(#"{"column":"salary","dir":"desc"}"#), SortKey(col: "salary", dir: .desc))
  }

  func testSortKeyReadsTheLegacyColAsAnAlias() throws {
    XCTAssertEqual(try key(#"{"col":"salary","dir":"desc"}"#), SortKey(col: "salary", dir: .desc))
  }

  func testSortKeyCarryingBothSpellingsIsRefused() {
    expectWrongType(
      try self.key(#"{"column":"dept","col":"salary","dir":"asc"}"#), "sort key")
  }

  /// The `window` step's `orderBy` entries go through the same reader, so the
  /// rename covers the frame ordering too. Pinned at the STEP level rather than
  /// trusting the shared call site, because "one reader serves both" is exactly
  /// the kind of claim a later refactor breaks quietly.
  func testWindowFrameOrderingTakesTheRenameToo() throws {
    let s = try step(
      #"{"$type":"window","as":"running","fn":"cumulSum","of":"salary","#
        + #""orderBy":[{"column":"salary","dir":"asc"}],"partitionBy":["dept"]}"#)
    guard case .window(_, let orderBy, _, _, _) = s else {
      return XCTFail("expected a window step, got \(s)")
    }
    XCTAssertEqual(orderBy, [SortKey(col: "salary", dir: .asc)])
  }

  func testWindowFrameOrderingRefusesBothSpellings() {
    expectWrongType(
      try self.step(
        #"{"$type":"window","as":"running","fn":"cumulSum","of":"salary","#
          + #""orderBy":[{"column":"dept","col":"salary","dir":"asc"}],"partitionBy":["dept"]}"#),
      "window orderBy entry")
  }

  // ── What the rename does NOT touch ────────────────────────────────────────

  /// `col` as an EXPRESSION DISCRIMINATOR is not a member name and does not move.
  func testTheColExpressionTagIsUntouched() throws {
    let s = try step(#"{"$type":"derive","name":"pay","expr":{"$type":"col","name":"salary"}}"#)
    XCTAssertEqual(s, .derive(name: "pay", expr: .col(name: "salary")))
  }

  /// A `groupBy` aggregation entry reads `column` as a lenient alias for `of` —
  /// a DIFFERENT slot that happens to share a spelling with the renamed sort-key
  /// member. Swept while confirming the read sites, and deliberately left alone:
  /// folding it into the rename would refuse documents the specification accepts.
  func testTheAggregationColumnAliasIsUntouched() throws {
    let s = try step(
      #"{"$type":"groupBy","by":["dept"],"aggs":[{"as":"total","op":"sum","column":"salary"}]}"#)
    XCTAssertEqual(s, .groupBy(keys: ["dept"], aggs: [Agg(name: "total", fn: .sum, of: "salary")]))
  }

  // ── The corpus, by name ───────────────────────────────────────────────────

  /// The rename's oracle fixtures entered the corpus AFTER the revision
  /// `corpus-pin.json` records, and this repository's gates certify against
  /// that pin (CI checks the corpus out at it). So the two tests below can run
  /// against a corpus that predates their own oracle, and the honest report of
  /// that is a SKIP naming the pin — never a pass, which would claim a rule was
  /// proven by a corpus that cannot state it, and never a failure, which would
  /// blame a checkout for being exactly where the pin aims it.
  ///
  /// Nothing has to remember to re-enable them: moving the pin is a reviewed act
  /// (`dev-scripts/corpus-pin.ps1 -Write`, which lands in the same change-set as
  /// the decoder work adopting the new vocabulary), and the instant it lands
  /// these fixtures are present and both tests run. The skip is keyed to the
  /// fixture's own presence rather than to a recorded version, so there is no
  /// second fact to keep in step.
  ///
  /// The rule itself is NOT gated on this: the corpus-independent tests above
  /// prove the canonical read, the alias read and the both-present refusal at
  /// every position, and they run everywhere.
  private func requireRenameOracle(_ corpus: URL, _ name: String) throws -> String {
    let url = corpus.appendingPathComponent(name)
    guard let text = try? String(contentsOf: url, encoding: .utf8) else {
      throw XCTSkip(
        "\(name) is absent from the corpus at \(corpus.path). It is a Phase 1821 fixture and "
          + "post-dates the revision corpus-pin.json records, so this checkout is pinned behind "
          + "its own oracle — run `dev-scripts/corpus-pin.ps1` to see the distance. Skipped "
          + "rather than passed: a corpus that cannot state this rule has not proven it.")
    }
    return text
  }

  /// Every node fixture Phase 1821 re-emitted in the new vocabulary, named so
  /// that one going missing is a failure rather than a silent loss of coverage.
  static let reEmittedNodeFixtures = [
    "nodes/a11y-wrapper-transform-label.json",
    "nodes/grid-transform.json",
    "nodes/master-detail-preselected-second-row.json",
    "nodes/scalar-transform-composition.json",
    "nodes/switch-on-transform-scalar.json",
  ]

  func testTheReEmittedNodeFixturesDecode() throws {
    let corpus = try CorpusTests.requireCorpus()
    for name in Self.reEmittedNodeFixtures {
      let url = corpus.appendingPathComponent(name)
      guard let text = try? String(contentsOf: url, encoding: .utf8) else {
        XCTFail(
          "\(name) is absent from the corpus at \(corpus.path). Phase 1821 re-emitted it in the "
            + "`columns` / `column` vocabulary; if it moved, correct this list rather than "
            + "letting the rename lose its coverage.")
        continue
      }
      XCTAssertNoThrow(
        try RenderProjection.decodeNode(text),
        "\(name) — a fixture in the post-rename vocabulary failed to decode")
    }
  }

  /// The acceptance criterion, stated as an equality: the legacy spellings and
  /// the canonical ones must decode to the SAME model. The corpus's `.expected`
  /// companion IS the canonical re-spelling of the input beside it, so this
  /// compares the two vocabularies of one document rather than a document with
  /// a hand-written expectation.
  func testTheLegacySpellingsDecodeToTheSameModelAsTheCanonicalOnes() throws {
    let corpus = try CorpusTests.requireCorpus()
    let legacy = try requireRenameOracle(
      corpus, "lenient/lenient-transform-column-member-legacy.json")
    let canonical = try requireRenameOracle(
      corpus, "lenient/lenient-transform-column-member-legacy.expected.json")
    let a = try RenderProjection.decodeNode(legacy)
    let b = try RenderProjection.decodeNode(canonical)
    XCTAssertEqual(
      a, b,
      "a tree in the pre-rename vocabulary decoded DIFFERENTLY from the same tree in the "
        + "canonical one — the aliases are not transparent")
  }

  /// The two reject fixtures, by name. `CorpusTests` sweeps the whole reject
  /// family; this pins that these two are IN it and refused for the recorded
  /// reason, so the rule cannot be lost by a fixture being dropped.
  func testTheBothPresentRejectFixturesAreRefused() throws {
    let corpus = try CorpusTests.requireCorpus()
    for name in [
      "reject/reject-transform-project-columns-and-cols.json",
      "reject/reject-transform-sort-key-column-and-col.json",
    ] {
      let text = try requireRenameOracle(corpus, name)
      expectWrongType(try RenderProjection.decodeNode(text), name)
    }
  }
}
