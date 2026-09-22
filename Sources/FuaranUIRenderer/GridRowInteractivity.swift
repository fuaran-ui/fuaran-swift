// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The grid interactive-row projection — `GridSpec.onRowClick` read into the one
// fact a renderer may state on the strength of it (WIRE_FORMAT.md §3.6.24,
// Phase 1701).
//
// ## What the declaration says, and what it does not
//
// `onRowClick` is a closure-bearing slot (§4), so it rides the wire as the
// `"<closure>"` sentinel and carries exactly one readable fact: **this grid
// declares a row action.** That fact — and nothing derived from it — decides
// whether a rendered row is marked interactive.
//
// In the reference class vocabulary the marker is `fuaran-grid-row-interactive`
// beside `fuaran-grid-row`, and a stylesheet keys the pointer cursor on it. This
// surface has no class vocabulary and no document, so the marker here is a
// per-row boolean the arm consumes — "whatever that surface uses to say *this
// row can be activated*", which is the form §3.6.24 states the obligation in for
// exactly this case.
//
// ## The three rules, and why two of them are the ones a host gets wrong
//
//   1. **A bound row carries the marker if and only if the grid declares
//      `onRowClick`.** A grid that declares none emits it on no row.
//   2. **A `staticRows` grid carries it on NO row, whatever it declares.** The
//      static mode honours no row action in any tier: its cells are
//      `TextSource`s rather than the row VALUES an action is applied to, so
//      there is nothing for a host to invoke. Marking there would promise a
//      click no tier can deliver — which is the defect the section exists to
//      remove, not a smaller version of it. This is why the projection takes the
//      whole spec rather than a bare `onRowClick != nil`: the obvious code reads
//      the declaration and never looks at the mode.
//   3. **A host that renders the bound leg as a placeholder emits no row, and so
//      no marker.** This surface renders `Loading…` for `.notResolved` and a
//      no-row-source note for `.noRowSource`, so it is that host in those two
//      states, and the obligation is satisfied vacuously and honestly: there is
//      no row to mislead a reader about. The markers array is EMPTY there rather
//      than all-`false`, because the array is one entry per RENDERED row and a
//      `false` would assert a row that does not exist.
//
// ## What is NOT claimed
//
// `activates` is always `false` here, and it is a field rather than an omission
// — the `TooltipProjection.focusStopClaimed` reasoning. The marker says the
// DOCUMENT declared a row action, never that a click reaches one on this
// surface: the action itself is a closure the wire cannot carry, so no arm here
// can invoke it. §3.6.24 states that distinction directly and admits the marked
// inert row — a pointer on a row that is about to become clickable reads as the
// page it is about to be, where an inert *button* reads as a broken page. A
// reader of the plan can see the claim was considered and declined; a missing
// field would leave them unable to tell a decision from an oversight, and it is
// where the answer goes the day this floor gains a row gesture.
//
// Nor is anything inferred the other way. A host whose rows select on click
// regardless of the declaration is unaffected by this rule — selection is the
// host's fallback, not the document's declaration — so nothing here reads a
// selection slot.
//
// Pure, and deliberately OUTSIDE the SwiftUI gate — the `UploadCeilings.swift`
// reasoning: the decisions are what matter, and a decision testable on only one
// platform is a decision nobody re-checks.

import Foundation
import FuaranUI

/// The interactive-row markers for one rendered grid.
public struct GridRowInteractivity: Equatable, Sendable {
  /// One marker per RENDERED row, in render order: `true` where that row may be
  /// activated, `false` where it may not.
  ///
  /// Per-row rather than one flag for the grid, because the obligation is stated
  /// per row — "carries it on no row at all" is a claim about rows, and a single
  /// boolean could not express a grid that rendered some.
  public let markers: [Bool]

  /// Whether the DOCUMENT declared a row action, read from `onRowClick` alone.
  ///
  /// Carried beside the markers because the two answer different questions: a
  /// `staticRows` grid declaring `onRowClick` has this `true` and every marker
  /// `false`, and rule 2 is precisely that divergence.
  public let rowActionDeclared: Bool

  /// Whether this surface claims a row activation will actually REACH the
  /// declared action. **Always `false`** — see the file header.
  public let activates: Bool

  /// No rendered row carries the marker. The state rules 2 and 3 both produce,
  /// and the one in which a conformant surface renders nothing extra.
  public var marksNoRow: Bool { !markers.contains(true) }
}

/// Project one grid's row action into the markers this surface may show, for the
/// rows it actually renders.
///
/// `rows` is the resolved row feed the bound leg renders from — the same
/// `BindingContext.rows(for:)` value the arm switches on — so the markers line
/// up one-for-one with the rows on screen.
public func gridRowInteractivity(_ spec: GridSpec, rows: ResolvedRows) -> GridRowInteractivity {
  let declared = spec.onRowClick != nil

  // Rule 2 FIRST, and unconditionally: the static mode is checked before the
  // declaration is read, so there is no path on which a declaring static grid
  // can reach the marking branch.
  if let staticRows = spec.staticRows {
    return GridRowInteractivity(
      markers: Array(repeating: false, count: staticRows.rows.count),
      rowActionDeclared: declared,
      activates: false)
  }

  switch rows {
  case .rows(let resolved):
    // Rule 1 — every bound row takes the grid's own answer, and they take the
    // same one: the declaration is a property of the GRID, so a per-row
    // divergence would be this surface inventing a rule.
    return GridRowInteractivity(
      markers: Array(repeating: declared, count: resolved.count),
      rowActionDeclared: declared,
      activates: false)
  case .notResolved, .noRowSource:
    // Rule 3 — the placeholder legs render no row, so there is no marker.
    return GridRowInteractivity(markers: [], rowActionDeclared: declared, activates: false)
  }
}
