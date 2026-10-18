// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The ONE corpus locator every test suite in this package reads (Phase 2331).
//
// The decode suite had a locator that honours `FUARAN_WIRE_FIXTURES` first and
// resolves a git worktree to its primary checkout; the renderer suite walked to a
// sibling directory in five places of its own. In a worktree that sibling walk
// finds nothing, so those suites SKIPPED, and a worktree run certified fewer
// legs than it reported. One locator, in a target every suite depends on, makes
// that drift impossible rather than merely fixed.
//
// Foundation only, and in no product: XCTest is not imported, so each suite maps
// the typed outcome onto its own skip or failure.

import Foundation

public enum WireCorpus {
  /// The package root: `<root>/Sources/FuaranWireCorpus/WireCorpus.swift` → `<root>`.
  public static var repoRoot: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // FuaranWireCorpus
      .deletingLastPathComponent()  // Sources
      .deletingLastPathComponent()  // the package root
  }

  /// Where a cross-host checkout keeps the corpus: beside this repository.
  public static var expectedPath: URL {
    repoRoot.deletingLastPathComponent().appendingPathComponent("wire-format-fixtures")
  }

  /// The files that identify THIS corpus, as opposed to any other corpus in the estate.
  ///
  /// `manifest.json` alone identifies nothing: the wire corpus's own `sanitization/`,
  /// `dag/` and `merge-conformance/` sub-corpora each carry one, and so does every other
  /// specification corpus. A predicate that accepts any directory holding a
  /// `manifest.json` therefore ACCEPTS a wrong corpus and fails downstream with "fixture X
  /// is absent" — loud, and about the wrong thing.
  public static let identityMarkers = ["manifest.json", "idl.json", "WIRE_FORMAT.md"]

  public static func missingMarkers(_ dir: URL) -> [String] {
    identityMarkers.filter {
      !FileManager.default.fileExists(atPath: dir.appendingPathComponent($0).path)
    }
  }

  public static func isWireCorpus(_ dir: URL) -> Bool { missingMarkers(dir).isEmpty }

  /// Raised when a declaring variable names something that is not this corpus.
  public struct DeclaredCorpusRefused: Error, CustomStringConvertible {
    public let message: String
    public var description: String { message }
  }

  /// The variables that DECLARE the corpus root, in the order they are consulted.
  /// `FUARAN_WIRE_FIXTURES` is the name every corpus reader honours first;
  /// `FUARAN_CORPUS` is this surface's older spelling, kept.
  public static let declaringVariables = ["FUARAN_WIRE_FIXTURES", "FUARAN_CORPUS"]

  /// A root declared by the operator, if any — REFUSED rather than ignored when wrong.
  ///
  /// Falling back would make the override unfalsifiable: a typo'd path would produce a run
  /// that looks exactly like a working one, and nobody would learn the variable was never
  /// read.
  public static func declared() throws -> URL? {
    let env = ProcessInfo.processInfo.environment
    for name in declaringVariables {
      guard let declared = env[name], !declared.isEmpty else { continue }
      let url = URL(fileURLWithPath: declared)
      if isWireCorpus(url) { return url }
      throw DeclaredCorpusRefused(
        message: "\(name)='\(declared)' does not name the Fuaran UI wire-format corpus: "
          + "\(missingMarkers(url)) absent. It is refused rather than ignored — falling back "
          + "would run this gate against a corpus you did not name.")
    }
    return nil
  }

  /// The repository's MAIN working tree, when this checkout is a git worktree.
  ///
  /// `repoRoot` is derived from `#filePath`, so in a worktree at `<workspace>/wt/<n>` the
  /// corpus is looked for at `<workspace>/wt/wire-format-fixtures`, where it has never been.
  /// A shared corpus belongs to the REPOSITORY rather than to whichever checkout of it is
  /// running, so it is resolved from the main working tree: `.git` in a worktree is a FILE
  /// whose `gitdir:` line points into the primary repository's `.git/worktrees/<name>`, and
  /// three levels up from there is the primary checkout. Reading that file needs no `git`
  /// process and no environment variable.
  public static func mainWorktreeRoot() -> URL? {
    let dotGit = repoRoot.appendingPathComponent(".git")
    var isDir: ObjCBool = false
    guard FileManager.default.fileExists(atPath: dotGit.path, isDirectory: &isDir),
      !isDir.boolValue,
      let text = try? String(contentsOf: dotGit, encoding: .utf8)
    else { return nil }  // a plain checkout (.git is a directory) — nothing to redirect to
    let prefix = "gitdir:"
    guard
      let line = text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) })
        .first(where: { $0.hasPrefix(prefix) })
    else { return nil }
    let gitDir = URL(
      fileURLWithPath: String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
    // <primary>/.git/worktrees/<name> → <primary>
    return
      gitDir
      .deletingLastPathComponent()  // worktrees
      .deletingLastPathComponent()  // .git
      .deletingLastPathComponent()  // <primary checkout>
  }

  /// Where the corpus may be, in order. The DECLARED root is deliberately not here: it
  /// refuses rather than falling through, so `locate` consults it first and lets the
  /// refusal propagate. Putting it in this list would make it just another candidate,
  /// which is the fall-back the refusal exists to prevent.
  public static func candidates() -> [URL] {
    var out = [expectedPath]
    if let main = mainWorktreeRoot() {
      out.append(main.deletingLastPathComponent().appendingPathComponent("wire-format-fixtures"))
    }
    return out
  }

  /// The first candidate that is this corpus, ignoring the declaring variables.
  public static func undeclared() -> URL? {
    candidates().first(where: isWireCorpus)
  }

  /// Sibling hosts whose presence proves this is a CROSS-HOST checkout — the shape the
  /// conformance gate is built from — rather than a standalone clone of this repo alone.
  public static let siblingHostNames = [
    "fuaran-dotnet", "fuaran", "fuaran-ts", "fuaran-py", "fuaran-go", "fuaran-rs", "fuaran-kt",
  ]

  /// Walks up from the repo looking for a sibling host. A hit means the corpus is absent
  /// from a checkout that plainly HAS one — it moved, was renamed, or this locator went
  /// stale — and the right answer is to fail, not to skip.
  public static func crossHostSibling() -> (name: String, under: URL)? {
    var dir = repoRoot
    while true {
      for name in siblingHostNames {
        var isDir: ObjCBool = false
        let candidate = dir.appendingPathComponent(name)
        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir),
          isDir.boolValue
        {
          return (name, dir)
        }
      }
      let parent = dir.deletingLastPathComponent()
      if parent.path == dir.path { return nil }
      dir = parent
    }
  }

  /// Where the corpus is, or which kind of absence this is.
  public enum Location {
    /// The corpus, declared or found.
    case found(URL)
    /// No corpus and no sibling host: a standalone clone, where skipping is honest.
    case standalone
    /// No corpus in a checkout that has a sibling host: a gate that skipped here would
    /// certify NOTHING while reporting success, so the suite must FAIL with this message.
    case missingOnCrossHostCheckout(String)
  }

  /// The declared root FIRST (its refusal propagates rather than falling through), then
  /// the candidates, then the discrimination between the two kinds of absence.
  public static func locate() throws -> Location {
    if let declared = try declared() { return .found(declared) }
    if let corpus = undeclared() { return .found(corpus) }
    if let sibling = crossHostSibling() {
      let tried = candidates().map(\.path).joined(separator: ", ")
      return .missingOnCrossHostCheckout(
        "cross-host checkout detected (\(sibling.name)/ is present under \(sibling.under.path)) "
          + "but the wire-format-fixtures corpus is at none of [\(tried)] — this gate certified "
          + "NOTHING. If the corpus moved or was renamed, correct `WireCorpus.candidates()` "
          + "rather than letting the harness skip; if this is a one-off layout, name it in "
          + "FUARAN_WIRE_FIXTURES.")
    }
    return .standalone
  }
}
