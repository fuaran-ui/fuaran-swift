// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The accessibility projection, driven by the SHARED CORPUS.
//
// `AccessibilityProjectionTests` next door asserts the mapping decisions against
// traits built here, so it measures this surface against this surface's own idea
// of the wire trait. The shared corpus's accessibility family is the oracle every
// surface answers to: all six slots, both role classes (a named lower-case
// `region` and a deliberately-cased custom `doc-pageFooter`), both binding forms
// (Static and State), all three `liveRegion` tokens, and the trait on both an
// ordinary wrapper kind and the three kinds whose body carries the semantics.
//
// This is a RENDER-COVERAGE leg, not a byte-parity one: there is no canonical
// encoder here, so what is certified is that the decoded trait projects to the
// declared value AND to the declared DROP SET. The drop set is asserted exactly
// rather than as a superset — a slot that becomes mappable must move between the
// two lists and turn this red, which is what makes the drop a decision rather
// than an omission (the policy in the repo's own working notes).

import Foundation
import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class AccessibilityCorpusTests: XCTestCase {
  /// `<repo>/Tests/FuaranUIRendererTests/…` → `<repo>/../wire-format-fixtures/nodes`.
  private static var nodesDir: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // FuaranUIRendererTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // fuaran-swift
      .deletingLastPathComponent()  // the workspace tree
      .appendingPathComponent("wire-format-fixtures")
      .appendingPathComponent("nodes")
  }

  private func fixture(_ id: String) throws -> Node {
    let url = Self.nodesDir.appendingPathComponent("\(id).json")
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
    }
    return try RenderProjection.decodeNode(String(contentsOf: url, encoding: .utf8))
  }

  private func project(_ id: String) throws -> AccessibilityProjection {
    accessibilityProjection(try fixture(id).accessibility, BindingContext.empty)
  }

  // ── The ordinary wrapper kind, all six slots at once ───────────────────────

  func testAllSlotsWrapperProjectsItsNameAndReportsThreeDrops() throws {
    let p = try project("a11y-wrapper-all-slots")

    XCTAssertEqual(p.label, "Channel performance summary")
    // `region` is a landmark role with no SwiftUI trait that means what it
    // means, so it drops rather than being approximated.
    XCTAssertEqual(p.traits, [.updatesFrequently], "liveRegion polite carries the declarative half")
    // `hidden` is an explicit Static FALSE on the wire — distinct from omitted,
    // and it must not hide the node.
    XCTAssertFalse(p.hidden)
    XCTAssertEqual(p.unmapped, [.labelledBy, .describedBy, .role], "in wire-slot order")
  }

  // ── The State forms ────────────────────────────────────────────────────────

  func testStateBoundTraitResolvesThroughItsDeclaredDefaults() throws {
    let p = try project("a11y-wrapper-state-bound")

    // An unwritten `State` resolves to its declared `defaultValue` — the same
    // law the HTML tiers apply, so the accessible name is not lost at the render
    // floor just because no host state was seeded.
    XCTAssertEqual(p.label, "Site footer")
    // `doc-pageFooter` is a CUSTOM role whose meaning this platform cannot know.
    // It drops — and the fact that its CASE survived decode is what the corpus
    // fixture exists to pin, so assert the wire value rather than the drop alone.
    XCTAssertEqual(try fixture("a11y-wrapper-state-bound").accessibility?.role, "doc-pageFooter")
    XCTAssertEqual(p.unmapped, [.role])
    // `off` maps EXACTLY — it asserts "do not announce", which is the platform
    // default, so its faithful projection is the ABSENCE of the trait rather
    // than a drop. Asserting both halves keeps that distinction live.
    XCTAssertEqual(p.traits, [])
    XCTAssertFalse(p.hidden, "the State default is false")
  }

  // ── The announcement pair ──────────────────────────────────────────────────

  func testAlertAssertiveCarriesTheLiveTraitAndDropsTheRole() throws {
    let p = try project("a11y-alert-assertive")

    XCTAssertNil(p.label)
    XCTAssertEqual(p.traits, [.updatesFrequently])
    // The politeness DISTINCTION is lost — `polite` and `assertive` both carry
    // the same declarative trait. That is the stated partial mapping, and both
    // fixtures projecting identically here is the evidence for it.
    XCTAssertEqual(p.unmapped, [.role], "`alert` has no SwiftUI trait")
  }

  // ── The three kinds whose body carries the semantics ───────────────────────

  func testLinkAccessibleNameOverridesTheVisibleText() throws {
    let p = try project("a11y-link-labelled")

    XCTAssertEqual(p.label, "Read the 2026 annual report (PDF)")
    XCTAssertEqual(p.traits, [])
    XCTAssertEqual(p.unmapped, [], "no role slot, so nothing to drop")
  }

  func testButtonRoleMapsToTheButtonTrait() throws {
    let p = try project("a11y-button-named")

    XCTAssertEqual(p.label, "Refresh revenue figures")
    XCTAssertEqual(p.traits, [.button])
    XCTAssertEqual(p.unmapped, [])
  }

  func testDecorativeImageHidesFromTheAccessibilityTree() throws {
    let p = try project("a11y-image-decorative")

    // The slot whose absence went unnoticed on two hosts for weeks: `hidden`
    // Static TRUE on the empty-alt decorative shape.
    XCTAssertTrue(p.hidden)
    XCTAssertNil(p.label)
    XCTAssertEqual(p.unmapped, [])
  }

  // ── The family itself ──────────────────────────────────────────────────────

  func testEveryTraitBearingFixtureProjectsSomethingOrReportsWhyNot() throws {
    // A leg that silently enumerated nothing would be a gate that checked
    // nothing. Every fixture in the family must either apply a modifier or
    // report a drop — a trait that did neither would have decoded and vanished,
    // which is the exact defect the drop set exists to make impossible.
    let family = [
      "a11y-wrapper-all-slots", "a11y-wrapper-state-bound", "a11y-alert-assertive",
      "a11y-link-labelled", "a11y-button-named", "a11y-image-decorative",
    ]
    XCTAssertEqual(family.count, 6)
    for id in family {
      let p = try project(id)
      XCTAssertFalse(
        p.isEmpty && p.unmapped.isEmpty,
        "\(id): the trait decoded and projected nothing, reporting nothing")
    }
  }
}
