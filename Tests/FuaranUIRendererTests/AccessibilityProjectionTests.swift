// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The accessibility projection — the mapping decisions, asserted directly.
//
// Two tiers, mirroring the grid-cell walk: the **projection** is pure logic and
// is asserted here, because that is where the load-bearing semantics live — the
// role map's unmapped fallback, the empty-label drop, and above all the DROP SET
// itself, which is the whole content of the policy in `CLAUDE.md` ("dropped,
// never silently"). The thin **modifier application** is SwiftUI-only and is
// exercised by the macOS CI build.
//
// NOT SwiftUI-guarded and NOT core-gated: the projection is pure, so this leg
// runs everywhere `swift test` runs, including the Windows job. That is the
// point of keeping the mapping outside `#if canImport(SwiftUI)` — a decision
// that can only be tested on one platform is a decision nobody re-checks.

import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class AccessibilityProjectionTests: XCTestCase {
  private let ctx = BindingContext.empty

  private func text(_ s: String) -> Binding { .staticValue(.ast(.string(s))) }
  private func flag(_ b: Bool) -> Binding { .staticValue(.ast(.bool(b))) }

  // ── The absent trait ───────────────────────────────────────────────────────

  func testNoTraitProjectsNothing() {
    let p = accessibilityProjection(nil, ctx)
    XCTAssertTrue(p.isEmpty)
    XCTAssertTrue(p.unmapped.isEmpty)
  }

  // ── label ──────────────────────────────────────────────────────────────────

  func testLabelResolvesThroughTheBinding() {
    let p = accessibilityProjection(Accessibility(label: text("Save changes")), ctx)
    XCTAssertEqual(p.label, "Save changes")
    XCTAssertFalse(p.isEmpty)
  }

  func testLabelResolvingEmptyIsDropped() {
    // The reference projection filters an empty resolved label; here the stake
    // is higher than parity — an empty `.accessibilityLabel` would ERASE the
    // view's natural name rather than leave it alone.
    let p = accessibilityProjection(Accessibility(label: text("")), ctx)
    XCTAssertNil(p.label)
    XCTAssertTrue(p.isEmpty)
  }

  func testAnUnresolvableLabelBindingIsDroppedNotRenderedAsAPlaceholder() {
    // A host-owned binding has no wire-surviving value at the render floor, so
    // it resolves empty — and an empty label is dropped, never emitted as "".
    let p = accessibilityProjection(
      Accessibility(label: .query(name: "orders", dependsOn: nil)), ctx)
    XCTAssertNil(p.label)
  }

  // ── role ───────────────────────────────────────────────────────────────────

  func testTheThreeMappedRoleTokensCarryTheirTrait() {
    for (token, want) in [
      ("button", SemanticTrait.button), ("link", .link), ("heading", .header),
    ] {
      let p = accessibilityProjection(Accessibility(role: token), ctx)
      XCTAssertEqual(p.traits, [want], "role \(token)")
      XCTAssertTrue(p.unmapped.isEmpty, "role \(token) should not report a drop")
    }
  }

  func testEveryOtherWireRoleIsReportedUnmappedNotApproximated() {
    // The decision this pins: a role with no SwiftUI trait that MEANS what it
    // means is dropped rather than approximated. `tab` as `.isButton` and
    // `dialog` as `.isModal` are the two tempting approximations, and both are
    // mis-statements rather than partial ones.
    for token in [
      "dialog", "alert", "status", "banner", "navigation", "main", "form", "region",
      "progressbar", "tab", "tablist", "tabpanel",
    ] {
      let p = accessibilityProjection(Accessibility(role: token), ctx)
      XCTAssertTrue(p.traits.isEmpty, "role \(token) should carry no trait")
      XCTAssertEqual(p.unmapped, [.role], "role \(token) should report the drop")
      XCTAssertTrue(p.isEmpty, "role \(token) alone should project no modifier")
    }
  }

  func testACustomRoleIsUnmappedByDefinition() {
    let p = accessibilityProjection(Accessibility(role: "treegrid"), ctx)
    XCTAssertEqual(p.unmapped, [.role])
  }

  func testTheRoleTokenIsMatchedExactlyNotCaseFolded() {
    // The wire's tokens are lowercase ARIA roles and the reference emits the
    // token the author declared. Accepting "Button" here would honour a
    // spelling no HTML tier honours — a divergence, not a leniency.
    let p = accessibilityProjection(Accessibility(role: "Button"), ctx)
    XCTAssertTrue(p.traits.isEmpty)
    XCTAssertEqual(p.unmapped, [.role])
  }

  // ── labelledBy / describedBy — the drop set ────────────────────────────────

  func testLabelledByAndDescribedByAreReportedUnmapped() {
    let p = accessibilityProjection(
      Accessibility(labelledBy: "heading-1", describedBy: "help-1"), ctx)
    XCTAssertEqual(p.unmapped, [.labelledBy, .describedBy])
    // Reported, and projecting nothing — the view is returned untouched.
    XCTAssertTrue(p.isEmpty)
  }

  func testTheDropSetIsReportedInWireSlotOrder() {
    // Order is part of the contract: the drop set is meant to be read, and a
    // set that reorders itself per input is one nobody can assert against.
    let p = accessibilityProjection(
      Accessibility(labelledBy: "h", describedBy: "d", role: "banner"), ctx)
    XCTAssertEqual(p.unmapped, [.labelledBy, .describedBy, .role])
  }

  // ── liveRegion ─────────────────────────────────────────────────────────────

  func testPoliteAndAssertiveBothCarryUpdatesFrequently() {
    // The PARTIAL mapping, pinned including its limit: SwiftUI's announcement is
    // imperative, so the politeness distinction cannot survive — both live
    // levels project the same declarative trait, and that is recorded rather
    // than hidden.
    for kind in [LiveRegionKind.polite, .assertive] {
      let p = accessibilityProjection(Accessibility(liveRegion: kind), ctx)
      XCTAssertEqual(p.traits, [.updatesFrequently], "liveRegion \(kind)")
    }
  }

  func testOffProjectsNothingAndIsNotADrop() {
    // `off` asserts "do not announce", which IS the platform default — so the
    // faithful projection is the absence of the trait, not a reported drop.
    let p = accessibilityProjection(Accessibility(liveRegion: .off), ctx)
    XCTAssertTrue(p.traits.isEmpty)
    XCTAssertTrue(p.unmapped.isEmpty)
    XCTAssertTrue(p.isEmpty)
  }

  // ── hidden — the aria-hidden analogue ──────────────────────────────────────

  func testHiddenTrueProjectsTheHiddenFlag() {
    // The author's intent is to REMOVE the subtree from the accessibility tree,
    // and that intent must survive the crossing to a native surface with the
    // same force it has on the web.
    let p = accessibilityProjection(Accessibility(hidden: flag(true)), ctx)
    XCTAssertTrue(p.hidden)
    XCTAssertFalse(p.isEmpty)
  }

  func testHiddenFalseProjectsNothing() {
    // Mirrors the reference: only a resolved-true `hidden` emits. A
    // `.accessibilityHidden(false)` would assert visibility the author never
    // claimed, overriding a natural hide.
    let p = accessibilityProjection(Accessibility(hidden: flag(false)), ctx)
    XCTAssertFalse(p.hidden)
    XCTAssertTrue(p.isEmpty)
  }

  func testHiddenResolvesThroughSeededState() {
    let seeded = BindingContext(state: ["decorative": .bool(true)])
    let p = accessibilityProjection(
      Accessibility(hidden: .state(key: "decorative", defaultValue: .ast(.bool(false)))), seeded)
    XCTAssertTrue(p.hidden)
  }

  // ── The whole trait at once ────────────────────────────────────────────────

  func testAFullyPopulatedTraitProjectsTheMappableHalfAndReportsTheRest() {
    let p = accessibilityProjection(
      Accessibility(
        label: text("Open the report"),
        labelledBy: "heading-1",
        describedBy: "help-1",
        role: "link",
        liveRegion: .polite,
        hidden: flag(true)),
      ctx)
    XCTAssertEqual(p.label, "Open the report")
    XCTAssertEqual(p.traits, [.link, .updatesFrequently])
    XCTAssertTrue(p.hidden)
    XCTAssertEqual(p.unmapped, [.labelledBy, .describedBy])
  }

  func testTheProjectionNeverThrowsOnAnUnmappableTrait() {
    // The policy, as a property rather than a sentence: a render tier does not
    // REFUSE a tree the wire declares valid. Every slot combination projects
    // some (possibly empty) result and reports what it could not carry — a
    // surface that rejected one would fork the vocabulary by host.
    let p = accessibilityProjection(
      Accessibility(labelledBy: "a", describedBy: "b", role: "tablist"), ctx)
    XCTAssertTrue(p.isEmpty)
    XCTAssertEqual(p.unmapped.count, 3)
  }
}
