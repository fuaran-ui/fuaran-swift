// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The platform-baseline wave's DECODE leg, corpus-independent — the
// `MediaVocabularyTests` shape for the five capabilities adopted together:
// media text tracks (§3.6.6), `Embed` (§3.6.8), the tooltip trait (§3.1),
// `Combobox` (§3.6.9) and `Tree` (§3.6.12, §21.5).
//
// **Why these exist beside the corpus leg.** `CorpusTests` asserts that every
// fixture decodes and every reject fixture refuses with the pinned code and
// path, which is the conformance bar — but it says nothing about WHAT decoded.
// A slot silently dropped on the floor passes the corpus leg perfectly: three
// tooltip fixtures round-tripped here for a whole wave with the hint discarded,
// and the reject vector that should have caught it decoded happily, because rule
// 2 tolerates an unknown key. So these assert the VALUES, one capability at a
// time, in the words each specification uses.

import Foundation
import XCTest

@testable import FuaranUI

final class PlatformBaselineVocabularyTests: XCTestCase {
  private func node(_ json: String) throws -> Node { try RenderProjection.decodeNode(json) }

  private func refusal(_ json: String) -> FuaranDecodeError? {
    do {
      _ = try RenderProjection.decodeNode(json)
      return nil
    } catch let e as FuaranDecodeError {
      return e
    } catch {
      return nil
    }
  }

  // ── Media text tracks (Phase 1110) ─────────────────────────────────────────

  func testTracksDecodeWithEveryMemberAndKeepTheirAuthoredOrder() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video"},"label":"Studio walkthrough","src":{"$type":"Static","value":"/w.mp4"},"tracks":[{"default":true,"kind":"Captions","label":"English captions","src":{"$type":"Static","value":"/w.en.vtt"},"srcLang":"en"},{"kind":"Subtitles","label":"Sous-titres","src":{"$type":"Static","value":"/w.fr.vtt"},"srcLang":"fr"}]}}
      """#
    guard case .media(let spec) = try node(json).kind else { return XCTFail("expected .media") }
    XCTAssertEqual(spec.tracks.count, 2)
    XCTAssertEqual(spec.tracks[0].kind, .captions)
    XCTAssertEqual(spec.tracks[0].srcLang, "en")
    XCTAssertEqual(spec.tracks[0].label, .literal("English captions"))
    XCTAssertTrue(spec.tracks[0].isDefault)
    // The one omitted-at-false slot restores to false rather than to nil.
    XCTAssertFalse(spec.tracks[1].isDefault)
    XCTAssertEqual(
      spec.tracks.map(\.srcLang), ["en", "fr"],
      "the AUTHORED order survives decode — a decoder that sorted would make the render obligation unmeetable")
  }

  func testAnAbsentTracksSlotDecodesToTheEmptyListNeverNil() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Audio"},"label":"Commentary","src":{"$type":"Static","value":"/c.mp3"}}}
      """#
    guard case .media(let spec) = try node(json).kind else { return XCTFail("expected .media") }
    XCTAssertEqual(
      spec.tracks, [],
      "an absent slot and an empty one denote the same document, so the model has no third state")
    XCTAssertNil(
      spec.transcript,
      "…where `transcript` IS an ordinary optional: absent means the document offers none, which is a different statement from offering an empty one")
  }

  func testATranscriptDecodesAsAText() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Audio"},"label":"Commentary","src":{"$type":"Static","value":"/c.mp3"},"transcript":"The harbour was rebuilt twice."}}
      """#
    guard case .media(let spec) = try node(json).kind else { return XCTFail("expected .media") }
    XCTAssertEqual(spec.transcript, .literal("The harbour was rebuilt twice."))
  }

  func testAMissingSrcLangIsRefusedAtTheIndEXEDPath() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video"},"label":"W","src":{"$type":"Static","value":"/w.mp4"},"tracks":[{"kind":"Captions","label":"English","src":{"$type":"Static","value":"/w.en.vtt"}}]}}
      """#
    let error = refusal(json)
    XCTAssertEqual(error?.code, .missingField)
    XCTAssertEqual(
      error?.path, "$.kind.tracks[0].srcLang",
      "the path carries the array INDEX, so a document with four tracks names the one at fault")
  }

  func testAStringifiedDefaultIsRefusedRatherThanCoerced() throws {
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video"},"label":"W","src":{"$type":"Static","value":"/w.mp4"},"tracks":[{"default":"true","kind":"Captions","label":"English","src":{"$type":"Static","value":"/w.en.vtt"},"srcLang":"en"}]}}
      """#
    let error = refusal(json)
    XCTAssertEqual(error?.code, .wrongType)
    XCTAssertEqual(error?.path, "$.kind.tracks[0].default")
  }

  func testMetadataIsNotATrackKind() throws {
    // The set is CLOSED at four. `Metadata`'s cues are rendered by no user agent
    // and read only by script, so a declarative document naming it would state
    // an intent no conformant host could honour.
    let json = #"""
      {"id":"m","kind":{"$type":"Media","kind":{"$type":"Video"},"label":"W","src":{"$type":"Static","value":"/w.mp4"},"tracks":[{"kind":"Metadata","label":"Cues","src":{"$type":"Static","value":"/w.vtt"},"srcLang":"en"}]}}
      """#
    let error = refusal(json)
    XCTAssertEqual(error?.code, .unknownDuCase)
    XCTAssertEqual(
      error?.path, "$.kind.tracks[0].kind",
      "a BARE enum reports at the field's own path — there is no `$type` member here to send an author to")
  }

  // ── Embed (Phase 1111) ─────────────────────────────────────────────────────

  func testAnEmbedDecodesWithItsPermissionsAndAspect() throws {
    let json = #"""
      {"id":"e","kind":{"$type":"Embed","aspectRatio":"SixteenNine","permissions":["AllowFullscreen","AllowScripts"],"src":{"$type":"Static","value":"https://player.example/embed/harbour"},"title":"Harbour restoration, part two"}}
      """#
    guard case .embed(let spec) = try node(json).kind else { return XCTFail("expected .embed") }
    XCTAssertEqual(spec.title, .literal("Harbour restoration, part two"))
    XCTAssertEqual(
      spec.permissions, [.allowFullscreen, .allowScripts],
      "the AUTHORED order survives decode; the vocabulary's order is imposed at render time")
    XCTAssertEqual(spec.aspectRatio, .sixteenNine, "the slot REUSES ImageAspect")
  }

  func testAnAbsentPermissionsListMeansTotalDenial() throws {
    let json = #"""
      {"id":"e","kind":{"$type":"Embed","src":{"$type":"Static","value":"https://e.example/x"},"title":"T"}}
      """#
    guard case .embed(let spec) = try node(json).kind else { return XCTFail("expected .embed") }
    XCTAssertEqual(
      spec.permissions, [],
      "empty means TOTAL DENIAL, so the wire-cheapest document is also the most locked-down one")
    XCTAssertEqual(spec.aspectRatio, .natural, "and the ratio omits at its identity")
  }

  func testAMissingEmbedTitleIsRefused() throws {
    let json = #"""
      {"id":"e","kind":{"$type":"Embed","src":{"$type":"Static","value":"https://e.example/x"}}}
      """#
    let error = refusal(json)
    XCTAssertEqual(error?.code, .missingField)
    XCTAssertEqual(error?.path, "$.kind.title")
  }

  func testAnUnknownPermissionIsRefusedRatherThanDropped() throws {
    // The token an author reaches for from memory. Dropping it would turn a
    // document asking for something this vocabulary has no name for into one
    // asking for LESS — which reads as success.
    let json = #"""
      {"id":"e","kind":{"$type":"Embed","permissions":["allow-top-navigation"],"src":{"$type":"Static","value":"https://e.example/x"},"title":"T"}}
      """#
    let error = refusal(json)
    XCTAssertEqual(error?.code, .unknownDuCase)
    XCTAssertEqual(error?.path, "$.kind.permissions[0]")
  }

  func testANonStringPermissionIsRefused() throws {
    let json = #"""
      {"id":"e","kind":{"$type":"Embed","permissions":[true],"src":{"$type":"Static","value":"https://e.example/x"},"title":"T"}}
      """#
    let error = refusal(json)
    XCTAssertEqual(error?.code, .wrongType)
    XCTAssertEqual(
      error?.path, "$.kind.permissions[0]",
      "a bare `true` is refused rather than read as a present-and-enabled flag — a host coercing it would have to invent WHICH permission it names")
  }

  func testTheDecoderDoesNotApplyTheEgressFloor() throws {
    // §19.1 is a RENDER-time obligation and not a wire constraint: a document
    // naming an `http` embed source is a VALID wire document and the decoder
    // must carry it through unchanged. A decoder that refused it here would
    // make the value unobservable to the surface that has to record the refusal.
    let json = #"""
      {"id":"e","kind":{"$type":"Embed","src":{"$type":"Static","value":"http://player.example/x"},"title":"T"}}
      """#
    guard case .embed(let spec) = try node(json).kind else { return XCTFail("expected .embed") }
    XCTAssertEqual(spec.src.literalString, "http://player.example/x")
    guard case .rejected = spec.sanitizedSrc else {
      return XCTFail("…and the accessor still refuses it, which is where the floor lives")
    }
  }

  func testTheEmbedClassIsNarrowerThanTheGeneralFloor() throws {
    // Three values §19 accepts and §19.1 does not, plus one it does. This is the
    // whole content of the class, and a surface reusing the general floor passes
    // only the last.
    let cases: [(String, Bool)] = [
      ("https://player.example/x", true),
      ("http://player.example/x", false),
      ("/local/embed.html", false),
      ("//player.example/x", false),
    ]
    for (url, admitted) in cases {
      XCTAssertEqual(
        FuaranUrlPolicy.sanitizeEmbed(url) != nil, admitted,
        "\(url) should \(admitted ? "be admitted" : "be refused") by the embed class")
      // …and the general floor is unchanged by its existence: the first three
      // are all things §19 accepts, which is what makes the narrowing real.
      if url != "//player.example/x" {
        XCTAssertNotNil(FuaranUrlPolicy.sanitize(url), "\(url) is still fine under the general floor")
      }
    }
  }

  // ── The tooltip trait (Phase 1112) ─────────────────────────────────────────

  func testTheTooltipTraitDecodesOnTheEnvelope() throws {
    let json = #"""
      {"id":"t","kind":{"$type":"Button","label":"Rebuild index","onClick":{"$type":"Notify","channel":"rebuild","payload":{}},"variant":"Secondary"},"tooltip":"Re-reads every document."}
      """#
    XCTAssertEqual(
      try node(json).tooltip, .literal("Re-reads every document."),
      "the hint is a node-level TRAIT beside `accessibility`, not a field of any kind")
  }

  func testTheTooltipTraitTakesTheI18nForm() throws {
    let json = #"""
      {"id":"t","kind":{"$type":"Metric","label":"Median latency","value":{"$type":"Static","value":128}},"tooltip":{"$type":"I18n","args":{},"key":"metric.latency.hint"}}
      """#
    XCTAssertEqual(
      try node(json).tooltip, .i18n(key: "metric.latency.hint", args: [:]),
      "a TextSource, so the hint is authored, translated and bindable exactly as content is")
  }

  func testANonTextTooltipIsRefused() throws {
    let error = refusal(#"{"id":"t","kind":{"$type":"Markdown","text":"Body"},"tooltip":42}"#)
    XCTAssertEqual(error?.code, .wrongType)
    XCTAssertEqual(error?.path, "$.tooltip")
  }

  func testAKindLevelTooltipIsStillAnIgnoredUnknownKey() throws {
    // `ButtonSpec` carries a legacy host-only `tooltip` slot which is never
    // emitted and never decoded. It is an unknown key inside `kind`, tolerated
    // under rule 2 — NOT a second spelling of the trait, and adopting the trait
    // must not have turned it into one.
    let json = #"""
      {"id":"t","kind":{"$type":"Button","label":"Go","onClick":{"$type":"Notify","channel":"c","payload":{}},"tooltip":"host-only","variant":"Primary"}}
      """#
    XCTAssertNil(try node(json).tooltip, "a `tooltip` inside `kind` reaches the envelope trait not at all")
  }

  // ── Combobox (Phase 1113) ──────────────────────────────────────────────────

  func testAComboboxDecodesOnChoicesValueContract() throws {
    let json = #"""
      {"id":"f","kind":{"$type":"Form","fields":[{"id":"country","kind":{"$type":"Combobox","onChange":"<closure>","options":{"$type":"Static","value":[{"label":"France","value":"fra"}]},"value":{"$type":"Static","value":"fra"}},"label":"Country","required":true}],"onSubmit":{"$type":"Chain","ops":[]},"submitLabel":"Save"}}
      """#
    guard case .form(let form) = try node(json).kind,
      case .combobox(let options, let value, let free, let onChange) = form.fields[0].kind
    else { return XCTFail("expected a Combobox field") }
    XCTAssertEqual(options, .staticValue(.options([SelectOption(value: "fra", label: .literal("France"))])))
    XCTAssertEqual(value, .staticValue(.stringOpt("fra")))
    XCTAssertNotNil(onChange)
    XCTAssertFalse(
      free,
      "the SHORTEST combobox document is the CONSTRAINED one — a host reading absence as 'free text admitted' round-trips these bytes perfectly and is wrong about what the document permits")
  }

  func testAnAbsentComboboxValueAutoBindsExactlyAsAChoiceWould() throws {
    let json = #"""
      {"id":"f","kind":{"$type":"Form","fields":[{"id":"city","kind":{"$type":"Combobox","options":{"$type":"Query","dependsOn":["country"],"name":"cities"}},"label":"City","required":false}],"onSubmit":{"$type":"Chain","ops":[]},"submitLabel":"Search"}}
      """#
    guard case .form(let form) = try node(json).kind,
      case .combobox(let options, let value, _, let onChange) = form.fields[0].kind
    else { return XCTFail("expected a Combobox field") }
    XCTAssertEqual(
      options, .query(name: "cities", dependsOn: ["country"]),
      "a Query binding in the ordinary options slot IS the async suggestion feed — no vocabulary of its own")
    XCTAssertNil(onChange, "declarative: an omitted handler arms the write-back default")

    // The migration property: the SAME auto-binding a Choice gets, which is what
    // makes `$type` the only difference between the two documents.
    let asChoice = #"""
      {"id":"f","kind":{"$type":"Form","fields":[{"id":"city","kind":{"$type":"Choice","options":{"$type":"Query","dependsOn":["country"],"name":"cities"}},"label":"City","required":false}],"onSubmit":{"$type":"Chain","ops":[]},"submitLabel":"Search"}}
      """#
    guard case .form(let choiceForm) = try node(asChoice).kind,
      case .choice(_, let choiceValue, _) = choiceForm.fields[0].kind
    else { return XCTFail("expected a Choice field") }
    XCTAssertEqual(
      value, choiceValue,
      "the constrained combobox IS a searchable select: a document migrating between the two changes its $type and nothing else")
  }

  func testAllowFreeTextIsNotCoerced() throws {
    let json = #"""
      {"id":"f","kind":{"$type":"Form","fields":[{"id":"tag","kind":{"$type":"Combobox","allowFreeText":"yes","options":{"$type":"Static","value":[]}},"label":"Tag","required":false}],"onSubmit":{"$type":"Chain","ops":[]},"submitLabel":"Save"}}
      """#
    let error = refusal(json)
    XCTAssertEqual(error?.code, .wrongType)
    XCTAssertEqual(
      error?.path, "$.kind.fields[0].kind.allowFreeText",
      "a truthiness rule would widen the field on \"no\" and \"false\" alike")
  }

  func testAComboboxWithNoOptionsIsNotAControl() throws {
    let json = #"""
      {"id":"f","kind":{"$type":"Form","fields":[{"id":"tag","kind":{"$type":"Combobox"},"label":"Tag","required":false}],"onSubmit":{"$type":"Chain","ops":[]},"submitLabel":"Save"}}
      """#
    XCTAssertEqual(refusal(json)?.code, .missingField)
  }

  // ── Tree (Phase 1120) ──────────────────────────────────────────────────────

  func testATreeDecodesItsHierarchyAndItsTwoStateKeys() throws {
    let json = #"""
      {"id":"t","kind":{"$type":"Tree","expandedStateKey":"openRows","items":[{"children":[{"children":[{"id":"manifest","label":"Manifest"}],"id":"1823","label":"1823"}],"icon":"folder","id":"archive","label":"Archive"}]}}
      """#
    guard case .tree(let spec) = try node(json).kind else { return XCTFail("expected .tree") }
    XCTAssertEqual(spec.expandedStateKey, "openRows")
    XCTAssertNil(spec.selectionStateKey, "the tree does not select — and that is a different state from selecting nothing")
    XCTAssertEqual(spec.items.count, 1)
    XCTAssertEqual(spec.items[0].icon, "folder")
    XCTAssertEqual(spec.items[0].children[0].children[0].label, .literal("Manifest"))
    XCTAssertEqual(
      spec.items[0].children[0].children[0].children, [],
      "a leaf omits `children` entirely — two keys and nothing else, which is most of a real hierarchy")
  }

  func testATreeCarriesItsSelectionKeyAndHandler() throws {
    let json = #"""
      {"id":"t","kind":{"$type":"Tree","items":[{"id":"harbour","label":"Harbour"}],"onSelect":"<closure>","selectionStateKey":"selectedRow"}}
      """#
    guard case .tree(let spec) = try node(json).kind else { return XCTFail("expected .tree") }
    XCTAssertEqual(spec.selectionStateKey, "selectedRow")
    XCTAssertNotNil(spec.onSelect)
  }

  func testARowMissingItsIdOrLabelIsRefusedAtEveryLevel() throws {
    XCTAssertEqual(
      refusal(#"{"id":"t","kind":{"$type":"Tree","items":[{"label":"Goods"}]}}"#)?.path,
      "$.kind.items[0].id")
    XCTAssertEqual(
      refusal(#"{"id":"t","kind":{"$type":"Tree","items":[{"id":"goods"}]}}"#)?.path,
      "$.kind.items[0].label")
    // One level DOWN, because a host whose child walker is looser than its root
    // walker passes the other two.
    XCTAssertEqual(
      refusal(
        #"{"id":"t","kind":{"$type":"Tree","items":[{"children":[{"label":"Cocoa"}],"id":"goods","label":"Goods"}]}}"#
      )?.path,
      "$.kind.items[0].children[0].id")
  }

  func testADuplicateRowIdIsAcceptedBecauseUniquenessIsAnEmitObligation() throws {
    // §8.1's position, transferred: duplicate detection is a whole-tree
    // property, a streaming decoder is not required to carry the id set, and
    // there is no error code for it. A decoder that accepts one is conformant.
    let json = #"""
      {"id":"t","kind":{"$type":"Tree","items":[{"id":"same","label":"A"},{"id":"same","label":"B"}]}}
      """#
    guard case .tree(let spec) = try node(json).kind else { return XCTFail("expected .tree") }
    XCTAssertEqual(spec.items.map(\.id), ["same", "same"])
  }

  // ── §21.5 — the item axis ──────────────────────────────────────────────────

  func testItemNestingIsBoundedOnItsOwnAxis() throws {
    // A hierarchy at the bound decodes; one past it is refused as too DEEP,
    // with the path naming the row that breached. This is the axis neither the
    // node counter nor the syntactic bound can see — a whole hierarchy lives
    // inside ONE node and costs about two JSON levels per row.
    func tree(_ depth: Int) -> String {
      var row = #"{"id":"leaf","label":"Leaf"}"#
      for i in stride(from: depth - 2, through: 0, by: -1) {
        row = #"{"children":[\#(row)],"id":"r\#(i)","label":"Row"}"#
      }
      return #"{"id":"t","kind":{"$type":"Tree","items":[\#(row)]}}"#
    }

    XCTAssertNoThrow(
      try node(tree(WireLimits.maxNodeDepth)),
      "a hierarchy AT the bound is one every host must decode")

    let error = refusal(tree(WireLimits.maxNodeDepth + 1))
    XCTAssertEqual(error?.code, .limitExceeded)
    XCTAssertTrue(
      error?.message.contains("tree-item nesting") == true,
      "…and it is diagnosed as ITEM nesting, not as node nesting or as malformed JSON — a wrong diagnosis sends the author to repair the wrong thing; got: \(error?.message ?? "nothing)")")

    // The axes are SEPARATE, not shared. A deep tree must not consume node
    // depth, or a document nesting a legal tree inside a legal node tree would
    // be refused for a breach neither half committed.
    let flex = #"{"$type":"Flex","direction":"Vertical","wrap":false}"#
    let nested = #"""
      {"id":"a","kind":{"$type":"Box","children":[{"id":"b","kind":{"$type":"Box","children":[\#(tree(WireLimits.maxNodeDepth))],"layout":\#(flex),"role":"Group"}}],"layout":\#(flex),"role":"Group"}}
      """#
    XCTAssertNoThrow(
      try node(nested), "a full-depth hierarchy inside two boxes costs two node levels, not twenty-six")
  }
}
