// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The renderer suite's door onto the shared corpus locator (Phase 2331): the
// declared `FUARAN_WIRE_FIXTURES` first, then the sibling and primary-worktree
// candidates — the locator `FuaranUITests` reads, not a copy of it.

import Foundation
import FuaranWireCorpus
import XCTest

/// Raised when the corpus is absent from a checkout that plainly has one.
struct RendererCorpusMissingOnCrossHostCheckout: Error {}

enum RendererCorpus {
  /// The corpus, or the right kind of stop: a skip on a standalone clone, a FAILURE on a
  /// cross-host checkout (where a skip would certify nothing while reporting success),
  /// and the declared variable's refusal when it names something that is not the corpus.
  static func require() throws -> URL {
    switch try WireCorpus.locate() {
    case .found(let corpus): return corpus
    case .missingOnCrossHostCheckout(let message):
      XCTFail(message)
      throw RendererCorpusMissingOnCrossHostCheckout()
    case .standalone:
      throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
    }
  }

  /// The corpus's `nodes/` family.
  static func nodes() throws -> URL { try require().appendingPathComponent("nodes") }
}
