// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The image presentation projection — the six `ImageSpec` slots of
// WIRE_FORMAT.md §3.6.2–§3.6.5 read into the shape a render arm applies.
//
// Four of the six are decisions rather than data, and each is the kind a
// surface gets wrong while round-tripping the bytes perfectly:
//
//   * **`srcSet` presentation order is ASCENDING BY WIDTH, and it is the
//     RENDERER's**, not the wire's. The wire preserves AUTHORED order (a codec
//     that sorted would emit bytes differing from what it decoded); a rendering
//     host orders the candidates ascending so its output is canonical for a
//     given tree. The two rules answer different questions, and putting the
//     sort here — never in the decoder — is what lets both be true.
//   * **A candidate the URL floor refused is DROPPED**, where a refused primary
//     `src` is not. The primary must exist so it collapses to the refusal
//     state; a candidate has no such obligation, and offering a client a
//     rendition guaranteed to fail is worse than offering it one fewer.
//   * **`expandable` over a refused `src` emits NO affordance.** The same rule
//     turned on the anchor: a link to nothing is the dead control §3.6.5
//     forbids, so the image still renders and the reader is simply not offered
//     an expansion that could not work.
//   * **`aspectRatio` is a LAYOUT RESERVATION, not a crop**, and `fit` is what
//     happens to pixels that do not match the box. Neither is derived from the
//     other, which is why they are projected as two independent values rather
//     than one combined content mode.
//
// **Pure, and deliberately OUTSIDE the SwiftUI gate**, on the
// `TrendSentiment.swift` / `Accessibility.swift` reasoning: these decisions are
// the load-bearing part and they are asserted on every platform, while the thin
// view application in `FuaranNode.swift` is the only Apple-gated half.

import Foundation
import FuaranUI

/// One `srcSet` candidate that survived the URL floor, at its declared
/// intrinsic pixel width.
public struct ImageCandidate: Equatable, Sendable {
  public let url: String
  public let width: Int
}

/// The projection an image render arm applies.
public struct ImagePresentationPlan: Equatable, Sendable {
  /// The primary source through the §19 floor — `nil` when refused. As with
  /// `MediaPlaybackPlan.source` this is a STATE the arm renders, not a reason
  /// to drop the element.
  public let source: String?

  /// The surviving candidates, ASCENDING BY WIDTH. Empty where the node
  /// declared none, where every candidate was refused, and where the node
  /// declared an explicit empty list — three absences that denote the same
  /// document and are therefore not distinguished here either.
  public let candidates: [ImageCandidate]

  /// The resolved caption, or `nil` where the node carries none.
  ///
  /// Present, it means the caption is BOUND to the image — an assistive
  /// technology announces the two together rather than reading the text as the
  /// next paragraph, which is precisely what an ad-hoc sibling text node could
  /// never say. Absent, there is no wrapper AT ALL: not an empty figure, not a
  /// wrapper with an empty caption.
  public let caption: String?

  /// The anchor target for a declared expansion — `nil` where the node does not
  /// declare one AND where it declares one over a source the floor refused.
  ///
  /// Deliberately the same `nil` for both: §3.6.5's rule is that a refused
  /// source emits no anchor, so "no affordance" is one state however it arose.
  /// The target is the PRIMARY source, never a `srcSet` candidate — a surface
  /// that put a candidate behind the expansion would satisfy every structural
  /// check and defeat the feature, because the reader would tap a thumbnail and
  /// be shown a thumbnail.
  public let expansion: String?

  public let fit: ImageFit
  public let aspectRatio: ImageAspect

  /// Carried, and — on this surface, today — NOT ACTED ON. The render floor has
  /// no network image loader at all (an image renders as a labelled placeholder
  /// box), so there is no fetch to defer and a surface claiming to honour `Lazy`
  /// would be claiming something it does not do. It is projected rather than
  /// dropped so the arm that gains a loader inherits the declaration instead of
  /// having to rediscover the slot.
  public let loading: ImageLoading

  /// `true` when the node declared an expansion the floor refused — the one
  /// case a surface may want to report rather than silently omit, and the case
  /// an `expansion == nil` test alone cannot distinguish from "no expansion
  /// declared".
  public let expansionRefused: Bool
}

extension ImageAspect {
  /// The reserved box as a width÷height ratio; `nil` for `Natural`, which
  /// reserves nothing and lets the content size the element.
  ///
  /// A NUMBER derived from a token, never a number carried by the wire — the
  /// direction matters, because the token vocabulary exists precisely so an
  /// author-supplied ratio has nowhere to land.
  public var ratio: Double? {
    switch self {
    case .natural: return nil
    case .square: return 1.0
    case .fourThree: return 4.0 / 3.0
    case .threeTwo: return 3.0 / 2.0
    case .sixteenNine: return 16.0 / 9.0
    }
  }
}

/// Build the plan for one `Image` node from its resolved bindings.
///
/// `resolvedSrc` is the primary source; `resolvedCandidates` are the `srcSet`
/// entries' resolved sources paired with their declared widths, in AUTHORED
/// order (the caller resolves, this function orders); `resolvedCaption` is
/// `nil` where the node carries no caption.
public func imagePresentationPlan(
  _ spec: ImageSpec,
  resolvedSrc: String,
  resolvedCandidates: [(url: String, width: Int)],
  resolvedCaption: String? = nil
) -> ImagePresentationPlan {
  let source = FuaranUrlPolicy.sanitize(resolvedSrc)

  // Floor first, THEN order — a refused candidate is not a candidate, so it
  // must not occupy a position in the presentation order.
  let candidates =
    resolvedCandidates
    .compactMap { c in
      FuaranUrlPolicy.sanitize(c.url).map { ImageCandidate(url: $0, width: c.width) }
    }
    .sorted { $0.width < $1.width }

  // §3.6.5 — the anchor exists only where the declaration AND a usable target
  // both do. `expansionRefused` keeps the two absences distinguishable to a
  // caller that wants to say something about the second.
  let expansion = spec.expandable ? source : nil

  return ImagePresentationPlan(
    source: source,
    candidates: candidates,
    caption: resolvedCaption,
    expansion: expansion,
    fit: spec.fit,
    aspectRatio: spec.aspectRatio,
    loading: spec.loading,
    expansionRefused: spec.expandable && source == nil)
}
