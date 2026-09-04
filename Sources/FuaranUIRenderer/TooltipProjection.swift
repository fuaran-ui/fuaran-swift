// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The tooltip projection — the node-level `tooltip` trait (WIRE_FORMAT.md §3.1,
// Phase 1112) read into what this surface can honestly do with it.
//
// **It is a DESCRIPTION, never a NAME**, and that is the one rule a surface must
// not get wrong. `accessibility.label` names the element; the tooltip supplements
// a name that already exists. An icon-only control needs both slots saying
// different things, so a surface that projected the hint as the accessible name
// would leave such a control with two competing names and no description — which
// is why nothing in this file ever reaches `accessibilityLabel`, by construction
// rather than by discipline.
//
// **The gesture is not on the wire.** Hover, focus, long-press, touch reveal,
// placement and delay are the renderer's own affordance: the document says WHAT
// the hint is and never HOW it appears, so nothing here names an event or a
// timing.
//
// ## The obligations, and this surface's answer to each
//
// The specification states six. Note at the outset that §3.1 records them as
// render obligations rather than wire shape, and that **`render-fidelity.json`
// carries no row for them** — the trait is a field, not a kind, and §11.2
// vocabulary attestation enumerates CASES. So there is no manifest checker to
// register here and the assertions live in this surface's own tests, which is
// the same position the reference tiers are in.
//
//   1. *A rendered element carrying `role="tooltip"` and a stable id, referenced
//      from `aria-describedby`.* Projected as a rendered hint plus a DESCRIPTION
//      channel that is not the name — on this platform, `accessibilityHint`.
//      There is no id list to reference because there is no document; the
//      relation the id exists to express is direct here.
//   2. *`aria-describedby` on the element that takes keyboard focus, ensuring
//      such an element exists.* NOT claimed by this surface, and said out loud:
//      the render floor gives most kinds no focus stop, and manufacturing one
//      around every hinted node would change the tab order of a tree to satisfy
//      a description. See `TooltipProjection.focusStopClaimed`.
//   3. *Hoverable and persistent (WCAG 1.4.13).* Satisfied structurally rather
//      than by timing code: the hint is rendered as an adjacent element of the
//      node's own body, so there is no timer to expire and no hover target to
//      leave. The reference emission satisfies both the same way — by placement,
//      not by script.
//   4. *MERGE, not replace, an `accessibility.describedBy` already present.* On
//      this surface the merge is VACUOUS and the reason is structural:
//      `describedBy` is an id reference into a document, this surface has no
//      document and no id space, and the accessibility projection therefore
//      DROPS the slot and reports it dropped. There is nothing present to merge
//      with, so honouring the tooltip cannot displace it. Recorded here so the
//      claim is not read as met by an implementation that never faced it.
//   5. *Emit NOTHING — no hint, no description, no focus stop — when the hint
//      resolves to empty or whitespace.* Honoured: `tooltipProjection` returns
//      `nil`. Advertising a description that is not there is worse than silence,
//      and this is the one obligation of the six a surface fails by writing the
//      obvious code (`if node.tooltip != nil`).
//   6. *SHOULD bound the hint's size.* A SHOULD, and a layout concern the arm
//      answers; nothing in the projection.
//
// Pure, and deliberately OUTSIDE the SwiftUI gate — the `MediaPlayback.swift`
// reasoning: the decisions are what matter, and a decision testable on only one
// platform is a decision nobody re-checks.

import Foundation
import FuaranUI

/// The projected tooltip hint for one node, or `nil` where the node offers none
/// that resolves to anything.
public struct TooltipProjection: Equatable, Sendable {
  /// The resolved hint text, non-empty by construction.
  public let hint: String

  /// Whether this surface claims obligation 2 — the focus-stop guarantee.
  ///
  /// **Always `false`, and it is a field rather than an omission.** A reader of
  /// the plan can see that the claim was considered and declined, where a
  /// missing field would leave them unable to tell a decision from an oversight.
  /// The decline is honest: the render floor gives most kinds no focus stop, and
  /// synthesising one around every hinted node would rewrite a tree's tab order
  /// to satisfy a description — a worse outcome than a description a keyboard
  /// reader reaches only where the node is already focusable.
  public let focusStopClaimed: Bool

  /// Whether an `accessibility.describedBy` was present and therefore merged
  /// with rather than replaced (obligation 4).
  ///
  /// **Always `false`, because the merge is structurally vacuous here**: this
  /// surface has no id space, so the accessibility projection drops
  /// `describedBy` and reports it dropped. Carried for the same reason
  /// `focusStopClaimed` is — so the vacuity is visible rather than inferred.
  public let mergedDescribedBy: Bool
}

/// Project a node's tooltip trait.
///
/// Takes the already-RESOLVED hint, because a `TextSource`'s bound and `i18n`
/// arms resolve only at render time — deciding emptiness before resolution would
/// suppress a hint that resolves to text, or emit one that resolves to nothing.
public func tooltipProjection(resolvedHint: String?) -> TooltipProjection? {
  guard let resolvedHint,
    !resolvedHint.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  else { return nil }
  return TooltipProjection(hint: resolvedHint, focusStopClaimed: false, mergedDescribedBy: false)
}

/// `tooltipProjection`, reading the node's own slot through a resolver.
public func tooltipProjection(
  _ node: Node, resolveText: (TextSource) -> String = literalTrackText
) -> TooltipProjection? {
  tooltipProjection(resolvedHint: node.tooltip.map { resolveText($0) })
}
