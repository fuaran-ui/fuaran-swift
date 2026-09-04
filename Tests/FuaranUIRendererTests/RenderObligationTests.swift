// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// ============================================================================
//  Executable render-obligation conformance (WIRE_FORMAT.md §13) — this
//  surface's adoption. The Swift sibling of the reference tiers' suites.
//
//  Decode conformance here is corpus-driven and strong. Render obligations were
//  prose: §3.6.2–§3.6.6 and §25.4 state, in sentences, that an accessible name
//  is always carried, that `autoplay` never appears without `muted`, that an
//  audio transport has no autoplay pathway at all, that a refused source emits
//  no affordance, that an unregistered component is labelled rather than
//  guessed at. A surface can decode every fixture in the corpus and silently
//  fail every one of those — none is a missing discriminator arm, so no decode
//  test and no exhaustive `switch` reaches them.
//
//  So the manifest carries them now, and this suite asserts FROM the manifest
//  rather than from a hand list beside it. Three consequences, which are the
//  whole point:
//
//    * The ENUMERATION is the corpus artefact's. A newly declared obligation on
//      a kind this surface renders arrives here as a claim with no checker and
//      turns the suite RED — not as a paragraph a future reader may re-read.
//
//    * NOT CHECKED IS NOT PASSED. Every claim this surface does not assert is
//      printed by name with the section that states it, and fails the gate
//      unless it carries a DECLARED exemption. Silence is never an answer.
//
//    * The go-red property is PROVEN, twice. `statusOf` is exercised against a
//      claim no checker covers (the permanent negative probe below), and the
//      whole gate is exercised against a perturbed copy of the artefact through
//      `FUARAN_RENDER_FIDELITY` — never by writing to the shared corpus, which
//      is the oracle every sibling surface answers to.
//
//  **What "emitted output" means on THIS surface, and why two claims are
//  exempt rather than asserted.** The reference tiers assert in emitted HTML.
//  This one emits no document: it is a render projection whose normative
//  decisions live in pure plans outside the `#if canImport(SwiftUI)` gate
//  (`mediaPlaybackPlan`, `imagePresentationPlan`, `customPlaceholder`), with a
//  thin Apple-gated view application over them. Those plans ARE what this
//  surface produces, and they are what every checker below asserts over — never
//  the type declarations that shape them, except where a claim is discharged BY
//  the type system, which is said out loud where it happens.
//
//  Where a claim is about a DOCUMENT — an attribute always emitted, an element
//  nested inside another — this surface has no analogue and the honest answer
//  is a declared exemption naming the structural fact, not a checker that
//  asserts something adjacent and reads as coverage. Both are recorded in
//  `declaredExemptions` with their reasons, and both are printed on every run.
// ============================================================================

import Foundation
import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

// ─── Fixture builders ─────────────────────────────────────────────────────────

private func binding(_ s: String) -> Binding { .staticValue(.ast(.string(s))) }

private func videoSpec(autoplay: Bool = false, poster: String? = nil) -> MediaSpec {
  MediaSpec(
    kind: .video(autoplay: autoplay, poster: poster.map { binding($0) }),
    label: .literal("Studio walkthrough"),
    src: binding("/walkthrough.mp4"))
}

private func audioSpec() -> MediaSpec {
  MediaSpec(kind: .audio, label: .literal("Curator commentary"), src: binding("/commentary.mp3"))
}

private func imageSpec(
  src: String = "/harbour.jpg",
  caption: TextSource? = nil,
  srcSet: [(String, Int)] = [],
  expandable: Bool = false
) -> ImageSpec {
  ImageSpec(
    alt: .literal("Fishing boats moored at first light"),
    src: binding(src),
    variant: .default,
    caption: caption,
    srcSet: srcSet.map { SrcSetEntry(src: binding($0.0), width: $0.1) },
    expandable: expandable)
}

/// A destination the §19 URL floor refuses. This surface's floor is the SCHEME
/// half of §19 — it operates no egress policy, so a scheme refusal is the whole
/// of what it can refuse, and it is what the two "refused" obligations are about
/// here.
private let refused = "javascript:alert(1)"

private func track(
  _ kind: TrackKind, _ src: String, _ lang: String, _ label: String, isDefault: Bool = false
) -> TrackEntry {
  TrackEntry(
    kind: kind, src: binding(src), srcLang: lang, label: .literal(label), isDefault: isDefault)
}

private func embedSpec(
  src: String = "https://player.example/embed/harbour",
  permissions: [EmbedPermission] = [],
  aspectRatio: ImageAspect = .natural
) -> EmbedSpec {
  EmbedSpec(
    src: binding(src), title: .literal("Harbour restoration, part two"),
    permissions: permissions, aspectRatio: aspectRatio)
}

/// The corpus's own two-level hierarchy (`nodes/tree-1.json`), so the row
/// assertions run against the shape every host is certified on rather than one
/// invented here.
private func treeSpec(
  expandedStateKey: String? = nil, selectionStateKey: String? = nil
) -> TreeSpec {
  TreeSpec(
    items: [
      TreeItem(
        id: "goods", label: .literal("Goods"),
        children: [
          TreeItem(id: "cocoa", label: .literal("Cocoa")),
          TreeItem(id: "yarn", label: .literal("Yarn")),
        ]),
      TreeItem(id: "ledger", label: .literal("Ledger")),
    ],
    expandedStateKey: expandedStateKey, selectionStateKey: selectionStateKey)
}

// ─── The checkers ─────────────────────────────────────────────────────────────
//
// One per (kind, claim). Each pins BOTH directions where the obligation has two:
// an emission test alone cannot tell a projection that honours a conditional
// from one that produces the value unconditionally.

private func checkAccessibleNameAlways() throws {
  // All three shapes, because the label is mandatory for the KIND and not for
  // one arm of it. A projection carrying it only on `Video` passes a video-only
  // test, and a projection carrying it only where autoplay is absent passes a
  // test that never declares one.
  for (spec, name) in [
    (videoSpec(), "a video"), (videoSpec(autoplay: true), "an autoplaying video"),
    (audioSpec(), "an audio"),
  ] {
    let plan = mediaPlaybackPlan(spec, resolvedLabel: "Studio walkthrough", resolvedSrc: "/w.mp4")
    XCTAssertEqual(
      plan.accessibilityLabel, "Studio walkthrough",
      "\(name) carries the resolved label as its accessible name")
  }

  // The half a presence test misses: a REFUSED source must not cost the element
  // its name. The reference tiers still emit the aria-label over their refusal
  // substitute, and a surface that dropped the name with the source would leave
  // a nameless transport on the page.
  let refusedSource = mediaPlaybackPlan(
    videoSpec(), resolvedLabel: "Studio walkthrough", resolvedSrc: refused)
  XCTAssertNil(refusedSource.source, "the floor refused the source")
  XCTAssertEqual(
    refusedSource.accessibilityLabel, "Studio walkthrough",
    "…and the element still renders, still named")
}

private func checkAutoplayMutedPairing() throws {
  let autoplaying = mediaPlaybackPlan(
    videoSpec(autoplay: true), resolvedLabel: "Ambient loop", resolvedSrc: "/ambient.mp4")
  XCTAssertTrue(autoplaying.autoplay, "a declared autoplay is carried")
  XCTAssertTrue(
    autoplaying.muted,
    "and never without muted — every mainstream player blocks unmuted autoplay, so an unmuted honouring means nothing"
  )

  // The pairing runs one way, and this is the half a one-sided assertion
  // misses: `muted` unasked silences a video the reader started themselves.
  let plain = mediaPlaybackPlan(
    videoSpec(), resolvedLabel: "Studio walkthrough", resolvedSrc: "/walkthrough.mp4")
  XCTAssertFalse(plain.autoplay, "autoplay is not declared, so it must not be carried")
  XCTAssertFalse(plain.muted, "muted rides autoplay; unasked it is a behaviour change")

  // This surface goes further than the claim asks and makes the failing
  // combination UNREPRESENTABLE — `muted` is computed from `autoplay` and there
  // is no public initialiser through which a caller could separate them. The
  // assertions above are therefore not merely a check on today's values; they
  // are what turns red if that derivation is ever replaced by a second stored
  // bool free to drift from the first.
}

private func checkNoAutoplayPathway() throws {
  // DISCHARGED BY THE TYPE SYSTEM, and said out loud rather than dressed as an
  // output check: `MediaKind.audio` carries no associated value, so there is no
  // autoplay slot for the projection to read and no later edit to the `.audio`
  // branch can start honouring one. What is asserted here is that STRUCTURAL
  // fact and its consequence in the produced plan.
  let plan = mediaPlaybackPlan(
    audioSpec(), resolvedLabel: "Curator commentary", resolvedSrc: "/commentary.mp3")
  XCTAssertEqual(plan.surface, .audio)
  XCTAssertFalse(plan.autoplay, "an audio plan never autoplays — there is no slot to read")
  XCTAssertFalse(plan.muted, "an audio surface has no autoplay, so it has nothing to mute")

  // Offered a poster it cannot use, an audio plan still carries none: there is
  // no half-honoured state on that variant either.
  let offered = mediaPlaybackPlan(
    audioSpec(), resolvedLabel: "Curator commentary", resolvedSrc: "/c.mp3",
    resolvedPoster: "/poster.jpg")
  XCTAssertNil(offered.poster, "an audio surface has nowhere to put a poster")

  // The decode half of the same guarantee. A document that DECLARES audio
  // autoplay is not refused — the slot does not exist on that variant, so its
  // presence is not malformed — and the value has nowhere to land.
  let json = #"""
    {"id":"m","kind":{"$type":"Media","kind":{"$type":"Audio","autoplay":true},"label":"Commentary","src":{"$type":"Static","value":"/c.mp3"}}}
    """#
  guard case .media(let decoded) = try RenderProjection.decodeNode(json).kind else {
    return XCTFail("expected a Media node")
  }
  XCTAssertEqual(decoded.kind.typeName, "Audio")
  let fromWire = mediaPlaybackPlan(
    decoded, resolvedLabel: "Commentary", resolvedSrc: "/c.mp3")
  XCTAssertFalse(
    fromWire.autoplay,
    "a declared audio autoplay decodes to a surface that does not autoplay — the value has nowhere to land"
  )
}

private func checkRefusedSourceDropped() throws {
  let plan = mediaPlaybackPlan(
    videoSpec(poster: refused), resolvedLabel: "Walkthrough", resolvedSrc: "/walkthrough.mp4",
    resolvedPoster: refused)
  XCTAssertNil(
    plan.poster,
    "a refused poster is DROPPED, not carried at a refusal marker — a video with no poster shows its first frame, where a poster at a refusal destination is a broken image over the player"
  )
  XCTAssertNotNil(plan.source, "the primary source is unaffected by the poster's refusal")

  // The allow twin. Without it a projection that dropped EVERY poster would
  // pass the assertion above and this obligation would guard nothing.
  let allowed = mediaPlaybackPlan(
    videoSpec(poster: "/walkthrough-poster.jpg"), resolvedLabel: "Walkthrough",
    resolvedSrc: "/walkthrough.mp4", resolvedPoster: "/walkthrough-poster.jpg")
  XCTAssertEqual(allowed.poster, "/walkthrough-poster.jpg", "a local poster still renders")

  // §3.6.6 obligation 4 (Phase 1110) — the claim names a `track` source as well
  // as a `poster`, and a track takes the POSTER's disposition rather than the
  // primary source's: an element must have a source, but it need not have this
  // track, and a track at a refusal destination is a menu entry that opens onto
  // nothing.
  var withTracks = videoSpec()
  withTracks.tracks = [
    track(.captions, refused, "en", "English captions"),
    track(.subtitles, "/walkthrough.fr.vtt", "fr", "Sous-titres"),
  ]
  let trackPlan = mediaPlaybackPlan(
    withTracks, resolvedLabel: "Walkthrough", resolvedSrc: "/walkthrough.mp4")
  XCTAssertEqual(
    trackPlan.tracks.map(\.srcLang), ["fr"],
    "the refused track is dropped and the survivor is untouched")
  XCTAssertNotNil(trackPlan.source, "the primary source is unaffected by a track's refusal")
}

// ── Media text tracks (Phase 1110) ───────────────────────────────────────────

private func checkAuthoredChildOrder() throws {
  // The corpus's `media-video-tracks-2` shape: an order NO sort produces, which
  // is what makes this rule separately testable from `srcSet`'s. A projection
  // that sorted by kind, by language or by label would reorder this list; the
  // authored one is none of those.
  var spec = videoSpec()
  spec.tracks = [
    track(.subtitles, "/w.fr.vtt", "fr", "Sous-titres"),
    track(.captions, "/w.en.vtt", "en", "English captions", isDefault: true),
    track(.descriptions, "/w.de.vtt", "de", "Audiodeskription"),
  ]
  let plan = mediaPlaybackPlan(spec, resolvedLabel: "Walkthrough", resolvedSrc: "/w.mp4")
  XCTAssertEqual(
    plan.tracks.map(\.srcLang), ["fr", "en", "de"],
    "tracks are emitted in the AUTHORED order the wire carries, never re-sorted — a reader picks a track from a menu the user agent builds in document order, so ordering it would be rewriting someone else's menu"
  )

  // The half a single-list assertion misses: this rule is the OPPOSITE of
  // `srcSet`'s, and the two live in two files precisely so neither can be
  // "fixed" into the other. Assert the neighbour still sorts, or a change that
  // unified them would pass both obligations while breaking one.
  let imagePlan = imagePresentationPlan(
    imageSpec(srcSet: [("/b.jpg", 800), ("/a.jpg", 400)]),
    resolvedSrc: "/harbour.jpg",
    resolvedCandidates: [(url: "/b.jpg", width: 800), (url: "/a.jpg", width: 400)])
  XCTAssertEqual(
    imagePlan.candidates.map(\.width), [400, 800],
    "…while a srcset IS re-ordered: a browser picks one candidate by an algorithm, so ordering it is canonicalisation"
  )
}

private func checkSingleDefaultPerKind() throws {
  var spec = videoSpec()
  spec.tracks = [
    track(.captions, "/w.en.vtt", "en", "English captions", isDefault: true),
    track(.captions, "/w.en-verbose.vtt", "en", "English captions (verbose)", isDefault: true),
    track(.subtitles, "/w.fr.vtt", "fr", "Sous-titres", isDefault: true),
  ]
  let plan = mediaPlaybackPlan(spec, resolvedLabel: "Walkthrough", resolvedSrc: "/w.mp4")

  XCTAssertEqual(plan.tracks.count, 3, "the later election is still EMITTED — only its claim is dropped")
  XCTAssertEqual(
    plan.tracks.map(\.isDefault), [true, false, true],
    "the FIRST election of a kind is honoured and a later one carries no default; the election is per KIND, so a captions default and a subtitles default coexist"
  )

  // Two halves a one-document assertion misses. A document electing two
  // defaults is legal BYTES — the decoder must not refuse it, or this whole
  // resolution would be unreachable…
  let json = #"""
    {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video"},"label":"W","src":{"$type":"Static","value":"/w.mp4"},"tracks":[{"default":true,"kind":"Captions","label":"A","src":{"$type":"Static","value":"/a.vtt"},"srcLang":"en"},{"default":true,"kind":"Captions","label":"B","src":{"$type":"Static","value":"/b.vtt"},"srcLang":"en"}]}}
    """#
  guard case .media(let decoded) = try RenderProjection.decodeNode(json).kind else {
    return XCTFail("a double election is legal bytes and must decode")
  }
  XCTAssertEqual(decoded.tracks.map(\.isDefault), [true, true], "the WIRE keeps both elections")

  // …and the resolution must not fire where nothing competes, or a projection
  // that simply dropped every default would pass the assertion above.
  var single = videoSpec()
  single.tracks = [track(.captions, "/w.en.vtt", "en", "English captions", isDefault: true)]
  let singlePlan = mediaPlaybackPlan(single, resolvedLabel: "W", resolvedSrc: "/w.mp4")
  XCTAssertEqual(singlePlan.tracks.map(\.isDefault), [true], "an uncontested election is honoured")
}

private func checkTranscriptDisclosureNamed() throws {
  var spec = audioSpec()
  spec.transcript = .literal("The harbour was rebuilt twice: once after the storm of 1908.")
  let plan = mediaPlaybackPlan(spec, resolvedLabel: "Curator commentary", resolvedSrc: "/c.mp3")

  guard let transcript = plan.transcript else {
    return XCTFail("a declared transcript must reach the plan")
  }
  XCTAssertEqual(
    transcript.accessibilityLabel, "Curator commentary",
    "the disclosure carries the MEDIA's resolved label as its own accessible name, so a reader meeting it out of context is told which recording it transcribes"
  )
  XCTAssertTrue(transcript.text.hasPrefix("The harbour"), "and the text itself")

  // BESIDE the transport, never INSIDE it. On a surface with no document that
  // is exactly this: `tracks` is the element's child list and the transcript is
  // a PEER field, so an arm rendering children cannot render it among them. A
  // transcript smuggled into the child list would show up here as a fourth
  // track and as a `<track>` a browser would never display.
  XCTAssertTrue(
    plan.tracks.isEmpty,
    "the transcript is not a member of the element's children — placed there a browser would treat it as fallback content and never show it")

  // Absent means absent, and an EMPTY declaration is not an offer: advertising a
  // disclosure that opens onto nothing is the `Tooltip` obligation-5 shape one
  // kind over.
  XCTAssertNil(
    mediaPlaybackPlan(audioSpec(), resolvedLabel: "C", resolvedSrc: "/c.mp3").transcript)
  var blank = audioSpec()
  blank.transcript = .literal("   ")
  XCTAssertNil(
    mediaPlaybackPlan(blank, resolvedLabel: "C", resolvedSrc: "/c.mp3").transcript,
    "a transcript resolving to whitespace is no transcript")
}

// ── Embed (Phase 1111) ───────────────────────────────────────────────────────

private func checkEmbedAccessibleNameAlways() throws {
  // Every shape, because the title is mandatory for the KIND: a projection
  // carrying it only where a source survived, or only where permissions were
  // declared, passes a narrower test.
  for (spec, src, name) in [
    (embedSpec(), "https://player.example/embed/harbour", "a plain embed"),
    (embedSpec(permissions: [.allowScripts]), "https://player.example/embed/harbour", "a permitted embed"),
    (embedSpec(src: "http://player.example/x"), "http://player.example/x", "a refused embed"),
  ] {
    let plan = embedFramePlan(spec, resolvedTitle: "Harbour restoration, part two", resolvedSrc: src)
    XCTAssertEqual(
      plan.title, "Harbour restoration, part two",
      "\(name) carries the resolved title as its accessible name — a frame is a focus container a reader tabs INTO, so there is no decorative case")
  }
}

private func checkSandboxAlwaysExactlyDeclared() throws {
  // ALWAYS, and EMPTY when nothing is granted. This is the obligation a surface
  // fails by writing the obvious code — omitting the declaration on a
  // permissionless embed produces the same result as an UNSANDBOXED frame.
  let bare = embedFramePlan(embedSpec(), resolvedTitle: "T", resolvedSrc: "https://e.example/x")
  XCTAssertEqual(bare.sandbox, [], "an empty sandbox, which is total denial — never an absent one")

  // …and the type is what makes the always-half unfalsifiable: `sandbox` is
  // `[String]`, so there is no representation of "no sandbox" for an arm to
  // reach. Asserting the emptiness above without this would be asserting a
  // value where the guarantee is a TYPE.
  XCTAssertFalse(
    "\(type(of: bare.sandbox))".contains("Optional"),
    "the sandbox declaration is non-optional by construction; an Optional would make the unsandboxed frame expressible")

  // EXACTLY the declared relaxations, in the VOCABULARY's declaration order,
  // de-duplicated — so two documents naming the same set render identically
  // however they authored it.
  let scrambled = embedFramePlan(
    embedSpec(permissions: [.allowForms, .allowSameOrigin, .allowScripts, .allowForms]),
    resolvedTitle: "T", resolvedSrc: "https://e.example/x")
  XCTAssertEqual(
    scrambled.sandbox, ["allow-scripts", "allow-same-origin", "allow-forms"],
    "declaration order, de-duplicated — never the document's order")

  // `AllowFullscreen` is NOT a sandbox token. The corpus fixture carries exactly
  // that one permission for exactly this reason: a host that mapped the whole
  // enum onto sandbox tokens round-trips every other fixture and fails here.
  let fullscreen = embedFramePlan(
    embedSpec(permissions: [.allowFullscreen]), resolvedTitle: "T",
    resolvedSrc: "https://e.example/x")
  XCTAssertEqual(
    fullscreen.sandbox, [],
    "fullscreen is a permissions-policy directive, not a sandbox relaxation")
  XCTAssertEqual(fullscreen.allow, ["fullscreen"], "…and it rides `allow` instead")
  XCTAssertEqual(
    bare.allow, [],
    "an empty `allow` means the attribute is ABSENT — not the same statement as an empty sandbox, and only the sandbox's absence is dangerous")
}

private func checkRefusedEmbedSourceOmitted() throws {
  // The `embed` class (§19.1) is NARROWER than the general floor, and each of
  // these three is a value §19 accepts elsewhere. A surface reusing the general
  // floor here passes the javascript case and fails all three.
  for (src, why) in [
    ("http://player.example/x", "http is refused — a document any intermediary can rewrite is that intermediary's script running in a frame this page created"),
    ("/local/embed.html", "a schemeless reference is refused — a same-origin frame is where a document granted AllowSameOrigin + AllowScripts can remove the sandbox from its own frame element"),
    (refused, "and every scheme the general floor refuses stays refused"),
  ] {
    let plan = embedFramePlan(embedSpec(src: src), resolvedTitle: "T", resolvedSrc: src)
    XCTAssertNil(plan.source, why)
    XCTAssertTrue(
      plan.sourceRefused,
      "…and the refusal is RECORDED: 'nothing was declared' and 'this was refused' stay different facts")
    XCTAssertEqual(
      plan.title, "T", "the frame still renders, still named — a refusal costs the source, not the element")
  }

  // The allow twin. Without it a projection that refused EVERY source would
  // pass every assertion above and this obligation would guard nothing.
  let ok = embedFramePlan(
    embedSpec(), resolvedTitle: "T", resolvedSrc: "https://player.example/embed/harbour")
  XCTAssertEqual(ok.source, "https://player.example/embed/harbour", "an https document is admitted")
  XCTAssertFalse(ok.sourceRefused)

  // And the third state: nothing declared at all is NOT a refusal. An
  // `Optional` alone cannot tell those apart, which is why the plan carries
  // both facts.
  let undeclared = embedFramePlan(embedSpec(src: ""), resolvedTitle: "T", resolvedSrc: "")
  XCTAssertNil(undeclared.source)
  XCTAssertFalse(
    undeclared.sourceRefused,
    "an unresolved source is not an egress refusal — telling a reader their destination was rejected when the document never named one is a wrong diagnosis")
}

// ── Tree (Phase 1120) ────────────────────────────────────────────────────────

private func checkTreeAccessibleNameAlways() throws {
  let rows = flattenTreeRows(treeRowPlans(treeSpec()))
  XCTAssertEqual(rows.count, 4, "two roots and two children")

  // EVERY row, including the parent — a treeitem OWNS its child group, so a
  // name computed from contents would read the whole branch out as the row's
  // own name.
  XCTAssertEqual(
    rows.map(\.label), ["Goods", "Cocoa", "Yarn", "Ledger"],
    "every row states its OWN visible label as its accessible name")

  guard let goods = rows.first(where: { $0.id == "goods" }) else {
    return XCTFail("the parent row must be projected")
  }
  XCTAssertTrue(goods.hasChildren)
  XCTAssertEqual(
    goods.label, "Goods",
    "the parent's name is 'Goods' and NOT 'Goods Cocoa Yarn' — the failure mode this obligation exists for is a name that grew its branch")
  XCTAssertFalse(
    goods.label.contains("Cocoa"),
    "…stated as the negative too, because a computed name passes an equality test on a leaf and fails only on a parent")

  // The name is the row's own label whatever the row's state, so a collapsed or
  // unselected row is not left nameless.
  let stateful = flattenTreeRows(
    treeRowPlans(
      treeSpec(expandedStateKey: "openRows", selectionStateKey: "selectedRow"),
      expandedIds: [], selectedId: "ledger"))
  XCTAssertEqual(stateful.map(\.label), ["Goods", "Cocoa", "Yarn", "Ledger"])
  XCTAssertTrue(stateful.allSatisfy { !$0.label.isEmpty }, "no row is ever nameless")
}

private func checkAnchorAffordanceOnExpandable() throws {
  let expandable = imagePresentationPlan(
    imageSpec(expandable: true), resolvedSrc: "/harbour.jpg", resolvedCandidates: [])
  XCTAssertEqual(
    expandable.expansion, "/harbour.jpg",
    "a declared expansion targets the full-size asset the image already names")
  XCTAssertFalse(expandable.expansionRefused, "nothing was refused")

  let plainImage = imagePresentationPlan(
    imageSpec(), resolvedSrc: "/harbour.jpg", resolvedCandidates: [])
  XCTAssertNil(plainImage.expansion, "an undeclared expansion offers no affordance")

  // The target is the PRIMARY source, never a candidate. A surface that put a
  // thumbnail behind the expansion would satisfy every structural check and
  // defeat the feature — the reader would tap a thumbnail and be shown one.
  let withCandidates = imagePresentationPlan(
    imageSpec(srcSet: [("/harbour-400.jpg", 400)], expandable: true),
    resolvedSrc: "/harbour.jpg",
    resolvedCandidates: [(url: "/harbour-400.jpg", width: 400)])
  XCTAssertEqual(
    withCandidates.expansion, "/harbour.jpg", "the expansion targets the primary, not a candidate")
}

private func checkRefusedSrcNoAffordance() throws {
  let plan = imagePresentationPlan(
    imageSpec(src: refused, expandable: true), resolvedSrc: refused, resolvedCandidates: [])
  XCTAssertNil(
    plan.expansion,
    "a src the floor refused offers NO expansion — an affordance that cannot be honoured is worse than none"
  )
  XCTAssertTrue(
    plan.expansionRefused,
    "and the two absences stay distinguishable: a declaration over a refused source is not the same fact as no declaration"
  )

  // The image itself is still projected, in its refusal state. Without this leg
  // a projection that dropped the whole node would pass the assertion above,
  // and this obligation would be satisfied by a worse defect than the one it
  // guards.
  XCTAssertNil(plan.source, "the primary collapses to the refusal state")
  XCTAssertEqual(plan.fit, .natural, "…and the rest of the presentation is still projected")
}

private func checkSrcSetAscendingByWidth() throws {
  // Authored DESCENDING, so the assertion pins the ORDERING and not merely the
  // spelling: a surface emitting authored order would produce the same three
  // URLs and fail here. The wire preserves authored order deliberately — the
  // sort is the renderer's, which is why it lives in the plan.
  let ordered = imagePresentationPlan(
    imageSpec(srcSet: [
      ("/harbour-1600.jpg", 1600), ("/harbour-800.jpg", 800), ("/harbour-400.jpg", 400),
    ]),
    resolvedSrc: "/harbour.jpg",
    resolvedCandidates: [
      (url: "/harbour-1600.jpg", width: 1600), (url: "/harbour-800.jpg", width: 800),
      (url: "/harbour-400.jpg", width: 400),
    ])
  XCTAssertEqual(
    ordered.candidates.map(\.width), [400, 800, 1600], "candidates are ascending by width")
  XCTAssertEqual(
    ordered.candidates.map(\.url),
    ["/harbour-400.jpg", "/harbour-800.jpg", "/harbour-1600.jpg"])

  // The second half of the same obligation: a refused candidate is DROPPED, so
  // the primary remains the fallback rather than the list carrying a
  // destination the floor refused. Flooring runs BEFORE the ordering, so a
  // refused candidate never occupies a position either.
  let withRefused = imagePresentationPlan(
    imageSpec(srcSet: [("/harbour-400.jpg", 400), (refused, 1600)]),
    resolvedSrc: "/harbour.jpg",
    resolvedCandidates: [(url: "/harbour-400.jpg", width: 400), (url: refused, width: 1600)])
  XCTAssertEqual(
    withRefused.candidates.map(\.url), ["/harbour-400.jpg"],
    "the refused candidate is dropped and the surviving one is kept")
}

private func checkUnregisteredCustomLabelled() throws {
  // §25.4 — the UNCARDED path, which on this surface is the only path there is.
  // It holds no contract-card reader, so no card is ever available, every
  // `Custom` node takes this branch, and the identity-only placeholder is what
  // §25.4 asks of a host in that position. The carded branches — the summary,
  // the verdict marker, the withheld description on a contradicted hash — are
  // OUT OF SCOPE here for that reason, and this surface does NOT thereby claim
  // §25 adoption: that is a separate bar with its own table.
  let spec = CustomSpec(
    moduleId: "analytics", componentId: "sparkline",
    props: ["series": .string(#"{"points":[1,2,3]}"#)],
    contentHash: nil, exposedNodeIds: [])
  let placeholder = customPlaceholder(spec)

  XCTAssertEqual(
    placeholder.identity, "analytics/sparkline",
    "the placeholder names the component that did not render")
  XCTAssertEqual(placeholder.title, "Custom", "…and names the class of thing it is")

  // No prop VALUE reaches the reader: this surface was never asked to interpret
  // the node's props, and a value shown outside the component that gives it
  // meaning is a claim nobody made.
  for text in [placeholder.title, placeholder.identity] {
    XCTAssertFalse(text.contains("points"), "no prop value reaches the placeholder")
    XCTAssertFalse(text.contains("series"), "no prop name reaches the placeholder either")
  }

  // And nothing is INVENTED. Asserting the full string set exactly is what
  // catches a future edit that starts guessing a summary from the identity —
  // a confident wrong description being worse than none.
  XCTAssertEqual(
    placeholder, CustomPlaceholder(title: "Custom", identity: "analytics/sparkline"),
    "the placeholder is the identity and nothing else — no summary, no guess at appearance")

  // A declared content hash changes nothing here, because there is no card to
  // compare it against. Presenting it as a verdict would be a stronger claim
  // than this surface can reach.
  let hashed = customPlaceholder(
    CustomSpec(
      moduleId: "analytics", componentId: "sparkline", props: [:],
      contentHash: ContentHash(algorithm: "SHA256", hash: "a94a8fe5", strictness: .advisoryWarning),
      exposedNodeIds: []))
  XCTAssertEqual(hashed, placeholder, "an unverifiable hash is not surfaced as a verdict")
}

// ─── The registry ─────────────────────────────────────────────────────────────

/// Which (kind, claim) pairs this surface asserts, and how. Keyed by the claim's
/// WIRE token, because the enumeration it is matched against comes from the
/// artefact.
///
/// `@Sendable` because this is a global under Swift 6 strict concurrency: the
/// checkers are non-capturing free functions, so the annotation costs nothing
/// and records that none of them holds shared state.
private let checkers: [String: @Sendable () throws -> Void] = [
  "Media/accessible-name-always": checkAccessibleNameAlways,
  "Media/autoplay-muted-pairing": checkAutoplayMutedPairing,
  "Media/no-autoplay-pathway": checkNoAutoplayPathway,
  "Media/refused-source-dropped": checkRefusedSourceDropped,
  "Media/authored-child-order": checkAuthoredChildOrder,
  "Media/single-default-per-kind": checkSingleDefaultPerKind,
  "Media/transcript-disclosure-named": checkTranscriptDisclosureNamed,
  "Embed/accessible-name-always": checkEmbedAccessibleNameAlways,
  "Embed/sandbox-always-exactly-declared": checkSandboxAlwaysExactlyDeclared,
  "Embed/refused-embed-source-omitted": checkRefusedEmbedSourceOmitted,
  "Tree/accessible-name-always": checkTreeAccessibleNameAlways,
  "Image/anchor-affordance-on-expandable": checkAnchorAffordanceOnExpandable,
  "Image/refused-src-no-affordance": checkRefusedSrcNoAffordance,
  "Image/srcset-ascending-by-width": checkSrcSetAscendingByWidth,
  "Custom/unregistered-custom-labelled": checkUnregisteredCustomLabelled,
]

/// Obligations this surface declares it does NOT check, each with a reason.
///
/// **Non-empty is the expected state here, and it is the mechanism working
/// rather than the mechanism failing.** This is a render projection over the
/// reference core — no document, no attribute bag, no network image loader, no
/// playback engine — so two of the ten declared claims are about something this
/// surface structurally does not produce. A declared exemption with a reason is
/// a conformant answer; an obligation silently absent from the registry is not,
/// which is precisely the difference this map exists to keep visible.
private let declaredExemptions: [String: String] = [
  "Image/alt-always-emitted":
    "this surface emits no alternative-text attribute at all — it holds no attribute bag and no network image loader, so an image renders as a placeholder box whose visible text substitutes the word \"image\" for an empty alt, which collapses the very absent-versus-empty distinction the claim exists to protect; and the wire slot is mandatory and totally modelled here (ImageSpec.alt is a non-optional TextSource), so there is no absent case for a checker to distinguish from an empty one",
  "Image/figure-caption-outside-link":
    "the claim is about document containment — a caption that is not a descendant of the expansion anchor — and this surface emits no anchor element and no document; the expansion is projected as a bare URL string beside the caption as two independent fields of one plan, so there is no containment relation for a checker to observe, and the view tree that finally places them carries no text-inspection seam on any platform this suite runs on",
]

/// This surface's answer for one declared obligation.
///
/// The default reason is deliberately actionable: a claim arriving with no
/// checker must tell the next reader what to do about it, in the same words
/// every sibling surface uses.
private func statusOf(kind: String, claimId: String) -> ObligationOutcome {
  let key = "\(kind)/\(claimId)"
  if checkers[key] != nil { return .asserted }
  if let exemption = declaredExemptions[key] { return .unchecked(reason: exemption) }
  return .unchecked(
    reason:
      "no checker registered in RenderObligationTests.swift and no declared exemption — add one, or declare why this host cannot check it"
  )
}

// ─── The suite ────────────────────────────────────────────────────────────────

final class RenderObligationTests: XCTestCase {
  /// The artefact, or the right kind of stop.
  ///
  /// A missing artefact has two very different meanings and collapsing them
  /// into one clean skip is a vacuous green: on a standalone clone the skip is
  /// honest; where the corpus is plainly here and only the artefact is not, this
  /// gate would certify NOTHING while reporting success. Discriminate, and FAIL
  /// in the second case — the `CorpusTests` posture, applied to one file.
  private func requireManifest() throws -> RenderFidelityManifest {
    if RenderFidelityArtefact.isPresent { return try RenderFidelityArtefact.load() }

    let corpusDir = RenderFidelityArtefact.url.deletingLastPathComponent()
    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: corpusDir.path, isDirectory: &isDir),
      isDir.boolValue
    {
      XCTFail(
        "the wire-format-fixtures corpus is present at \(corpusDir.path) but render-fidelity.json "
          + "is not — this gate certified NOTHING. If the artefact moved or was renamed, correct "
          + "the locator rather than letting the harness skip.")
    }
    throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
  }

  /// Run one registered checker BY KEY, so a method and the registry cannot
  /// drift: a renamed claim fails here by name rather than leaving a method
  /// quietly asserting a key nothing declares.
  private func run(_ key: String) throws {
    guard let check = checkers[key] else {
      return XCTFail("no checker registered for \(key) — the registry and this method disagree")
    }
    try check()
  }

  // ── The gate ───────────────────────────────────────────────────────────────

  func testAssertsEveryObligationTheManifestDeclares() throws {
    let manifest = try requireManifest()
    let report = reportObligations(manifest: manifest, statusOf: statusOf)

    XCTAssertGreaterThan(
      report.count, 0,
      "the manifest declares no obligations at all — either the artefact is stale or this suite is reading the wrong file, and either way it is asserting nothing"
    )

    // NOT CHECKED IS NOT PASSED. Everything this surface did not assert is
    // printed by name and section BEFORE the gate decides, so an exempted claim
    // is visible in the run rather than inferable from its absence.
    let unmet = unassertedObligations(report)
    for line in unmet {
      print("  render obligation not asserted: \(describeObligationReport(line))")
    }

    let undeclared =
      unmet
      .filter { declaredExemptions["\($0.kind)/\($0.claimId)"] == nil }
      .map { "\($0.kind)/\($0.claimId) [\($0.section)]" }
      .sorted()

    XCTAssertEqual(
      undeclared, [],
      "a render obligation this surface owes has no checker: assert it, or add a declared exemption saying why this surface cannot"
    )
  }

  // ── The permanent negative probe ───────────────────────────────────────────

  func testReportsAnObligationWithNoCheckerAsUnchecked() throws {
    // The shape a NEWLY-DECLARED obligation takes on the day it lands: a
    // kind/claim pair the registry does not cover. Without this probe the gate
    // above could be green because the classification never reports anything —
    // the completeness check that cannot fail.
    let outcome = statusOf(kind: "Markdown", claimId: "accessible-name-always")
    guard case .unchecked(let reason) = outcome else {
      return XCTFail("an unregistered (kind, claim) must be reported UNCHECKED, got \(outcome)")
    }
    XCTAssertTrue(
      reason.contains("no checker registered"), "in words a reader can act on — got: \(reason)")

    // …and the gate's own filter must classify it as unasserted, which is what
    // turns the suite red.
    let probe = ObligationReport(
      kind: "Markdown", claimId: "accessible-name-always", statement: "", section: "probe",
      outcome: outcome)
    XCTAssertEqual(unassertedObligations([probe]).count, 1)
    XCTAssertTrue(
      describeObligationReport(probe).hasPrefix(
        "Markdown/accessible-name-always [probe]: UNCHECKED ("),
      "the report line names the claim, its section and its outcome")
  }

  // ── The vocabulary seam ────────────────────────────────────────────────────

  func testResolvesEveryDeclaredClaimAgainstTheClosedVocabulary() throws {
    // A row naming a claim the vocabulary omits is unresolvable: a surface
    // keying its registry off the vocabulary could never report it, and a
    // surface must never accept a claim it cannot name.
    let manifest = try requireManifest()
    let vocabulary = Set(manifest.obligationVocabulary.map(\.id))

    XCTAssertGreaterThan(vocabulary.count, 0, "the artefact carries no obligation vocabulary")

    let unresolvable =
      allObligations(manifest)
      .filter { !vocabulary.contains($0.obligation.id) }
      .map { "\($0.kind)/\($0.obligation.id)" }
      .sorted()
    XCTAssertEqual(
      unresolvable, [], "a kind declares an obligation the closed vocabulary does not carry")

    // Every claim carries a section and a statement. An obligation with no
    // section is an assertion about a surface's habits, not about the
    // specification, and is not admissible.
    for entry in allObligations(manifest) {
      let key = "\(entry.kind)/\(entry.obligation.id)"
      XCTAssertTrue(
        entry.obligation.section.contains("WIRE_FORMAT.md"), "\(key): no spec section")
      XCTAssertFalse(entry.obligation.statement.isEmpty, "\(key): no normative statement")
    }
  }

  // ── The registry is not itself a second source of truth ────────────────────

  func testRegistersNoCheckerForAnObligationTheManifestDoesNotDeclare() throws {
    // A checker for a claim no row declares is a stale assertion: it passes
    // forever and guards a contract that has moved, which is exactly the drift
    // the generated artefact exists to remove. Declared exemptions are held to
    // the same bar — an exemption from an obligation nobody declares is a
    // reason nobody needs.
    let manifest = try requireManifest()
    let declared = Set(allObligations(manifest).map { "\($0.kind)/\($0.obligation.id)" })

    XCTAssertEqual(
      checkers.keys.filter { !declared.contains($0) }.sorted(), [],
      "a checker asserts an obligation no manifest row declares — either the row was removed or the checker was never declared"
    )
    XCTAssertEqual(
      declaredExemptions.keys.filter { !declared.contains($0) }.sorted(), [],
      "an exemption is declared from an obligation no manifest row declares")
  }

  // ── The checkers themselves ────────────────────────────────────────────────
  //
  // One method per registered claim, so a failing obligation names the claim it
  // broke rather than surfacing as one opaque red test. XCTest discovers
  // methods rather than generating cases from a collection, so the naming is
  // done here and `run(_:)` keeps it honest against the registry.

  func testOwesMediaAccessibleNameAlways() throws { try run("Media/accessible-name-always") }
  func testOwesMediaAutoplayMutedPairing() throws { try run("Media/autoplay-muted-pairing") }
  func testOwesMediaNoAutoplayPathway() throws { try run("Media/no-autoplay-pathway") }
  func testOwesMediaRefusedSourceDropped() throws { try run("Media/refused-source-dropped") }
  func testOwesMediaAuthoredChildOrder() throws { try run("Media/authored-child-order") }
  func testOwesMediaSingleDefaultPerKind() throws { try run("Media/single-default-per-kind") }
  func testOwesMediaTranscriptDisclosureNamed() throws {
    try run("Media/transcript-disclosure-named")
  }
  func testOwesEmbedAccessibleNameAlways() throws { try run("Embed/accessible-name-always") }
  func testOwesEmbedSandboxAlwaysExactlyDeclared() throws {
    try run("Embed/sandbox-always-exactly-declared")
  }
  func testOwesEmbedRefusedEmbedSourceOmitted() throws {
    try run("Embed/refused-embed-source-omitted")
  }
  func testOwesTreeAccessibleNameAlways() throws { try run("Tree/accessible-name-always") }
  func testOwesImageAnchorAffordanceOnExpandable() throws {
    try run("Image/anchor-affordance-on-expandable")
  }
  func testOwesImageRefusedSrcNoAffordance() throws { try run("Image/refused-src-no-affordance") }
  func testOwesImageSrcsetAscendingByWidth() throws { try run("Image/srcset-ascending-by-width") }
  func testOwesCustomUnregisteredCustomLabelled() throws {
    try run("Custom/unregistered-custom-labelled")
  }

  /// Every registered checker has a method above. Without this, adding a checker
  /// to the registry and forgetting its method would leave the claim reported as
  /// `asserted` by `statusOf` while nothing ever ran it — the gate green over an
  /// assertion that does not exist.
  func testEveryRegisteredCheckerHasAMethod() {
    let named = Set([
      "Media/accessible-name-always", "Media/autoplay-muted-pairing", "Media/no-autoplay-pathway",
      "Media/refused-source-dropped", "Media/authored-child-order",
      "Media/single-default-per-kind", "Media/transcript-disclosure-named",
      "Embed/accessible-name-always", "Embed/sandbox-always-exactly-declared",
      "Embed/refused-embed-source-omitted", "Tree/accessible-name-always",
      "Image/anchor-affordance-on-expandable",
      "Image/refused-src-no-affordance", "Image/srcset-ascending-by-width",
      "Custom/unregistered-custom-labelled",
    ])
    XCTAssertEqual(
      Set(checkers.keys).symmetricDifference(named), [],
      "the registry and the per-claim test methods disagree — a checker with no method never runs")
  }
}
