// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The upload-ceiling projection — `FileUploadSpec.maxBytes` / `.maxFiles`
// (WIRE_FORMAT.md §3.6.23, Phase 1548) read into what this surface can honestly
// do with them.
//
// ## What this floor can and cannot answer
//
// §3.6.23 states five render obligations. Four of the five turn on a SELECTION,
// and this floor meets none: the `FileUpload` arm renders a labelled, disabled-
// aware button and opens no file picker at all, so there is no pick to refuse
// (obligation 1), no refusal to report (obligation 2), and no `file-read` event
// to gate (obligation 3, which is a server-driven host's in any case). The fifth
// — that a declared ceiling never relaxes a host's own bound — is satisfied
// vacuously here, because nothing on this path admits a file to bound.
//
// That leaves obligation 4, whose normative sentence this projection follows
// literally: a tier that cannot ACT on a ceiling records only THAT one was
// declared, never its value, "because nothing on that path can act on the number
// and publishing it would invite a reader to believe otherwise". The obligation
// is written for the static no-script tier and its `data-` attribute markers,
// and this surface emits no attribute bag and no document — which is why
// `FileUpload/ceiling-recorded-never-enforced` is a DECLARED EXEMPTION in
// `RenderObligationTests.swift` rather than an asserted claim. The reasoning
// behind the sentence is not attribute-shaped, though, and it applies here
// unchanged: a native control that displayed `max 5 MB` beside a button that
// enforces nothing would make the same false promise a valued marker would.
//
// So the plan below is deliberately VALUE-FREE. It is the whole of what an
// unenforcing floor may say, and the fields are booleans rather than the numbers
// precisely so that no arm downstream can render a ceiling as though it held.
//
// **The values are still DECODED and still carried** — `FileUploadSpec` holds
// both members, they round-trip, and an embedding app that adds a real picker
// reads them from the spec. What is withheld is the RENDER, not the data.
//
// Pure, and deliberately OUTSIDE the SwiftUI gate — the `TooltipProjection.swift`
// reasoning: the decisions are what matter, and a decision testable on only one
// platform is a decision nobody re-checks.

import Foundation
import FuaranUI

/// The read-markers an unenforcing floor may record for one upload's declared
/// ceilings: THAT each was declared, never its value.
public struct UploadCeilingMarkers: Equatable, Sendable {
  /// A `maxBytes` was declared on the control.
  public let byteCeilingDeclared: Bool

  /// A `maxFiles` was declared on the control.
  public let fileCountCeilingDeclared: Bool

  /// Whether this surface claims to ENFORCE either ceiling.
  ///
  /// **Always `false`, and it is a field rather than an omission** — the
  /// `TooltipProjection.focusStopClaimed` reasoning. A reader of the plan can
  /// see that the claim was considered and declined; a missing field would
  /// leave them unable to tell a decision from an oversight. It becomes
  /// answerable the day this floor grows a picker, and the field is where that
  /// answer goes.
  public let enforced: Bool

  /// Neither ceiling was declared. An UNDECLARED ceiling earns no marker at all
  /// — §3.6.23 obligation 4's second half — so this is the case in which a
  /// conformant surface renders nothing extra.
  public var isEmpty: Bool { !byteCeilingDeclared && !fileCountCeilingDeclared }

  /// The marker line, or `nil` where there is nothing to record.
  ///
  /// Carries no number, by construction: it is built from the booleans above,
  /// so there is no path by which a value could reach it.
  public var summary: String? {
    var parts: [String] = []
    if byteCeilingDeclared { parts.append("per-file byte ceiling declared") }
    if fileCountCeilingDeclared { parts.append("file-count ceiling declared") }
    guard !parts.isEmpty else { return nil }
    return parts.joined(separator: " · ")
  }
}

/// Project one upload's declared ceilings into the markers this floor may show.
public func uploadCeilingMarkers(_ spec: FileUploadSpec) -> UploadCeilingMarkers {
  UploadCeilingMarkers(
    byteCeilingDeclared: spec.maxBytes != nil,
    fileCountCeilingDeclared: spec.maxFiles != nil,
    enforced: false)
}
