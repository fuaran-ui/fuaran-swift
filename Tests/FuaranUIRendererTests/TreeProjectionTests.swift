// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The `Tree` row projection (§3.6.12, Phase 1120).
//
// **Only ONE of the kind's eight render obligations has a manifest row**
// (`accessible-name-always`), and that one is asserted in `RenderObligationTests`
// where the closed vocabulary can enumerate it. The other seven are normative
// all the same — §3.6.12 states them, and §11.2 vocabulary attestation
// enumerates CASES, so a per-kind render rule that is not in the closed
// obligation vocabulary has no row to sit in. They are asserted here rather than
// left as prose, because "the manifest does not enumerate it" is not the same
// statement as "no host owes it".
//
// Every assertion below runs on every platform: the projection is outside the
// SwiftUI gate, so the rules are checked on Windows and Linux too.

import Foundation
import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class TreeProjectionTests: XCTestCase {
  /// The corpus's `nodes/tree-1.json` hierarchy.
  private func spec(
    expandedStateKey: String? = nil, selectionStateKey: String? = nil
  ) -> TreeSpec {
    TreeSpec(
      items: [
        TreeItem(
          id: "goods", label: .literal("Goods"),
          children: [
            TreeItem(id: "cocoa", label: .literal("Cocoa")),
            TreeItem(id: "yarn", label: .literal("Yarn")),
          ]),
        TreeItem(id: "ledger", label: .literal("Ledger")),
      ],
      expandedStateKey: expandedStateKey, selectionStateKey: selectionStateKey)
  }

  private func rows(
    _ spec: TreeSpec, expandedIds: Set<String>? = nil, selectedId: String? = nil
  ) -> [TreeRowPlan] {
    flattenTreeRows(treeRowPlans(spec, expandedIds: expandedIds, selectedId: selectedId))
  }

  // ── Obligation 1 — the tree pattern's positional facts ─────────────────────

  func testEveryRowCarriesItsLevelPositionAndSetSize() {
    let all = rows(spec())
    let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    XCTAssertEqual(byId["goods"]?.level, 1)
    XCTAssertEqual(byId["goods"]?.posInSet, 1)
    XCTAssertEqual(byId["goods"]?.setSize, 2, "two ROOT rows")
    XCTAssertEqual(byId["ledger"]?.posInSet, 2)

    // The child set is its own set — a projection counting the whole tree, or
    // numbering children continuously from the root, gets both of these wrong.
    XCTAssertEqual(byId["cocoa"]?.level, 2)
    XCTAssertEqual(byId["cocoa"]?.posInSet, 1)
    XCTAssertEqual(byId["cocoa"]?.setSize, 2)
    XCTAssertEqual(byId["yarn"]?.posInSet, 2)
  }

  // ── Obligation 2 — expanded on rows that HAVE children, and on no others ───

  func testTheExpandedClaimExistsOnlyWhereASubtreeDoes() {
    let all = rows(spec(expandedStateKey: "openRows"), expandedIds: ["goods"])
    let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })

    XCTAssertEqual(byId["goods"]?.expanded, true)
    // `nil` is the ABSENCE of the claim, not "closed". On a leaf the attribute
    // asserts a subtree that does not exist and assistive technology announces
    // such a row as closed — a reader told there is more when there is not.
    XCTAssertNil(byId["cocoa"]?.expanded, "a leaf makes no expansion claim at all")
    XCTAssertNil(byId["ledger"]?.expanded)
    XCTAssertEqual(byId["cocoa"]?.hasChildren, false)

    // The closed half, so an always-true projection cannot pass.
    let closed = Dictionary(
      uniqueKeysWithValues: rows(spec(expandedStateKey: "openRows"), expandedIds: []).map {
        ($0.id, $0)
      })
    XCTAssertEqual(closed["goods"]?.expanded, false)
  }

  func testATreeNamingNoExpansionKeyRendersFullyExpanded() {
    // The same reading that lets a grid honour a declared initial order while
    // offering no interactive sorting — and the only reading under which such a
    // tree shows its content at all.
    let byId = Dictionary(uniqueKeysWithValues: rows(spec()).map { ($0.id, $0) })
    XCTAssertEqual(byId["goods"]?.expanded, true)

    // And an EMPTY declared set is a different state from an absent key: a
    // document that named a key over which every row is currently closed.
    let empty = Dictionary(
      uniqueKeysWithValues: rows(spec(expandedStateKey: "k"), expandedIds: []).map { ($0.id, $0) })
    XCTAssertEqual(
      empty["goods"]?.expanded, false,
      "an empty set is not the same statement as no key — collapsing the two would make a declared, fully-closed tree indistinguishable from a static one")
  }

  // ── Obligation 3 — selected only where a selection key is named ────────────

  func testTheSelectedClaimExistsOnlyWhereTheDocumentNamedTheSlot() {
    let unnamed = rows(spec())
    XCTAssertTrue(
      unnamed.allSatisfy { $0.selected == nil },
      "a tree that never selects must not declare a selectable widget with nothing selected")

    let named = Dictionary(
      uniqueKeysWithValues: rows(spec(selectionStateKey: "sel"), selectedId: "yarn").map {
        ($0.id, $0)
      })
    XCTAssertEqual(named["yarn"]?.selected, true)
    XCTAssertEqual(
      named["cocoa"]?.selected, false,
      "…and every other row carries the claim in the negative, which is what makes the widget selectable")

    // A named key with nothing selected is still a selectable widget.
    let none = rows(spec(selectionStateKey: "sel"), selectedId: nil)
    XCTAssertTrue(none.allSatisfy { $0.selected == false })
  }

  // ── Obligation 4 — one tab stop ────────────────────────────────────────────

  func testTheWidgetHasExactlyOneTabStop() {
    // The obligation the kind EXISTS for: a composition of independently
    // focusable containers is N tab stops, and no arrangement of them produces
    // one.
    for (expanded, selected) in [
      (Set<String>?.none, String?.none),
      (Set(["goods"]), nil),
      (Set([]), nil),
      (Set(["goods"]), "yarn"),
      (Set([]), "yarn"),
    ] as [(Set<String>?, String?)] {
      let all = rows(spec(expandedStateKey: "k", selectionStateKey: "sel"),
        expandedIds: expanded, selectedId: selected)
      XCTAssertEqual(
        all.filter(\.isTabStop).count, 1,
        "exactly one row is the tab stop for expanded=\(String(describing: expanded)) selected=\(String(describing: selected))")
    }
  }

  func testTheTabStopIsTheSelectedRowWhenVisibleAndTheFirstVisibleRowOtherwise() {
    // Computed from STATE ALONE, which is what makes a server rendering and an
    // interactive host's first frame agree.
    let visible = rows(
      spec(expandedStateKey: "k", selectionStateKey: "sel"), expandedIds: ["goods"],
      selectedId: "yarn")
    XCTAssertEqual(visible.first(where: \.isTabStop)?.id, "yarn")

    // The selected row is inside a CLOSED branch, so it is not visible and
    // cannot be the tab stop — a widget whose only focus stop is hidden is one
    // a keyboard cannot enter.
    let hidden = rows(
      spec(expandedStateKey: "k", selectionStateKey: "sel"), expandedIds: [],
      selectedId: "yarn")
    XCTAssertEqual(hidden.first(where: \.isTabStop)?.id, "goods", "…so it falls to the first visible row")
  }

  func testVisibilityIsAPropertyOfTheAncestorChain() {
    XCTAssertEqual(
      visibleRowIds(spec().items, expandedIds: nil), ["goods", "cocoa", "yarn", "ledger"],
      "no key means fully expanded, so every row is visible")
    XCTAssertEqual(
      visibleRowIds(spec().items, expandedIds: []), ["goods", "ledger"],
      "a closed parent hides its whole branch, not merely its own marker")
    XCTAssertEqual(
      visibleRowIds(spec().items, expandedIds: ["goods"]), ["goods", "cocoa", "yarn", "ledger"])
  }

  // ── Obligation 8 — derive nothing else from a row ──────────────────────────

  func testExpandabilityComesFromChildrenAndFromNothingElse() {
    // No `expandable` flag exists on the wire and none is inferred here: a row
    // with children is expandable and a row without is not, whatever else it
    // carries.
    let iconOnly = TreeSpec(items: [TreeItem(id: "a", label: .literal("A"), icon: "folder")])
    let plans = flattenTreeRows(treeRowPlans(iconOnly))
    XCTAssertFalse(
      plans[0].hasChildren,
      "a folder ICON is decoration; it does not make a leaf a branch")
    XCTAssertNil(plans[0].expanded)
  }

  func testTheChildrenAreProjectedWhetherOrNotTheBranchIsOpen() {
    // Visibility is answered by `visibleRowIds`, not by pruning the plan — so a
    // surface rendering only open branches and one rendering the whole structure
    // read the same projection, and there is no second, shadow notion of
    // openness for them to disagree about.
    let closed = treeRowPlans(spec(expandedStateKey: "k"), expandedIds: [])
    XCTAssertEqual(closed[0].children.count, 2, "the closed branch still carries its rows")
    XCTAssertEqual(closed[0].expanded, false)
  }

  // ── Resolution ─────────────────────────────────────────────────────────────

  func testLabelsAreResolvedThroughTheCallersResolver() {
    let bound = TreeSpec(items: [TreeItem(id: "a", label: .i18n(key: "row.a", args: [:]))])
    let plans = flattenTreeRows(
      treeRowPlans(bound, resolveText: { _ in "Resolved" }))
    XCTAssertEqual(
      plans[0].label, "Resolved",
      "a TextSource's bound and i18n arms resolve at render time, so the projection takes a resolver rather than reading a literal")
  }
}
