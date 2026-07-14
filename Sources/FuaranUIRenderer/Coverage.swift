// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The render-coverage sink for the Phase 540 conformance gate (the render-leg
// twin of Phase 538's decode-coverage report). As the exhaustive dispatch spine
// projects a node it records the node's `NodeKind` discriminator; the
// (structurally unreachable) fallback placeholder records a *fallback hit*. The
// render gate asserts `fallbacks` is empty across the whole corpus — every
// fixture renders through a real arm of the floor.
//
// The dispatch spine (`fuaranNodeBody`) is an **exhaustive `switch` with no
// `default`** over the sealed `NodeKind`, so an unrendered kind is a *compile*
// error, not a runtime fallback (the Swift analogue of the Rust host's `match`
// with no `_`). The fallback placeholder therefore exists only as the *defined*
// visible placeholder a host may deliberately route a not-yet-implemented kind
// through (never a silent skip); the sink makes any such use loud.
//
// This layer is pure (no SwiftUI), so it compiles on every platform even where
// the SwiftUI renderer (`FuaranNode`) is guarded out.

import Foundation

/// A render-coverage recorder. A reference type so the single instance threaded
/// through a whole render walk accumulates across nodes.
public final class RenderCoverage: @unchecked Sendable {
  /// discriminator -> number of nodes rendered through that kind's arm.
  public private(set) var kinds: [String: Int] = [:]

  /// discriminators that fell to the fallback placeholder — must be empty for
  /// the gate to pass.
  public private(set) var fallbacks: Set<String> = []

  public init() {}

  public func count(_ discriminator: String) {
    kinds[discriminator, default: 0] += 1
  }

  public func fallback(_ discriminator: String) {
    fallbacks.insert(discriminator)
  }
}
