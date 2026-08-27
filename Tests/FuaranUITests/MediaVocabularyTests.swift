// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The media-wave decode leg (WIRE_FORMAT.md §3.6.2–§3.6.6): the `ImageSpec`
// presentation set and the `Media` kind, read into the sealed model.
//
// Corpus-independent by design (the `ModelTests` posture), so they run in a
// standalone checkout. The corpus harness in `CorpusTests` is the coverage
// oracle — every one of these shapes is also a fixture there; these are the
// assertions about what the decoded VALUES are, which a
// "decodes without throwing" harness structurally cannot make.

import XCTest

@testable import FuaranUI

final class MediaVocabularyTests: XCTestCase {

  // ── §3.6.2 — the three presentation tokens ─────────────────────────────────

  func testImagePresentationTokensDecode() throws {
    let json = #"""
      {"id":"image-presentation-1","kind":{"$type":"Image","alt":"The harbour at dawn","aspectRatio":"SixteenNine","fit":"Cover","loading":"Lazy","src":{"$type":"Static","value":"/hero.jpg"},"variant":"Default"}}
      """#
    guard case .image(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected .image")
    }
    XCTAssertEqual(spec.fit, .cover)
    XCTAssertEqual(spec.aspectRatio, .sixteenNine)
    XCTAssertEqual(spec.loading, .lazy)
  }

  /// A document written before the slots existed decodes to today's behaviour —
  /// the identity defaults, TOTAL rather than `nil`, so no reader downstream has
  /// to re-decide what absence meant.
  func testAbsentPresentationSlotsAreTheIdentityDefaults() throws {
    let json = #"""
      {"id":"image-1","kind":{"$type":"Image","alt":"A chart","src":{"$type":"Static","value":"/c.png"},"variant":"Default"}}
      """#
    guard case .image(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected .image")
    }
    XCTAssertEqual(spec.fit, .natural)
    XCTAssertEqual(spec.aspectRatio, .natural)
    XCTAssertEqual(spec.loading, .eager)
    XCTAssertNil(spec.caption)
    XCTAssertTrue(spec.srcSet.isEmpty)
    XCTAssertFalse(spec.expandable)
  }

  /// The token vocabularies are CLOSED — a CSS ratio is refused at the bare
  /// slot with no `.$type` suffix (Phase 1073's ruled path).
  func testACssRatioIsRefusedAtTheBareSlot() {
    let json = #"""
      {"id":"i","kind":{"$type":"Image","alt":"Hero","aspectRatio":"16/9","src":{"$type":"Static","value":"/h.jpg"},"variant":"Default"}}
      """#
    XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
      guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
      XCTAssertEqual(e.code, .unknownDuCase)
      XCTAssertEqual(e.path, "$.kind.aspectRatio")
    }
  }

  // ── §3.6.3 — the caption is a TextSource, not a String ─────────────────────

  func testACaptionIsATextSourceAndCarriesEveryCase() throws {
    let bare = #"""
      {"id":"c","kind":{"$type":"Image","alt":"Boats","caption":"The harbour at dawn, 1908.","src":{"$type":"Static","value":"/h.jpg"},"variant":"Default"}}
      """#
    guard case .image(let literal) = try RenderProjection.decodeNode(bare).kind else {
      return XCTFail("expected .image")
    }
    XCTAssertEqual(literal.caption, .literal("The harbour at dawn, 1908."))

    // The rule a surface narrowing the slot to `String` would break: every case
    // of the DU rides it, so a caption is i18n-capable on exactly the terms
    // `alt` is.
    let i18n = #"""
      {"id":"c","kind":{"$type":"Image","alt":"Boats","caption":{"$type":"I18n","args":{},"key":"gallery.harbour"},"src":{"$type":"Static","value":"/h.jpg"},"variant":"Default"}}
      """#
    guard case .image(let translated) = try RenderProjection.decodeNode(i18n).kind else {
      return XCTFail("expected .image")
    }
    guard case .i18n(let key, _) = translated.caption else {
      return XCTFail("a caption must carry every TextSource case, not just a literal")
    }
    XCTAssertEqual(key, "gallery.harbour")
  }

  // ── §3.6.4 — absent means EMPTY, never null ────────────────────────────────

  /// The single most likely cross-host divergence in the slot: a decoder
  /// answering `nil` for an absent `srcSet` produces a value the format's own
  /// encoder cannot round-trip. The Swift model makes it unrepresentable —
  /// `[SrcSetEntry]`, not `[SrcSetEntry]?` — and this pins the decode half.
  func testAbsentSrcSetIsTheEmptyListAndAnExplicitNullIsRefused() throws {
    let absent = #"""
      {"id":"i","kind":{"$type":"Image","alt":"Boats","src":{"$type":"Static","value":"/h.jpg"},"variant":"Default"}}
      """#
    guard case .image(let spec) = try RenderProjection.decodeNode(absent).kind else {
      return XCTFail("expected .image")
    }
    XCTAssertEqual(spec.srcSet, [])

    // Absence already has a spelling; admitting a second would let two
    // conformant hosts emit different canonical bytes for one document.
    let explicitNull = #"""
      {"id":"i","kind":{"$type":"Image","alt":"Boats","src":{"$type":"Static","value":"/h.jpg"},"srcSet":null,"variant":"Default"}}
      """#
    XCTAssertThrowsError(try RenderProjection.decodeNode(explicitNull)) { error in
      guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
      XCTAssertEqual(e.code, .wrongType)
      XCTAssertEqual(e.path, "$.kind.srcSet")
    }
  }

  /// Authored order is preserved through decode — the corpus fixture is
  /// authored DESCENDING precisely so a re-sorting codec fails it.
  func testSrcSetPreservesAuthoredOrder() throws {
    let json = #"""
      {"id":"i","kind":{"$type":"Image","alt":"Boats","src":{"$type":"Static","value":"/h.jpg"},"srcSet":[{"src":{"$type":"Static","value":"/h-1600.jpg"},"width":1600},{"src":{"$type":"Static","value":"/h-800.jpg"},"width":800},{"src":{"$type":"Static","value":"/h-400.jpg"},"width":400}],"variant":"Default"}}
      """#
    guard case .image(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected .image")
    }
    XCTAssertEqual(spec.srcSet.map(\.width), [1600, 800, 400])
  }

  /// The positive-width floor is a DECODE rule, and zero is refused as firmly
  /// as a negative: a `0w` candidate is not a small image, it is one a client
  /// can never select. The entry is named by INDEX, so a well-formed entry
  /// first must not mask the second.
  func testANonPositiveWidthIsRefusedNamingItsIndex() {
    for width in ["0", "-400"] {
      let json = """
        {"id":"i","kind":{"$type":"Image","alt":"Hero","src":{"$type":"Static","value":"/h.jpg"},"srcSet":[{"src":{"$type":"Static","value":"/h-800.jpg"},"width":800},{"src":{"$type":"Static","value":"/h-0.jpg"},"width":\(width)}],"variant":"Default"}}
        """
      XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
        guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
        XCTAssertEqual(e.code, .wrongType)
        XCTAssertEqual(e.path, "$.kind.srcSet[1].width")
      }
    }
  }

  // ── §3.6.5 — the expansion declaration ─────────────────────────────────────

  func testExpandableDecodesAndDefaultsFalse() throws {
    let declared = #"""
      {"id":"i","kind":{"$type":"Image","alt":"Boats","expandable":true,"src":{"$type":"Static","value":"/h.jpg"},"variant":"Default"}}
      """#
    guard case .image(let spec) = try RenderProjection.decodeNode(declared).kind else {
      return XCTFail("expected .image")
    }
    XCTAssertTrue(spec.expandable)
  }

  /// A stringified boolean is REFUSED rather than coerced. A truthiness rule
  /// would have to rule on `"false"` and `""` as well, and two hosts ruling
  /// differently would disagree about whether a document declares an affordance
  /// at all.
  func testAStringifiedExpandableIsRefused() {
    let json = #"""
      {"id":"i","kind":{"$type":"Image","alt":"Hero","expandable":"true","src":{"$type":"Static","value":"/h.jpg"},"variant":"Default"}}
      """#
    XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
      guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
      XCTAssertEqual(e.code, .wrongType)
      XCTAssertEqual(e.path, "$.kind.expandable")
    }
  }

  // ── §3.6.6 — one kind, two variants ────────────────────────────────────────

  func testVideoDecodesWithBothBoolDefaultsOmitted() throws {
    let json = #"""
      {"id":"media-video-1","kind":{"$type":"Media","kind":{"$type":"Video"},"label":"Studio walkthrough","src":{"$type":"Static","value":"/walkthrough.mp4"}}}
      """#
    let node = try RenderProjection.decodeNode(json)
    XCTAssertEqual(node.kind.typeName, "Media")
    XCTAssertEqual(node.kind.category, .display)
    guard case .media(let spec) = node.kind else { return XCTFail("expected .media") }
    XCTAssertEqual(spec.label, .literal("Studio walkthrough"))
    // `controls` is omitted at TRUE — the inverted polarity, deliberate because
    // a transportless media element cannot be paused by a keyboard user at all.
    XCTAssertTrue(spec.controls)
    XCTAssertFalse(spec.loop)
    guard case .video(let autoplay, let poster) = spec.kind else {
      return XCTFail("expected the Video variant")
    }
    XCTAssertFalse(autoplay)
    XCTAssertNil(poster)
  }

  func testVideoCarriesItsPosterInsideTheCaseObject() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video","poster":{"$type":"Static","value":"/p.jpg"}},"label":"Walkthrough","src":{"$type":"Static","value":"/w.mp4"}}}
      """#
    guard case .media(let spec) = try RenderProjection.decodeNode(json).kind,
      case .video(_, let poster) = spec.kind
    else { return XCTFail("expected a Video variant") }
    XCTAssertNotNil(poster, "the poster rides INSIDE the case object, not beside it")
  }

  func testAllThreeBoolsOffTheirDefaultsAtOnce() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","controls":false,"kind":{"$type":"Video","autoplay":true},"label":"Ambient loop","loop":true,"src":{"$type":"Static","value":"/ambient.mp4"}}}
      """#
    guard case .media(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected .media")
    }
    XCTAssertFalse(spec.controls)
    XCTAssertTrue(spec.loop)
    guard case .video(let autoplay, _) = spec.kind else { return XCTFail("expected Video") }
    XCTAssertTrue(autoplay)
  }

  func testAudioDecodesFromTheBareDiscriminator() throws {
    let json = #"""
      {"id":"media-audio-1","kind":{"$type":"Media","kind":{"$type":"Audio"},"label":"Curator's commentary","src":{"$type":"Static","value":"/commentary.mp3"}}}
      """#
    guard case .media(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected .media")
    }
    XCTAssertEqual(spec.kind, .audio)
    XCTAssertEqual(spec.kind.typeName, "Audio")
  }

  /// **The obligation this decode leg exists to pin.** A document carrying
  /// `{"$type":"Audio","autoplay":true}` decodes to an audio surface that does
  /// not autoplay, because the value has NOWHERE TO LAND — `MediaKind.audio`
  /// carries no associated value. Note the document is not REFUSED: the wire
  /// rule is that the slot does not exist on this variant, not that its
  /// presence is malformed.
  ///
  /// This is stronger than a default of `false`, and the strength is structural
  /// rather than asserted: a slot defaulting to off is one a document can
  /// switch on, and there is no document this format wants to be able to state
  /// in which a page begins making sound unbidden.
  func testAudioAutoplayHasNowhereToLand() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Audio","autoplay":true},"label":"Commentary","src":{"$type":"Static","value":"/c.mp3"}}}
      """#
    guard case .media(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected .media")
    }
    XCTAssertEqual(
      spec.kind, .audio,
      "the Audio case has no autoplay slot, so the value is not carried anywhere")
  }

  /// The variant is `$type`-discriminated, so an unknown case reports at
  /// `$.kind.kind.$type` — the Binding/TextSource position, not the bare-enum
  /// one. The set is closed at two, so admitting a third surface later is an
  /// ADDITION rather than a re-meaning of shipped bytes.
  func testAnUnknownVariantIsRefusedAtTheDiscriminatorPath() {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Stream"},"label":"Live feed","src":{"$type":"Static","value":"/live.m3u8"}}}
      """#
    XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
      guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
      XCTAssertEqual(e.code, .unknownDuCase)
      XCTAssertEqual(e.path, "$.kind.kind.$type")
    }
  }

  /// `label` is REQUIRED — the one place the media contract differs from
  /// `Image`'s. There is no value to default to that would not be a fabricated
  /// name for someone else's recording.
  func testAMissingLabelIsRefused() {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video"},"src":{"$type":"Static","value":"/clip.mp4"}}}
      """#
    XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
      guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
      XCTAssertEqual(e.code, .missingField)
      XCTAssertEqual(e.path, "$.kind.label")
    }
  }

  /// A stringified `autoplay` is refused rather than coerced, on the slot where
  /// a truthiness rule would make one host start playing a video another host
  /// leaves still.
  func testAStringifiedAutoplayIsRefused() {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video","autoplay":"true"},"label":"Ambient loop","src":{"$type":"Static","value":"/ambient.mp4"}}}
      """#
    XCTAssertThrowsError(try RenderProjection.decodeNode(json)) { error in
      guard let e = error as? FuaranDecodeError else { return XCTFail("wrong error type") }
      XCTAssertEqual(e.code, .wrongType)
      XCTAssertEqual(e.path, "$.kind.kind.autoplay")
    }
  }

  /// The URL floor accessors reach both media URLs. A media source and a poster
  /// are each fetched with no user act, so both carry the same obligation as an
  /// image's `src` — and the accessors are how a render arm discharges it.
  func testTheFloorAccessorsReachBothMediaUrls() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video","poster":{"$type":"Static","value":"javascript:alert(1)"}},"label":"W","src":{"$type":"Static","value":"/w.mp4"}}}
      """#
    guard case .media(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected .media")
    }
    XCTAssertEqual(spec.sanitizedSrc, .allowed("/w.mp4"))
    guard case .rejected = spec.sanitizedPoster else {
      return XCTFail("a javascript: poster must be refused by the floor")
    }
  }

  /// The candidate accessor likewise — a `srcSet` entry is a URL a client
  /// fetches with no user act, so a slot that skipped the floor would be a
  /// documented way around it.
  func testTheFloorAccessorReachesSrcSetCandidates() throws {
    let json = #"""
      {"id":"i","kind":{"$type":"Image","alt":"Boats","src":{"$type":"Static","value":"/h.jpg"},"srcSet":[{"src":{"$type":"Static","value":"javascript:alert(1)"},"width":400}],"variant":"Default"}}
      """#
    guard case .image(let spec) = try RenderProjection.decodeNode(json).kind else {
      return XCTFail("expected .image")
    }
    guard case .rejected = spec.srcSet[0].sanitizedSrc else {
      return XCTFail("a javascript: candidate must be refused by the floor")
    }
  }
}
