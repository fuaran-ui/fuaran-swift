// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The node envelope (§3.1), hand-written. The flat `NodeKind` vocabulary (§3.2),
// its `NodeKindTag` discriminator set and the `NodeCategory` classification are
// GENERATED into `Model.generated.swift` from the corpus IDL (Phase 2299), so a
// kind the IDL gains arrives by regeneration and is a build error at every
// exhaustive `switch` over the kind set — the decoder's dispatch among them —
// until its arm is written; it can never slip in as a silent fallback.
//
// The envelope stays hand-written because its representation is not a function
// of the IDL's `nodeFields`: `state` and `style` are TOTAL (absent reads as
// `.empty` / `.default`), `fallback` and the state-behaviour subtrees are boxed in
// `NodeRef` so the value graph stays finite, and `motion` / `extraAttributes`
// (host-only) and `visible` are not modelled by this render projection.

import Foundation

/// A reference box for the state-behaviour subtrees. `StateBehaviour` is an
/// inline field of `Node`, so its optional child `Node`s must sit behind a
/// reference to keep the value graph finite (the `NodeKind` payloads are boxed
/// by `indirect`, but `Node.state` is not).
public final class NodeRef: Equatable, @unchecked Sendable {
  public let node: Node
  public init(_ node: Node) { self.node = node }
  public static func == (l: NodeRef, r: NodeRef) -> Bool { l.node == r.node }
}

/// State-dependent alternative renderings (§3.1). `onError` is a closure (§4) —
/// presence only.
public struct StateBehaviour: Equatable, Sendable {
  public var onLoading: NodeRef?
  public var onEmpty: NodeRef?
  public var onError: Closure?

  public static let empty = StateBehaviour(onLoading: nil, onEmpty: nil, onError: nil)

  public var isEmpty: Bool { onLoading == nil && onEmpty == nil && onError == nil }
}

extension SemanticStyle {
  /// Every member at its declared default — the style a node carries when the
  /// wire omits `style` (each member is omitted at its default on both
  /// boundaries).
  public static let `default` = SemanticStyle(
    direction: .auto, emphasis: .normal, role: .none, tone: .default, voice: .default,
    weight: .standard)

  public var isDefault: Bool { self == .default }
}

/// The typed UI tree node (§3.1). `motion` / `extraAttributes` are wire-omitted
/// by design (§9) and therefore not modelled by this render projection.
public struct Node: Equatable, Sendable {
  public var id: String
  public var kind: NodeKind
  public var state: StateBehaviour
  public var style: SemanticStyle
  public var accessibility: Accessibility?
  /// The tooltip trait (§3.1, Phase 1112) — a short supplementary hint.
  ///
  /// **A node-level TRAIT, not a field of any kind**, and it sits here beside
  /// `accessibility` for the reason the specification gives: nothing about "a
  /// short supplementary description of this thing" varies with whether the
  /// thing is a button or a metric, so a per-kind spelling of it is not this
  /// trait. In particular `ButtonSpec` carries a legacy host-only `tooltip`
  /// slot which is never emitted and never decoded — a `tooltip` inside a
  /// `kind` object is an unknown key, tolerated and ignored under rule 2, and
  /// is not a second spelling of this one.
  ///
  /// **It is a DESCRIPTION, never a NAME.** `accessibility.label` names the
  /// element; the tooltip supplements a name that already exists. An icon-only
  /// control needs both slots saying different things, so a surface that
  /// projected this as the accessible name would leave such a control with two
  /// competing names and no description. See `tooltipProjection` in the
  /// renderer for how that lands on this platform.
  public var tooltip: TextSource?
  /// Phase 1812 — the author-declared degraded rendering: a full node a BEHIND
  /// reader (one that meets this node's kind as a transport-only `Unknown`)
  /// renders in place of its placeholder. A current reader decodes and preserves
  /// it and never renders it. Boxed, as `StateBehaviour`'s slots are, because a
  /// value type cannot hold itself.
  public var fallback: NodeRef?

  public init(
    id: String, kind: NodeKind, state: StateBehaviour = .empty,
    style: SemanticStyle = .default, accessibility: Accessibility? = nil,
    tooltip: TextSource? = nil, fallback: NodeRef? = nil
  ) {
    self.id = id
    self.kind = kind
    self.state = state
    self.style = style
    self.accessibility = accessibility
    self.tooltip = tooltip
    self.fallback = fallback
  }
}
