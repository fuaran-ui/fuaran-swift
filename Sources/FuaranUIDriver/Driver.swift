// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The server-driven (SDUI) driver (Phase 541) — the Swift twin of the Kotlin
// server-driven driver, and the client half of the loop the Go/Rust hosts drive
// from the server side. It fetches an initial tree over the `FuaranTransport`,
// seeds a `FuaranTreeSession` via `sessionFactory`, then applies each streamed
// `TreeOp` against the session and re-projects the tree, emitting a
// `DriverState` after every step. A validator reject is caught and re-emitted as
// `.rejected` — the loop **survives** and continues.
//
// No wire-JSON handling happens outside the session boundary: the driver only
// ever hands raw op JSON to `FuaranTreeSession.applyOp` and decodes the JSON the
// session hands back with `RenderProjection.decodeNode`. The driver is transport-
// and session-agnostic (both are seams), so the same loop runs over the live
// Rust session in production and over an in-memory fixture + fake session under
// test.

import Foundation
import FuaranUI

/// The re-projected state the driver emits after each step. A **typed** surface:
/// the host renders the current `.rendered` tree, shows a `.rejected` validator
/// error inline while keeping the last-good tree, and treats `.fatal` (a
/// transport or seeding failure) as a terminal error screen.
public enum DriverState {
  /// The current tree, freshly re-projected after a successful step.
  case rendered(Node)
  /// A streamed op was rejected by the validator; the loop survives — `error` is
  /// the typed reject and `tree` is the retained last-good projection.
  case rejected(error: Error, tree: Node)
  /// A terminal failure — the transport failed or the initial tree could not
  /// seed a session.
  case fatal(Error)
}

/// The server-driven driver.
public final class ServerDrivenDriver {
  private let transport: any FuaranTransport
  private let sessionFactory: (String) throws -> any FuaranTreeSession

  public init(
    transport: any FuaranTransport,
    sessionFactory: @escaping (String) throws -> any FuaranTreeSession
  ) {
    self.transport = transport
    self.sessionFactory = sessionFactory
  }

  /// Run the loop to completion (the fixture op stream is finite; a real stream
  /// ends when the server closes it). `onState` is invoked once per step.
  /// Returns the final `DriverState`.
  public func run(onState: (DriverState) -> Void) async -> DriverState {
    let session: any FuaranTreeSession
    var lastGood: Node
    do {
      let initial = try await transport.fetchInitialTree()
      session = try sessionFactory(initial)
      lastGood = try RenderProjection.decodeNode(await session.treeJSON())
    } catch {
      let fatal = DriverState.fatal(error)
      onState(fatal)
      return fatal
    }

    var last: DriverState = .rendered(lastGood)
    onState(last)

    let ops: [String]
    do {
      ops = try await transport.openOpStream()
    } catch {
      let fatal = DriverState.fatal(error)
      onState(fatal)
      return fatal
    }

    for op in ops {
      do {
        try await session.applyOp(op)
        lastGood = try RenderProjection.decodeNode(await session.treeJSON())
        last = .rendered(lastGood)
      } catch {
        // Survive the reject: keep the last-good tree, surface the typed error.
        last = .rejected(error: error, tree: lastGood)
      }
      onState(last)
    }
    return last
  }

  /// POST an interaction event (a control dispatch, a form submit) back to the
  /// server.
  public func postEvent(_ eventJSON: String) async throws -> String {
    try await transport.postEvent(eventJSON)
  }
}
