// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The render-fidelity manifest's obligation surface (WIRE_FORMAT.md §13), read
// from the shared corpus artefact, plus the reporting shape every adopting
// surface uses.
//
// The reporting shape is declared here — rather than each surface inventing a
// way to say "we did not check that" — so the sibling implementations answer
// the same question in the same words. It is the Swift sibling of the reference
// tiers' coverage surface, not a transpile of one: same vocabulary, same three
// outcomes, same report line, expressed with an `enum` carrying its reason as an
// associated value, which is what this language has instead of a tagged union.
//
// **Test-local, and deliberately so.** This is a conformance harness, not a
// consumer-facing capability: nothing in the shipped library reads the manifest,
// and publishing a decoder for it would be claiming a surface area no consumer
// asked for. If a consumer ever needs the artefact at runtime, that is its own
// adoption with its own bar.

import Foundation

// ─── The artefact ─────────────────────────────────────────────────────────────

/// One entry of the CLOSED vocabulary of checkable claims the artefact
/// enumerates at its top level.
///
/// Closed is the load-bearing word. An open free-form vocabulary would let a
/// surface accept a claim it has no checker for; a closed one means a surface
/// can enumerate what exists independently of the rows it happens to read, and
/// report an id it does not implement.
struct ObligationVocabularyEntry: Decodable, Equatable {
  let id: String
  let meaning: String
}

/// One checkable claim a kind owes, bound to the section that states it.
struct RenderObligation: Decodable, Equatable {
  /// The vocabulary token. Resolvable against `obligationVocabulary` or the row
  /// is unresolvable — a surface must never accept a claim it cannot name.
  let id: String
  /// The normative sentence FOR THAT KIND. The same claim reads differently on a
  /// transport (an accessible name is mandatory) and on a decorative image (it
  /// is the empty string), which is why the statement travels with the row and
  /// not with the vocabulary entry.
  let statement: String
  /// The section that states the claim. An obligation with no section is an
  /// assertion about a surface's habits rather than about the specification,
  /// and is not admissible.
  let section: String
}

/// One `kinds` row, narrowed to the part this harness reads.
///
/// The artefact carries more per row (`sensitive`, `source`, `fallback`, `rich`,
/// `fixtures`, `contract`); `Decodable` ignores keys we do not declare, so a row
/// gaining a field is not a decode failure here. Growth in the artefact must not
/// break a surface that reads one slice of it.
struct RenderFidelityKind: Decodable {
  let kind: String
  let obligations: [RenderObligation]

  private enum CodingKeys: String, CodingKey { case kind, obligations }

  init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    kind = try c.decode(String.self, forKey: .kind)
    // Absent reads as "declares no checkable claim", which is what an empty
    // array already means — the artefact emits the key on every row today, and
    // tolerating its absence costs nothing while an opaque decode failure on a
    // row we do not otherwise read would cost a confusing red.
    obligations = try c.decodeIfPresent([RenderObligation].self, forKey: .obligations) ?? []
  }
}

struct RenderFidelityManifest: Decodable {
  let obligationVocabulary: [ObligationVocabularyEntry]
  let kinds: [RenderFidelityKind]
}

/// Locate the artefact.
///
/// `FUARAN_RENDER_FIDELITY` (a path to the artefact FILE) wins where it is set;
/// otherwise the shared corpus beside this checkout. **The override exists so
/// the go-red property can be PROVEN** — a perturbed scratch copy carrying a
/// claim no checker covers must turn this suite red, and demonstrating that must
/// never involve writing to the shared corpus, which is the oracle every sibling
/// surface answers to.
enum RenderFidelityArtefact {
  static var url: URL {
    if let override = ProcessInfo.processInfo.environment["FUARAN_RENDER_FIDELITY"],
      !override.isEmpty
    {
      return URL(fileURLWithPath: override)
    }
    // `<repo>/Tests/FuaranUIRendererTests/…` → `<repo>/../wire-format-fixtures/…`
    return
      URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // FuaranUIRendererTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // fuaran-swift
      .deletingLastPathComponent()  // the workspace tree
      .appendingPathComponent("wire-format-fixtures")
      .appendingPathComponent("render-fidelity.json")
  }

  static var isPresent: Bool { FileManager.default.fileExists(atPath: url.path) }

  static func load() throws -> RenderFidelityManifest {
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(RenderFidelityManifest.self, from: data)
  }
}

// ─── Obligation coverage — the reporting surface ──────────────────────────────

/// Every declared obligation, paired with the kind that owes it, in table order.
func allObligations(
  _ manifest: RenderFidelityManifest
) -> [(kind: String, obligation: RenderObligation)] {
  manifest.kinds.flatMap { row in row.obligations.map { (kind: row.kind, obligation: $0) } }
}

/// A surface's answer for one declared obligation.
///
/// `unchecked` is the case the whole mechanism exists for. A surface that
/// renders a kind and has no checker for one of its claims must say so, WITH a
/// reason — not checked is not passed, and an obligation that quietly falls out
/// of a suite is exactly the silent failure the closed vocabulary replaces.
/// `notRendered` is distinct: nothing is owed, rather than owed and unpaid.
enum ObligationOutcome: Equatable {
  case asserted
  case unchecked(reason: String)
  case notRendered(reason: String)
}

/// One line of a surface's obligation report.
struct ObligationReport: Equatable {
  let kind: String
  let claimId: String
  let statement: String
  let section: String
  let outcome: ObligationOutcome
}

/// Project the manifest through this surface's own answer, one line per declared
/// obligation. The ENUMERATION is the manifest's, never this surface's — so a
/// newly declared obligation appears in the report the moment it lands rather
/// than when someone remembers it.
func reportObligations(
  manifest: RenderFidelityManifest,
  statusOf: (String, String) -> ObligationOutcome
) -> [ObligationReport] {
  allObligations(manifest).map { entry in
    ObligationReport(
      kind: entry.kind,
      claimId: entry.obligation.id,
      statement: entry.obligation.statement,
      section: entry.obligation.section,
      outcome: statusOf(entry.kind, entry.obligation.id))
  }
}

/// The report lines a surface must SURFACE: everything it did not assert. Empty
/// is the only silent result — anything else is printed, so an unchecked
/// obligation is visible in the run rather than inferable from its absence.
func unassertedObligations(_ report: [ObligationReport]) -> [ObligationReport] {
  report.filter { $0.outcome != .asserted }
}

/// The one-line rendering of a report line, so the same sentence appears in
/// every surface's output.
func describeObligationReport(_ line: ObligationReport) -> String {
  let outcome: String
  switch line.outcome {
  case .asserted: outcome = "asserted"
  case .unchecked(let reason): outcome = "UNCHECKED (\(reason))"
  case .notRendered(let reason): outcome = "not rendered (\(reason))"
  }
  return "\(line.kind)/\(line.claimId) [\(line.section)]: \(outcome)"
}
