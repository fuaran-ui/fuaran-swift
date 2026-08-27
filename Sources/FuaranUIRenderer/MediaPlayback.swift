// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The media playback projection — `Media` read into the three obligations the
// wire format states normatively (WIRE_FORMAT.md §3.6.6).
//
// **What the wire asks for**, and all three are CONTRACT rather than choice,
// because a surface that got any of them wrong would still hold a perfectly
// well-formed tree:
//
//   * an ACCESSIBLE NAME, always. `label` is mandatory on the wire and a
//     transport has no decorative case, so unlike `Image`'s `alt` there is no
//     branch to get wrong here — only a precedence, recorded below.
//   * `autoplay` NEVER WITHOUT MUTED. The pairing is not a default a caller
//     overrides; it is what the declaration MEANS, which is why the wire
//     carries no separate muted slot to fall out of step with it. Every
//     mainstream browser blocks unmuted autoplay, so an unmuted honouring would
//     produce a player that silently never starts — the declaration would mean
//     nothing and the failure would be invisible.
//   * NO AUTOPLAY PATHWAY ON AUDIO, at all. Not "off by default": the
//     `MediaKind.audio` case declares no slot, so this projection has nothing
//     to read and cannot acquire something to read by a later edit here.
//
// **The pairing is made UNREPRESENTABLE rather than asserted.** `muted` is a
// computed property returning `autoplay`, so there is no combination of stored
// values in which the two disagree and no initialiser through which a caller
// could construct one. That is the same argument the wire makes for having no
// `muted` slot, applied to this type: a second stored bool would be a second
// knob free to drift from the first, and the only combination it would add is
// the one no surface may render.
//
// **Pure, and deliberately OUTSIDE the SwiftUI gate** — the `TrendSentiment.swift`
// and `Accessibility.swift` reasoning. The decisions are the load-bearing part,
// and a helper inside `#if canImport(SwiftUI)` can only ever be exercised on
// macOS; here they are asserted on every platform, and the thin view
// application in `FuaranNode.swift` is the only Apple-gated half.

import Foundation
import FuaranUI

/// Which transport a plan describes. The render-fidelity contract names a
/// distinct element per surface (`video` / `audio` on an HTML host); this is
/// that distinction in a form a native surface can switch on.
public enum MediaSurface: String, CaseIterable, Equatable, Sendable {
  case video
  case audio
}

/// The projection a media render arm applies: the resolved, floored, obligation-
/// checked shape of one `Media` node.
///
/// **There is deliberately no public initialiser.** `mediaPlaybackPlan` is the
/// only way to obtain one, and it is where the audio-has-no-autoplay obligation
/// is discharged — a public memberwise init would let a caller hand `autoplay:
/// true` to an audio surface, re-opening by an initialiser exactly what the
/// sealed `MediaKind` closes by its case set.
public struct MediaPlaybackPlan: Equatable, Sendable {
  public let surface: MediaSurface

  /// The accessible name, ALWAYS — there is no absent case, because `label` is
  /// mandatory on the wire and a transport is never decorative.
  ///
  /// **Precedence, where a node ALSO carries an `Accessibility.label`.** The
  /// node-level slot wins: it is the author saying this particular instance is
  /// named something else, the same precedence a node-level label has over an
  /// image's `alt`. On this surface that falls out of the render spine rather
  /// than needing a branch — `fuaranNodeBody` applies the node's accessibility
  /// projection AFTER the kind arm's view, and a later `.accessibilityLabel`
  /// replaces an earlier one. The reference host reaches the same precedence by
  /// the opposite mechanism (it serialises attributes to text, where a
  /// duplicate resolves FIRST-wins, so it emits the spec label only when the
  /// node-level attributes carry none). Do not "fix" this arm by suppressing
  /// the label when a trait is present — on SwiftUI that would invert the
  /// precedence rather than preserve it.
  public let accessibilityLabel: String

  /// The primary source put through the §19 URL floor — `nil` when the floor
  /// refused it.
  ///
  /// A refusal here is a STATE the arm renders, never a reason to drop the
  /// element: an element must have a source, so the reference tiers collapse a
  /// refused `src` to their refusal substitute and carry its marker. `nil` is
  /// that state in the shape this surface has for it, and it reads differently
  /// from `poster`'s `nil` for exactly that reason — see below.
  public let source: String?

  /// The poster frame — present ONLY when it is literal and passed the floor.
  ///
  /// §3.6.4's dropped-candidate rule applied to a single slot: a refused poster
  /// simply LEAVES. A video with no poster shows its first frame, which is a
  /// working rendering; a poster at the refusal URL is a broken image painted
  /// over the player. `nil` on `Audio`, on a `Video` with no poster, and on a
  /// poster the floor refused — three different absences the arm treats
  /// identically, which is the whole point of the rule.
  public let poster: String?

  public let controls: Bool
  public let loop: Bool

  /// `false` on EVERY audio plan, and not because it was defaulted — the
  /// `audio` case carries no slot for the initialiser to read.
  public let autoplay: Bool

  /// The pairing, by construction. Not a stored value, so it cannot disagree
  /// with `autoplay` in either direction: a surface MUST NOT mute a video the
  /// reader pressed play on, which is the same defect as unmuted autoplay in
  /// the other direction.
  public var muted: Bool { autoplay }
}

/// Build the plan for one `Media` node from its resolved bindings.
///
/// Bindings are resolved by the caller (the render arm, against its
/// `BindingContext`) and floored here — the order the reference host uses, and
/// the only one that is correct: a `Binding` may not carry a literal at all, so
/// flooring before resolution would be checking a placeholder.
///
/// `resolvedPoster` is `nil` where the node declares none. Passing a resolved
/// poster string for an `Audio` node is harmless and ignored: the surface has
/// nowhere to put it.
public func mediaPlaybackPlan(
  _ spec: MediaSpec, resolvedLabel: String, resolvedSrc: String, resolvedPoster: String? = nil
) -> MediaPlaybackPlan {
  let surface: MediaSurface
  let autoplay: Bool
  let poster: String?

  switch spec.kind {
  case .video(let declaredAutoplay, _):
    surface = .video
    autoplay = declaredAutoplay
    // Read the refusal from the floor's own verdict rather than by comparing
    // against whatever substitute it would offer.
    poster = resolvedPoster.flatMap { FuaranUrlPolicy.sanitize($0) }
  case .audio:
    // Nothing is read from the case here, and that is the obligation: `Audio`
    // declares no autoplay slot, so there is none to consult and none an edit
    // to this arm could start consulting.
    surface = .audio
    autoplay = false
    poster = nil
  }

  return MediaPlaybackPlan(
    surface: surface,
    accessibilityLabel: resolvedLabel,
    source: FuaranUrlPolicy.sanitize(resolvedSrc),
    poster: poster,
    controls: spec.controls,
    loop: spec.loop,
    autoplay: autoplay)
}
