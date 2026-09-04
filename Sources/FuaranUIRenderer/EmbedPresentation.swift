// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The embed presentation projection — `Embed` read into the three obligations
// the wire format states normatively (WIRE_FORMAT.md §3.6.8, §19.1).
//
// **Why an embed gets its own file and its own egress class.** Every other URL
// slot on this surface is fetch-and-DISPLAY or navigate-on-a-click; an embed is
// fetch-and-EXECUTE. The document it names runs, in a browsing context this page
// created, so the floor is narrower (`https` only — no other scheme and no
// schemeless reference) and a refusal costs something different from every other
// refusal here.
//
// **What the wire asks for**, all three normative and none of them expressible
// in the bytes:
//
//   * THE SANDBOX DECLARATION, ALWAYS, and EMPTY when nothing is granted.
//     Omitting it on a permissionless embed produces the same markup as an
//     UNSANDBOXED frame — which is why the emission is unconditional rather than
//     derived from the list being non-empty. This is the obligation a surface is
//     most likely to fail by writing the obvious code.
//   * THE TOKENS IN THE VOCABULARY'S DECLARATION ORDER, DE-DUPLICATED. The wire
//     preserves whatever order the document authored (a JSON array is ordered
//     data and this format does not re-sort a document's own list), so the
//     determinism the markup needs is established HERE instead: two documents
//     naming the same set produce the same declaration. And `AllowFullscreen` is
//     NOT a sandbox token — it is a permissions-policy directive riding `allow`,
//     emitted only where declared, because an empty `allow` is not the same
//     statement as an absent one.
//   * A REFUSED SOURCE OMITS THE SOURCE ENTIRELY. This is the one place a
//     refusal does not take a substitute destination, and the reason is the
//     element: a frame pointed at a refusal URL RENDERS that page, where one with
//     no source is a well-defined empty browsing context that fetches nothing.
//     The refusal is still RECORDED, so "nothing was declared" and "this was
//     refused" stay different facts.
//
// **Pure, and deliberately OUTSIDE the SwiftUI gate** — the `MediaPlayback.swift`
// reasoning. The decisions are the load-bearing part and they are asserted on
// every platform; the thin view application in `FuaranNode.swift` is the only
// Apple-gated half.

import Foundation
import FuaranUI

/// The projection an embed render arm applies: the resolved, floored,
/// obligation-checked shape of one `Embed` node.
///
/// **There is deliberately no public initialiser.** `embedFramePlan` is the only
/// way to obtain one, and it is where the sandbox obligation is discharged — a
/// memberwise init would let a caller construct a plan with tokens the document
/// never named, or in an order it chose, re-opening by an initialiser exactly
/// what the projection closes.
public struct EmbedFramePlan: Equatable, Sendable {
  /// The accessible name, ALWAYS. There is no absent case and no branch: `title`
  /// is mandatory on the wire and a browsing context has no decorative case, so
  /// unlike `Image`'s `alt` there is nothing here to condition on.
  ///
  /// The node-level `Accessibility.label` precedence is `MediaSpec.label`'s and
  /// falls out of the render spine the same way — `fuaranNodeBody` applies the
  /// node projection after the kind arm, and a later `.accessibilityLabel`
  /// replaces an earlier one.
  public let title: String

  /// The floored source, or `nil` when the `embed` class refused it.
  ///
  /// `nil` here means *emit no source at all* — never a substitute. See the
  /// third obligation in this file's header for why that differs from every
  /// other refusal on this surface.
  public let source: String?

  /// Whether a source was declared AND refused, as a fact separate from
  /// `source == nil`.
  ///
  /// The two are not the same statement and an `Optional` alone cannot tell them
  /// apart: a plan whose source is `nil` because the document named nothing
  /// resolvable, and one whose source is `nil` because the floor refused an
  /// `http:` document, are different things to show a reader and different
  /// things to log. This is the egress-refusal marker in the shape this surface
  /// has for it.
  public let sourceRefused: Bool

  /// The sandbox relaxations, in the VOCABULARY's declaration order,
  /// de-duplicated.
  ///
  /// **Non-optional, and that is how the always-emitted obligation is
  /// discharged.** An empty array is the empty sandbox — the maximally
  /// restrictive value — and there is no representation of "no sandbox" for an
  /// arm to reach. A surface that modelled this as `[String]?` would have made
  /// the unsandboxed frame expressible, which is the whole defect the obligation
  /// exists to foreclose.
  public let sandbox: [String]

  /// The permissions-policy directives, in the same declaration order.
  ///
  /// Empty means the attribute is ABSENT, which is deliberately not the same
  /// statement as `sandbox`'s empty: an empty `allow` grants nothing and an
  /// absent one says nothing, and only the sandbox attribute's absence is
  /// dangerous.
  public let allow: [String]

  /// The declared layout ratio. A CLASS on the frame in the reference emission —
  /// no value from the tree ever reaches a style attribute, which is `Image`'s
  /// presentation rule (§3.6.2) applied unchanged. Carried here as the token, so
  /// this surface's arm reserves a box rather than interpolating a number.
  public let aspectRatio: ImageAspect

  /// Unconditional. There is deliberately no wire slot for either, so neither is
  /// a value this projection reads — they are constants the obligation names,
  /// carried on the plan so an arm that gains a real frame inherits them rather
  /// than rediscovering them.
  public let lazyLoading: Bool

  /// `strict-origin-when-cross-origin`, and deliberately NOT `no-referrer`:
  /// several ubiquitous providers restrict playback by referring domain, so
  /// stripping the header outright breaks a legitimate embed, while sending the
  /// origin alone leaks no path and no query.
  public let referrerPolicy: String
}

/// The referrer policy every embed carries. A constant rather than a slot,
/// stated once so the plan and any future arm cannot spell it differently.
public let embedReferrerPolicy = "strict-origin-when-cross-origin"

/// Build the plan for one `Embed` node from its resolved bindings.
///
/// `resolvedSrc` is the source AFTER binding resolution and BEFORE the floor:
/// a `Binding` may not carry a literal at all, so flooring before resolution
/// would be checking a placeholder — the `mediaPlaybackPlan` ordering, and the
/// only correct one.
///
/// An EMPTY resolved source is treated as "nothing declared" rather than as a
/// refusal: the `embed` class refuses the empty string like every other
/// non-`https` value, but reporting that as an egress refusal would tell a reader
/// their destination was rejected when the document never resolved one.
public func embedFramePlan(
  _ spec: EmbedSpec, resolvedTitle: String, resolvedSrc: String
) -> EmbedFramePlan {
  let declared = !resolvedSrc.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
  let floored = declared ? FuaranUrlPolicy.sanitizeEmbed(resolvedSrc) : nil

  // The order is the VOCABULARY's, taken from `allCases` rather than from a
  // second list beside it — so a fifth relaxation added to the enum takes its
  // place here with no edit, and the two can never disagree about what
  // "declaration order" means. Membership is the document's; order is not.
  let declaredSet = Set(spec.permissions)
  let ordered = EmbedPermission.allCases.filter { declaredSet.contains($0) }

  return EmbedFramePlan(
    title: resolvedTitle,
    source: floored,
    sourceRefused: declared && floored == nil,
    sandbox: ordered.compactMap { $0.sandboxToken },
    allow: ordered.compactMap { $0.allowDirective },
    aspectRatio: spec.aspectRatio,
    lazyLoading: true,
    referrerPolicy: embedReferrerPolicy)
}
