// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Phase 1548 — the render half of `FileUploadSpec.maxBytes` / `.maxFiles`
// (WIRE_FORMAT.md §3.6.23), asserted on the pure projection rather than in a
// composition, so it is re-checked on whatever machine the next change is made
// from rather than only on the macOS box.
//
// These are the SUPPORTING TESTS the declared exemption for
// `FileUpload/ceiling-recorded-never-enforced` in `RenderObligationTests.swift`
// names. An exemption that merely asserted "this surface emits no attribute
// bag" would be true and useless; what makes it honest is that the floor
// follows the same obligation's reasoning — record THAT a ceiling was declared,
// never its value — and that the following can fail if it stops doing so.

import XCTest

@testable import FuaranUI
@testable import FuaranUIRenderer

final class UploadCeilingTests: XCTestCase {
  private func upload(maxBytes: Int? = nil, maxFiles: Int? = nil, multiple: Bool = false)
    -> FileUploadSpec
  {
    FileUploadSpec(
      accept: ["application/pdf"], label: .literal("Attach a scan"), multiple: multiple,
      disabled: nil, dropTarget: false, acceptPaste: false, capture: nil, destination: nil,
      maxBytes: maxBytes, maxFiles: maxFiles)
  }

  /// §3.6.23 obligation 4, second half — an UNDECLARED ceiling earns no marker
  /// at all, so an upload written before this revision renders exactly as it
  /// did. The marker line is ABSENT rather than empty, which is what keeps the
  /// unbounded control visually identical to its pre-1548 self.
  func testAnUndeclaredCeilingEarnsNoMarker() {
    let m = uploadCeilingMarkers(upload())
    XCTAssertFalse(m.byteCeilingDeclared)
    XCTAssertFalse(m.fileCountCeilingDeclared)
    XCTAssertTrue(m.isEmpty)
    XCTAssertNil(m.summary)
  }

  /// The two members are carried APART, exactly as the corpus vectors carry
  /// them: a declared byte ceiling must not mark a count ceiling and vice
  /// versa, because no host may read either member as implying the other.
  func testEachCeilingIsMarkedOnItsOwn() {
    let bytes = uploadCeilingMarkers(upload(maxBytes: 5_242_880))
    XCTAssertTrue(bytes.byteCeilingDeclared)
    XCTAssertFalse(bytes.fileCountCeilingDeclared)
    XCTAssertEqual(bytes.summary, "per-file byte ceiling declared")

    let files = uploadCeilingMarkers(upload(maxFiles: 3, multiple: true))
    XCTAssertFalse(files.byteCeilingDeclared)
    XCTAssertTrue(files.fileCountCeilingDeclared)
    XCTAssertEqual(files.summary, "file-count ceiling declared")

    let both = uploadCeilingMarkers(upload(maxBytes: 5_242_880, maxFiles: 3, multiple: true))
    XCTAssertEqual(
      both.summary, "per-file byte ceiling declared · file-count ceiling declared",
      "a control stating both ceilings marks both, in the specification's own order")
  }

  /// **The load-bearing one.** No marker this floor renders may carry the
  /// ceiling's VALUE. A tier that cannot act on the number must not publish it,
  /// because publishing it invites the reader to believe an enforcement that is
  /// not there — and this arm enforces nothing at all, since it opens no picker.
  ///
  /// Asserted over the rendered text rather than over the booleans it is built
  /// from: the booleans structurally cannot carry a number, so a test over them
  /// could not fail. This one can, the moment someone "helpfully" interpolates
  /// the ceiling into the caption.
  func testNoMarkerEverCarriesTheCeilingsValue() {
    // Digits chosen to be unmistakable in a substring search and impossible to
    // arrive at by rounding.
    let m = uploadCeilingMarkers(upload(maxBytes: 5_242_881, maxFiles: 7, multiple: true))
    let summary = m.summary ?? ""
    XCTAssertFalse(summary.contains("5242881"), "the byte ceiling reached the render as a value")
    XCTAssertFalse(summary.contains("5,242,881"), "…in a grouped spelling")
    XCTAssertFalse(summary.contains("7"), "the count ceiling reached the render as a value")
    XCTAssertFalse(
      summary.contains(where: \.isNumber),
      "a marker on this tier records THAT a ceiling was declared and never its value — "
        + "WIRE_FORMAT.md §3.6.23 obligation 4")
  }

  /// The claim is DECLINED, and declined out loud. `enforced` is a field rather
  /// than an omission so a reader can tell a decision from an oversight; it
  /// becomes answerable the day this floor grows a picker.
  func testThisFloorClaimsNoEnforcement() {
    for m in [
      uploadCeilingMarkers(upload()),
      uploadCeilingMarkers(upload(maxBytes: 1)),
      uploadCeilingMarkers(upload(maxFiles: 1, multiple: true)),
    ] {
      XCTAssertFalse(m.enforced, "this floor opens no picker, so it enforces no ceiling")
    }
  }

  /// The values are WITHHELD FROM THE RENDER, not dropped from the model. An
  /// embedding app that adds a real picker reads them off the spec, so the
  /// projection must not be mistaken for the place the ceilings live.
  func testTheSpecStillCarriesBothValues() {
    let spec = upload(maxBytes: 5_242_880, maxFiles: 3, multiple: true)
    XCTAssertEqual(spec.maxBytes, 5_242_880)
    XCTAssertEqual(spec.maxFiles, 3)
  }
}
