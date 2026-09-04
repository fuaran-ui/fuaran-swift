// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The tooltip trait's render projection (§3.1, Phase 1112).
//
// **`render-fidelity.json` carries no row for this**, and that is structural
// rather than an omission: the trait is a FIELD on the node envelope, not a
// kind, and §11.2 vocabulary attestation enumerates CASES. So there is no
// manifest checker to register and no closed-vocabulary id to key off — which
// makes this file the whole of this surface's answer, and the reason it asserts
// the declined obligations as loudly as the honoured ones.
//
// The specification is explicit that these are render obligations and not wire
// shape ("Not byte-compared"), so the corpus pins that the slot round-trips and
// nothing more. A surface can decode all three tooltip fixtures perfectly and
// honour none of this.

import Foundation
import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class TooltipProjectionTests: XCTestCase {

  // ── Obligation 5 — emit NOTHING when the hint resolves to nothing ──────────

  func testAHintResolvingToNothingProjectsNothing() {
    // The one obligation of the six a surface fails by writing the OBVIOUS code
    // (`if node.tooltip != nil`). Advertising a description that is not there is
    // worse than silence, so absence, empty and whitespace all project nothing —
    // and the whitespace case is the one a nil-check misses.
    XCTAssertNil(tooltipProjection(resolvedHint: nil))
    XCTAssertNil(tooltipProjection(resolvedHint: ""))
    XCTAssertNil(tooltipProjection(resolvedHint: "   "))
    XCTAssertNil(tooltipProjection(resolvedHint: "\n\t "))

    // The allow twin: without it a projection that emitted nothing EVER would
    // pass every assertion above.
    XCTAssertEqual(tooltipProjection(resolvedHint: "Takes about a minute.")?.hint, "Takes about a minute.")
  }

  func testEmptinessIsDecidedAfterResolutionNotBefore() {
    // A `TextSource`'s bound and i18n arms resolve only at render time, so
    // deciding emptiness on the SLOT would suppress a hint that resolves to text
    // and emit one that resolves to nothing — both directions wrong.
    let node = Node(
      id: "n", kind: .markdown(MarkdownSpec(text: .literal("Body"))),
      tooltip: .i18n(key: "hint.key", args: [:]))

    XCTAssertEqual(
      tooltipProjection(node, resolveText: { _ in "Resolved hint" })?.hint, "Resolved hint")
    XCTAssertNil(
      tooltipProjection(node, resolveText: { _ in "  " }),
      "a slot that IS present but resolves to whitespace projects nothing")
  }

  // ── The rule that must not be got wrong ────────────────────────────────────

  func testTheHintIsADescriptionAndNeverAName() {
    // Structural rather than behavioural, and deliberately so: there is no path
    // from this projection to an accessible LABEL. An icon-only control needs
    // both slots saying different things, so a surface that conflated them would
    // leave such a control with two competing names and no description.
    let projection = tooltipProjection(resolvedHint: "Exports the rows currently shown.")
    XCTAssertNotNil(projection)

    // The projection's whole surface is the hint plus two declined claims — no
    // label field exists for an arm to reach for. If one is ever added, this
    // assertion is what should be revisited rather than quietly extended.
    let mirror = Mirror(reflecting: projection!)
    let names = Set(mirror.children.compactMap(\.label))
    XCTAssertEqual(
      names, ["hint", "focusStopClaimed", "mergedDescribedBy"],
      "the projection carries no name-shaped field at all — the separation is by construction, not by discipline")
  }

  // ── The two DECLINED claims, asserted rather than left silent ──────────────

  func testTheFocusStopGuaranteeIsDeclinedAndSaysSo() {
    // Obligation 2 asks a host to place the description on the element that
    // takes keyboard focus, ENSURING such an element exists. This surface's
    // render floor gives most kinds no focus stop, and synthesising one around
    // every hinted node would rewrite a tree's tab order to satisfy a
    // description — a worse outcome than a description a keyboard reader reaches
    // only where the node is already focusable.
    //
    // The decline is a FIELD rather than an omission, so a reader can tell a
    // decision from an oversight; this asserts the field is telling the truth.
    XCTAssertEqual(tooltipProjection(resolvedHint: "Hint")?.focusStopClaimed, false)
  }

  func testTheDescribedByMergeIsVACUOUSHereAndTheReasonIsStructural() {
    // Obligation 4 says MERGE, not replace, an `accessibility.describedBy`
    // already present — `aria-describedby` is an id list and the document has
    // declared two descriptions.
    //
    // On this surface there is nothing to merge WITH, and that is a fact about
    // the platform rather than a shortcut: `describedBy` is an id reference into
    // a document, this surface has no document and no id space, so the
    // accessibility projection drops the slot and REPORTS it dropped. Honouring
    // the tooltip therefore cannot displace it.
    let node = Node(
      id: "n", kind: .markdown(MarkdownSpec(text: .literal("Body"))),
      accessibility: Accessibility(
        label: nil, labelledBy: nil, describedBy: "some-note", role: nil, liveRegion: nil,
        hidden: nil),
      tooltip: .literal("Updated hourly."))

    let projection = accessibilityProjection(node.accessibility, .empty)
    XCTAssertTrue(
      projection.unmapped.contains(.describedBy),
      "the slot is dropped and reported — which is what makes the merge vacuous rather than skipped")

    let tooltip = tooltipProjection(node)
    XCTAssertEqual(tooltip?.hint, "Updated hourly.", "…and the hint is still honoured")
    XCTAssertEqual(
      tooltip?.mergedDescribedBy, false,
      "nothing was merged, because nothing survived to merge with")
  }

  // ── The decoded path ───────────────────────────────────────────────────────

  func testTheCorpusShapesReachTheProjection() throws {
    // The three corpus tooltip fixtures in miniature: a plain hint on a button,
    // an i18n hint on a metric, and a hinted node that ALSO carries an
    // `accessibility` trait — the shape the precedence rule is about.
    let plain = try RenderProjection.decodeNode(
      #"{"id":"t","kind":{"$type":"Markdown","text":"Body"},"tooltip":"Re-reads every document."}"#)
    XCTAssertEqual(tooltipProjection(plain)?.hint, "Re-reads every document.")

    let untooltipped = try RenderProjection.decodeNode(
      #"{"id":"t","kind":{"$type":"Markdown","text":"Body"}}"#)
    XCTAssertNil(tooltipProjection(untooltipped), "a node with no trait projects nothing")
  }
}
