// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The unregistered-`Custom` placeholder projection (WIRE_FORMAT.md §25.4).
//
// A `Custom` node names a component this surface has no renderer for — that is
// what the kind IS here, since this tier ships no custom-renderer registry seam
// at all, so EVERY `Custom` node takes the unregistered path. What the reader
// gets is therefore decided entirely by this projection, and §25.4 states the
// decision normatively rather than leaving it to a surface:
//
//   * the placeholder carries the COMPONENT IDENTITY, so a reader can name what
//     did not render and an author can find it;
//   * it emits NO PROP VALUE — this surface was never asked to interpret the
//     node's props, and a value shown out of the component that gives it
//     meaning is a claim nobody made;
//   * it GUESSES NOTHING about the component's appearance or purpose. A
//     confident wrong description is worse than none.
//
// **The description slot §25.4 describes is not filled here, and that is the
// conformant answer rather than a gap.** A description comes from a CONTRACT
// CARD, and this surface holds no card reader — so no card is ever available,
// every node takes the uncarded branch, and the identity-only placeholder is
// what §25.4 asks of a host in that position. A surface that invented a summary
// from the identity alone would be producing exactly the guess the rule forbids.
// Adding a card reader is a separate adoption with its own bar; it would extend
// this projection rather than replace it.
//
// **Pure, and deliberately OUTSIDE the SwiftUI gate** — the reasoning
// `MediaPlayback.swift`, `ImagePresentation.swift`, `TrendSentiment.swift` and
// `Accessibility.swift` all record: the decision is the load-bearing part, and a
// decision testable on only one platform is a decision nobody re-checks. The
// thin view application in `FuaranNode.swift` is the only Apple-gated half.

import Foundation
import FuaranUI

/// The projection a `Custom` render arm applies: what an unregistered component
/// shows a reader.
///
/// **There is deliberately no public initialiser.** `customPlaceholder` is the
/// only way to obtain one, and it is where the no-guess obligation is
/// discharged — a memberwise init would let a caller hand this type a
/// description no card ever supplied, re-opening by an initialiser exactly what
/// the projection closes.
public struct CustomPlaceholder: Equatable, Sendable {
  /// The heading — a fixed word naming the CLASS of thing that did not render,
  /// never the component's own name dressed up as a title.
  public let title: String

  /// The component identity, `<moduleId>/<componentId>`. The whole of what this
  /// surface knows and the whole of what it claims.
  public let identity: String
}

/// Build the placeholder for one unregistered `Custom` node.
///
/// Note what is NOT read: `props`, `contentHash` and `exposedNodeIds` are all
/// carried by the spec and none of them reaches the reader. That is not an
/// omission to be tidied up later — a prop value shown outside the component
/// that interprets it, or a hash presented as a verdict this surface cannot
/// reach (it has no card to compare against), would each be a stronger claim
/// than this surface is entitled to make.
public func customPlaceholder(_ spec: CustomSpec) -> CustomPlaceholder {
  CustomPlaceholder(title: "Custom", identity: "\(spec.moduleId)/\(spec.componentId)")
}
