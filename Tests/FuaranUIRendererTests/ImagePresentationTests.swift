// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The image presentation projection (WIRE_FORMAT.md §3.6.2–§3.6.5). Runs on
// every platform, for the reason `TrendSentimentTests` records: the decisions
// are the load-bearing half, and one testable only on macOS is one nobody
// re-checks.

import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class ImagePresentationTests: XCTestCase {
  private func binding(_ s: String) -> Binding { .staticValue(.ast(.string(s))) }

  private func image(
    src: String = "/harbour.jpg",
    fit: ImageFit = .natural,
    aspectRatio: ImageAspect = .natural,
    loading: ImageLoading = .eager,
    caption: TextSource? = nil,
    srcSet: [(String, Int)] = [],
    expandable: Bool = false
  ) -> ImageSpec {
    ImageSpec(
      alt: .literal("Fishing boats moored at first light"),
      src: binding(src),
      variant: .default,
      fit: fit,
      aspectRatio: aspectRatio,
      loading: loading,
      caption: caption,
      srcSet: srcSet.map { SrcSetEntry(src: binding($0.0), width: $0.1) },
      expandable: expandable)
  }

  private func plan(_ spec: ImageSpec, src: String = "/harbour.jpg") -> ImagePresentationPlan {
    imagePresentationPlan(
      spec,
      resolvedSrc: src,
      resolvedCandidates: spec.srcSet.map { entry in
        (
          url: {
            if case .staticValue(.ast(.string(let s))) = entry.src { return s } else { return "" }
          }(),
          width: entry.width
        )
      },
      resolvedCaption: spec.caption.map {
        if case .literal(let s) = $0 { return s } else { return "" }
      })
  }

  // ── §3.6.4 — the two orders, which are NOT the same order ──────────────────

  /// The wire keeps AUTHORED order; the renderer presents ASCENDING BY WIDTH.
  /// The corpus fixture is authored descending precisely so a host that
  /// conflated the two fails, so the input here is descending too — and the
  /// model must still hold it descending while the plan holds it ascending.
  func testCandidatesArePresentedAscendingWhileTheModelKeepsAuthoredOrder() {
    let spec = image(srcSet: [("/h-1600.jpg", 1600), ("/h-800.jpg", 800), ("/h-400.jpg", 400)])
    XCTAssertEqual(
      spec.srcSet.map(\.width), [1600, 800, 400],
      "the decoded model MUST preserve the author's order — a codec never re-sorts")
    XCTAssertEqual(
      plan(spec).candidates.map(\.width), [400, 800, 1600],
      "presentation order is the renderer's, and it is ascending by width")
  }

  /// A refused candidate is DROPPED, not neutered — and it is dropped BEFORE
  /// the ordering, so it never occupies a position.
  func testARefusedCandidateIsDroppedRatherThanEmitted() {
    let spec = image(srcSet: [("/h-800.jpg", 800), ("javascript:alert(1)", 400)])
    let candidates = imagePresentationPlan(
      spec, resolvedSrc: "/harbour.jpg",
      resolvedCandidates: [
        (url: "/h-800.jpg", width: 800), (url: "javascript:alert(1)", width: 400),
      ]
    ).candidates
    XCTAssertEqual(candidates.map(\.url), ["/h-800.jpg"])
  }

  /// Three different absences that denote the same document, and are therefore
  /// not distinguished: no slot, an explicit empty list, and every candidate
  /// refused.
  func testTheThreeEmptyCandidateStatesAreOneState() {
    XCTAssertTrue(plan(image()).candidates.isEmpty)
    XCTAssertTrue(plan(image(srcSet: [])).candidates.isEmpty)
    XCTAssertTrue(
      imagePresentationPlan(
        image(), resolvedSrc: "/harbour.jpg",
        resolvedCandidates: [(url: "javascript:alert(1)", width: 400)]
      ).candidates.isEmpty)
  }

  // ── §3.6.5 — the anchor, and the case that emits none ──────────────────────

  /// The expansion target is the PRIMARY source — never a candidate. A surface
  /// that put a thumbnail behind the link would pass every structural check and
  /// defeat the feature.
  func testTheExpansionTargetIsThePrimarySourceNotACandidate() {
    let spec = image(srcSet: [("/h-400.jpg", 400), ("/h-800.jpg", 800)], expandable: true)
    let p = plan(spec)
    XCTAssertEqual(p.expansion, "/harbour.jpg")
    XCTAssertFalse(p.expansionRefused)
  }

  /// A `src` the floor refused emits NO anchor: a link to nothing is the dead
  /// affordance §3.6.5 forbids. The image still renders — only the expansion
  /// leaves.
  func testARefusedSourceEmitsNoAffordance() {
    let p = imagePresentationPlan(
      image(src: "javascript:alert(1)", expandable: true),
      resolvedSrc: "javascript:alert(1)", resolvedCandidates: [])
    XCTAssertNil(p.expansion)
    XCTAssertTrue(p.expansionRefused, "the refusal is reportable, not merely absent")
  }

  /// The two ways `expansion` is `nil` stay distinguishable, which is the whole
  /// reason `expansionRefused` exists.
  func testAnUndeclaredExpansionIsNotARefusedOne() {
    let p = plan(image(expandable: false))
    XCTAssertNil(p.expansion)
    XCTAssertFalse(p.expansionRefused)
  }

  // ── §3.6.2 — tokens, and the box they reserve ──────────────────────────────

  /// `aspectRatio` reserves a box; `Natural` reserves nothing. The ratio is
  /// DERIVED from the token — never carried by the wire, which is the direction
  /// that keeps an author-supplied `"16 / 9"` inexpressible.
  func testAspectTokensProjectToReservedRatios() {
    XCTAssertNil(ImageAspect.natural.ratio)
    XCTAssertEqual(ImageAspect.square.ratio, 1.0)
    XCTAssertEqual(ImageAspect.fourThree.ratio!, 4.0 / 3.0, accuracy: 1e-12)
    XCTAssertEqual(ImageAspect.threeTwo.ratio!, 1.5, accuracy: 1e-12)
    XCTAssertEqual(ImageAspect.sixteenNine.ratio!, 16.0 / 9.0, accuracy: 1e-12)
  }

  /// `fit` and `aspectRatio` are independently declarable and neither is
  /// derived from the other — the pair reads as one in practice, which is
  /// exactly why the format keeps them apart.
  func testFitAndAspectAreCarriedIndependently() {
    let p = plan(image(fit: .cover, aspectRatio: .sixteenNine))
    XCTAssertEqual(p.fit, .cover)
    XCTAssertEqual(p.aspectRatio, .sixteenNine)

    let contained = plan(image(fit: .contain, aspectRatio: .natural))
    XCTAssertEqual(contained.fit, .contain)
    XCTAssertEqual(contained.aspectRatio, .natural)
  }

  /// `loading` is carried rather than dropped, and this surface does not yet
  /// act on it — the render floor has no fetching tier. Pinned so the boundary
  /// is a recorded state rather than an unnoticed omission.
  func testLoadingIsCarriedThroughUnacted() {
    XCTAssertEqual(plan(image(loading: .lazy)).loading, .lazy)
    XCTAssertEqual(plan(image()).loading, .eager)
  }

  // ── §3.6.3 — the caption binding ───────────────────────────────────────────

  func testACaptionIsCarriedResolvedAndItsAbsenceIsNotAnEmptyOne() {
    XCTAssertEqual(
      plan(image(caption: .literal("The harbour at dawn, 1908. Oil on canvas."))).caption,
      "The harbour at dawn, 1908. Oil on canvas.")
    XCTAssertNil(
      plan(image()).caption,
      "absent means NO wrapper at all — not a wrapper with an empty caption")
  }
}
