// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The media playback projection (WIRE_FORMAT.md §3.6.6). These assertions run
// on EVERY platform, not only macOS — which is why the projection sits outside
// the `#if canImport(SwiftUI)` gate. The three obligations the spec states
// normatively are decisions, and a decision testable on only one platform is a
// decision nobody re-checks.

import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class MediaPlaybackTests: XCTestCase {
  private func binding(_ s: String) -> Binding { .staticValue(.ast(.string(s))) }

  private func video(autoplay: Bool = false, poster: String? = nil) -> MediaSpec {
    MediaSpec(
      kind: .video(autoplay: autoplay, poster: poster.map { binding($0) }),
      label: .literal("Studio walkthrough"),
      src: binding("/walkthrough.mp4"))
  }

  private func audio() -> MediaSpec {
    MediaSpec(
      kind: .audio, label: .literal("Curator's commentary"), src: binding("/commentary.mp3"))
  }

  // ── Obligation 1 — the accessible name, always ─────────────────────────────

  /// `label` is mandatory on the wire and a transport has no decorative case,
  /// so there is no branch and no empty-label pathway to test around: whatever
  /// the label resolves to IS the accessible name.
  func testTheAccessibleNameIsAlwaysCarried() {
    for spec in [video(), video(autoplay: true), audio()] {
      let plan = mediaPlaybackPlan(
        spec, resolvedLabel: "Studio walkthrough", resolvedSrc: "/clip.mp4")
      XCTAssertEqual(plan.accessibilityLabel, "Studio walkthrough")
    }
  }

  // ── Obligation 2 — autoplay NEVER without muted, in both directions ────────

  /// The pairing, over every plan this projection can produce. It is not an
  /// assertion about an implementation choice — `muted` is computed from
  /// `autoplay`, so the failing case is unrepresentable and this test's job is
  /// to pin that it stays so.
  func testAutoplayAndMutedAreTheSameDeclaration() {
    let declared = mediaPlaybackPlan(
      video(autoplay: true), resolvedLabel: "Ambient loop", resolvedSrc: "/ambient.mp4")
    XCTAssertTrue(declared.autoplay)
    XCTAssertTrue(declared.muted, "a host honouring autoplay MUST pair it with muted playback")

    // The converse defect: muting a video the reader pressed play on.
    let notDeclared = mediaPlaybackPlan(
      video(autoplay: false), resolvedLabel: "Studio walkthrough", resolvedSrc: "/w.mp4")
    XCTAssertFalse(notDeclared.autoplay)
    XCTAssertFalse(notDeclared.muted, "muted MUST NOT be asserted where autoplay is absent")
  }

  // ── Obligation 3 — Audio has NO autoplay pathway ───────────────────────────

  /// An audio plan never autoplays, and the reason is stronger than a default:
  /// the `MediaKind.audio` case declares no slot, so the projection has nothing
  /// to read.
  ///
  /// **What this test can and cannot say.** The load-bearing guarantee is a
  /// COMPILE-TIME one — `case audio` carries no associated value, so
  /// `{"$type":"Audio","autoplay":true}` has nowhere to land and no edit to the
  /// render arm can start honouring it. The companion assertion in
  /// `MediaVocabularyTests.testAudioAutoplayHasNowhereToLand` pins the decode
  /// half of that on the wire; this one pins the projection half.
  func testAudioNeverAutoplaysAndNeverMutes() {
    let plan = mediaPlaybackPlan(
      audio(), resolvedLabel: "Curator's commentary", resolvedSrc: "/commentary.mp3")
    XCTAssertEqual(plan.surface, .audio)
    XCTAssertFalse(plan.autoplay)
    XCTAssertFalse(plan.muted)
    XCTAssertNil(plan.poster, "an audio surface has nowhere to put a poster")
  }

  /// A poster handed to an audio plan is ignored rather than carried — the
  /// surface has no slot for it, so there is no half-honoured state.
  func testAPosterOfferedToAnAudioPlanIsIgnored() {
    let plan = mediaPlaybackPlan(
      audio(), resolvedLabel: "Commentary", resolvedSrc: "/c.mp3",
      resolvedPoster: "/poster.jpg")
    XCTAssertNil(plan.poster)
  }

  // ── The two URLs, and what a refusal means on each ─────────────────────────

  /// A refused POSTER simply leaves. A video with no poster shows its first
  /// frame, which is a working rendering; a poster at a refusal URL would be a
  /// broken image painted over the player.
  func testARefusedPosterIsDropped() {
    let plan = mediaPlaybackPlan(
      video(poster: "javascript:alert(1)"), resolvedLabel: "Walkthrough",
      resolvedSrc: "/w.mp4", resolvedPoster: "javascript:alert(1)")
    XCTAssertNil(plan.poster)
    XCTAssertNotNil(plan.source, "the primary source is unaffected by the poster's refusal")
  }

  func testAnAllowedPosterSurvivesTheFloor() {
    let plan = mediaPlaybackPlan(
      video(poster: "/walkthrough-poster.jpg"), resolvedLabel: "Walkthrough",
      resolvedSrc: "/walkthrough.mp4", resolvedPoster: "/walkthrough-poster.jpg")
    XCTAssertEqual(plan.poster, "/walkthrough-poster.jpg")
  }

  /// A refused SOURCE is a state, not a dropped element — the asymmetry with
  /// the poster is the whole of §3.6.6's rule, so it is pinned as a pair rather
  /// than as two independent facts.
  func testARefusedSourceIsAStateTheArmStillRenders() {
    let plan = mediaPlaybackPlan(
      video(), resolvedLabel: "Walkthrough", resolvedSrc: "data:video/mp4;base64,AAAA")
    XCTAssertNil(plan.source)
    XCTAssertEqual(
      plan.accessibilityLabel, "Walkthrough",
      "the element still renders, and still carries its accessible name")
  }

  // ── The two shared declarations, and their polarities ──────────────────────

  /// `controls` is the inverted one: a document gets the accessible setting for
  /// free and taking it away costs a key.
  func testControlsDefaultsOnAndLoopDefaultsOff() {
    let plan = mediaPlaybackPlan(video(), resolvedLabel: "W", resolvedSrc: "/w.mp4")
    XCTAssertTrue(plan.controls)
    XCTAssertFalse(plan.loop)
  }

  func testTheDeclarationsAreCarriedWhenSwitchedOffTheirDefaults() {
    var spec = video(autoplay: true)
    spec.controls = false
    spec.loop = true
    let plan = mediaPlaybackPlan(spec, resolvedLabel: "Ambient loop", resolvedSrc: "/ambient.mp4")
    XCTAssertFalse(plan.controls)
    XCTAssertTrue(plan.loop)
    XCTAssertTrue(plan.autoplay)
    XCTAssertTrue(plan.muted)
  }

  /// The surface distinction the render-fidelity contract names per element.
  func testSurfaceTracksTheVariant() {
    XCTAssertEqual(
      mediaPlaybackPlan(video(), resolvedLabel: "W", resolvedSrc: "/w.mp4").surface, .video)
    XCTAssertEqual(
      mediaPlaybackPlan(audio(), resolvedLabel: "C", resolvedSrc: "/c.mp3").surface, .audio)
  }
}
