// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The tree projection — `Tree` read into the row facts WIRE_FORMAT.md §3.6.12
// states normatively.
//
// **What transfers from the HTML tiers, and what does not.** Those tiers emit
// `role="tree"` / `role="treeitem"` / `role="group"` with `aria-level`,
// `aria-setsize`, `aria-posinset`, `aria-expanded`, `aria-selected` and a roving
// `tabindex`. A SwiftUI surface has no attribute bag, so what crosses is not the
// attribute names but the FACTS behind them — a row's depth, its position in its
// sibling set, whether it owns children, whether it is open, whether it is
// selected, and which single row is the widget's tab stop. Every one of those is
// computable here, from the wire plus the two named State slots, with no view
// involved; and computing them here is what lets them be asserted on Windows and
// Linux as well as on macOS.
//
// The eight obligations, and where each lands:
//
//   1. THE ARIA TREE PATTERN — the facts are `level` / `posInSet` / `setSize` on
//      every row; the roles are the arm's.
//   2. EXPANDED ONLY ON ROWS THAT HAVE CHILDREN. `expanded` is an `Optional`,
//      and `nil` is the assertion's ABSENCE rather than a collapsed row: on a
//      leaf the attribute asserts a subtree that does not exist, and assistive
//      technology announces such a row as closed — a reader told there is more
//      when there is not.
//   3. SELECTED ONLY WHERE A SELECTION KEY IS NAMED. Same shape, same reason:
//      `nil` throughout when the document names no key, because a tree that
//      never selects must not declare a selectable widget with nothing selected.
//   4. ONE TAB STOP. `isTabStop` is true on exactly one VISIBLE row across the
//      whole widget — the obligation the kind exists for, since a composition of
//      independently focusable containers is N tab stops and no arrangement of
//      them produces one.
//   5. A STATED ACCESSIBLE NAME. `label` is the row's OWN visible label, never a
//      name computed from its contents: a treeitem owns its child group, so a
//      computed name reads the whole branch out as the row's own name.
//   6. THE SIX KEY BINDINGS are an INTERACTIVE host's, over this identical
//      structure. Not modelled here; see the render-projection guide.
//   7. THE WHOLE HIERARCHY WITHOUT SCRIPT. These plans are computed from state
//      alone, so a static render and an interactive host's first frame agree by
//      construction — movement is the addition, never a precondition.
//   8. DERIVE NOTHING ELSE FROM A ROW. Expandability comes from `children` and
//      from nothing else, and there is no per-row expansion state here beside the
//      named key — a shadow copy is free to disagree with the slot every other
//      row is drawn from, which is why this projection keeps none.
//
// Pure, and deliberately OUTSIDE the SwiftUI gate — the `MediaPlayback.swift`
// reasoning.

import Foundation
import FuaranUI

/// One projected `Tree` row: the facts a rendering surface needs, resolved.
public struct TreeRowPlan: Equatable, Sendable {
  public let id: String

  /// The row's STATED accessible name — its own visible label, resolved.
  ///
  /// Stated rather than computed, which is obligation 5 and the whole reason
  /// this field is not derived from `children`. It is also the visible text, so
  /// the two cannot drift: a surface with one field for both cannot show one
  /// name and announce another.
  public let label: String

  public let icon: String?

  /// 1-based depth, root rows at 1.
  public let level: Int
  /// 1-based position within this row's own sibling set.
  public let posInSet: Int
  /// The size of that sibling set.
  public let setSize: Int

  /// Whether this row owns children — the ONLY thing expandability is derived
  /// from (obligation 8).
  public let hasChildren: Bool

  /// Open / closed, or `nil` on a row with no children.
  ///
  /// `nil` is not "closed": it is the absence of the claim (obligation 2).
  public let expanded: Bool?

  /// Selected / not, or `nil` throughout when the document names no selection
  /// key (obligation 3).
  public let selected: Bool?

  /// Exactly one VISIBLE row in the whole widget carries `true` (obligation 4).
  public let isTabStop: Bool

  /// This row's own children, projected. Present whether or not the row is open
  /// — visibility is a property of the ANCESTOR chain and is answered by
  /// `visibleRows`, so an arm that renders only open branches and one that
  /// renders the whole structure both read the same plan.
  public let children: [TreeRowPlan]
}

/// Project a whole `Tree` into its rows.
///
/// `expandedIds` is the value the document's `expandedStateKey` names — a SET of
/// open row ids — and `nil` means the document named no key at all. The two are
/// deliberately different: **a tree naming no `expandedStateKey` renders FULLY
/// EXPANDED and does not toggle**, which is the same reading that lets a grid
/// honour a declared initial order while offering no interactive sorting, and it
/// is the only reading under which such a tree shows its content at all. An
/// EMPTY set, by contrast, is a document that named a key over which every row
/// is currently closed.
///
/// `selectedId` is the value `selectionStateKey` names. A host handing a value of
/// some other shape passes `nil` here rather than an error: this is the host's
/// own state slot and not a wire document, so there is nothing to refuse, and
/// refusing would blank a tree over a value the reader never authored.
public func treeRowPlans(
  _ spec: TreeSpec,
  expandedIds: Set<String>? = nil,
  selectedId: String? = nil,
  resolveText: (TextSource) -> String = literalTrackText
) -> [TreeRowPlan] {
  let selects = spec.selectionStateKey != nil

  // The tab stop is decided BEFORE the rows are built, over the visible set, so
  // exactly one row can carry it however the hierarchy is shaped. The selected
  // row when it is visible, else the first visible row — computed from state
  // alone, so a server rendering and a client's first frame agree.
  let visible = visibleRowIds(spec.items, expandedIds: expandedIds)
  let tabStop: String? =
    (selects && selectedId != nil && visible.contains(selectedId!)) ? selectedId : visible.first

  func project(_ items: [TreeItem], level: Int) -> [TreeRowPlan] {
    items.enumerated().map { (index, item) in
      let hasChildren = !item.children.isEmpty
      return TreeRowPlan(
        id: item.id,
        label: resolveText(item.label),
        icon: item.icon,
        level: level,
        posInSet: index + 1,
        setSize: items.count,
        hasChildren: hasChildren,
        // Obligation 2: the claim exists only where a subtree does.
        expanded: hasChildren ? isExpanded(item.id, expandedIds) : nil,
        // Obligation 3: the claim exists only where the document declared the
        // slot it would be read from.
        selected: selects ? (item.id == selectedId) : nil,
        isTabStop: item.id == tabStop,
        children: project(item.children, level: level + 1))
    }
  }
  return project(spec.items, level: 1)
}

/// Whether a row is open. A tree with no declared expansion key is FULLY
/// EXPANDED — see `treeRowPlans`.
public func isExpanded(_ id: String, _ expandedIds: Set<String>?) -> Bool {
  guard let expandedIds else { return true }
  return expandedIds.contains(id)
}

/// The ids of every row a reader can currently see, in document order: a row is
/// visible when every ANCESTOR of it is open. The root rows are always visible.
///
/// This is the set the single tab stop is chosen from, and it is deliberately
/// computed from the same `isExpanded` reading the plans use — a second walk
/// with its own notion of openness is exactly the shadow state obligation 8
/// forbids.
public func visibleRowIds(_ items: [TreeItem], expandedIds: Set<String>?) -> [String] {
  var out: [String] = []
  func walk(_ rows: [TreeItem]) {
    for row in rows {
      out.append(row.id)
      if !row.children.isEmpty, isExpanded(row.id, expandedIds) { walk(row.children) }
    }
  }
  walk(items)
  return out
}

/// Every projected row, depth-first in document order — the flat view an
/// assertion or a coverage walk wants without re-deriving the recursion.
public func flattenTreeRows(_ rows: [TreeRowPlan]) -> [TreeRowPlan] {
  rows.flatMap { [$0] + flattenTreeRows($0.children) }
}
