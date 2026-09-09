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
// session hands back with `RenderProjection.decodeNode` — from
// `projectResolved()`, the read the render path uses. The driver is transport-
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

  /// The live session, retained from `run`'s seeding step.
  ///
  /// It used to be a local of `run`, which is exactly why an event could not
  /// have consequences: `postEvent` reached the transport and never the session,
  /// so the ops a server sent BACK in reply had nowhere to be applied. See
  /// `postEventApplyingReply`.
  private var session: (any FuaranTreeSession)?
  /// The last successfully projected tree, retained across a reject so a
  /// rejected reply op does not blank the screen.
  private var lastGood: Node?

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
  ///
  /// The stream is consumed INCREMENTALLY (`openOpLineStream`), so an op renders
  /// when it arrives rather than when the stream ends — the difference between a
  /// server-driven screen and a slow page load. Every transport failure, whether
  /// it happened before the first op or in the middle of the thousandth, arrives
  /// as the sequence's terminating error and maps to `.fatal` at one site.
  public func run(onState: (DriverState) -> Void) async -> DriverState {
    let session: any FuaranTreeSession
    var lastGood: Node
    do {
      let initial = try await transport.fetchInitialTree()
      session = try sessionFactory(initial)
      // projectResolved(), not treeJSON() — see the note in the op loop below.
      lastGood = try RenderProjection.decodeNode(await session.projectResolved())
    } catch {
      let fatal = DriverState.fatal(error)
      onState(fatal)
      return fatal
    }
    self.session = session
    self.lastGood = lastGood

    var last: DriverState = .rendered(lastGood)
    onState(last)

    do {
      for try await op in transport.openOpLineStream() {
        do {
          try await session.applyOp(op)
          // The RESOLVED projection, not `treeJSON()`.
          //
          // `treeJSON()` is the round-trip EXIT point: every scalar `Binding.Transform`
          // arrives there unevaluated, and this surface is decode-only — it cannot
          // evaluate one. So a metric or a heading driven by a computed value rendered
          // as the empty string on the server-driven path, while the interaction host
          // (`Interaction.swift`, which already read the resolved projection) rendered
          // it correctly. Two paths over one session disagreeing about what the tree
          // says is worse than either being wrong on its own; `TreeSession.swift`
          // documents `projectResolved` as "the read the render path uses", and this
          // is a render path.
          lastGood = try RenderProjection.decodeNode(await session.projectResolved())
          self.lastGood = lastGood
          last = .rendered(lastGood)
        } catch {
          // Survive the reject: keep the last-good tree, surface the typed error.
          last = .rejected(error: error, tree: lastGood)
        }
        onState(last)
      }
    } catch {
      // A TRANSPORT failure, not a reject: the connection died, the status was
      // not 2xx, or a stream bound was breached. There is no "carry on with the
      // next op" here — there is no next op — so it is terminal, and it is
      // terminal wherever in the stream it happened.
      let fatal = DriverState.fatal(error)
      onState(fatal)
      return fatal
    }
    return last
  }

  /// POST an interaction event (a control dispatch, a form submit) back to the
  /// server, returning the raw response body.
  ///
  /// This does NOT apply the reply — see `postEventApplyingReply` for the loop
  /// that does. Kept unchanged so a host that treats the response as its own
  /// business (an acknowledgement, a redirect hint) is unaffected.
  public func postEvent(_ eventJSON: String) async throws -> String {
    try await transport.postEvent(eventJSON)
  }

  /// POST an interaction event and APPLY the server's reply ops, through the
  /// same apply-then-project path the stream uses — so an event's consequences
  /// render.
  ///
  /// Without this an interaction was a one-way message: the server could decide
  /// a click had changed the tree and had no way to say so until the next
  /// streamed op, which on a request/response server is never. The reply ops are
  /// ordinary `TreeOp`s and are treated as such: each is applied in order, a
  /// reject is SURVIVED with the last-good tree retained exactly as in `run`,
  /// and `onState` fires once per applied op.
  ///
  /// Returns the final `DriverState`, or `.fatal` when the POST itself failed or
  /// the driver has not been seeded (`run` has not begun).
  @discardableResult
  public func postEventApplyingReply(
    _ eventJSON: String, onState: (DriverState) -> Void
  ) async -> DriverState {
    guard let session, var lastGood = self.lastGood else {
      let fatal = DriverState.fatal(
        TransportError("postEventApplyingReply before the session was seeded — call run() first"))
      onState(fatal)
      return fatal
    }

    let replies: [String]
    do {
      replies = try await transport.postEventOps(eventJSON)
    } catch {
      let fatal = DriverState.fatal(error)
      onState(fatal)
      return fatal
    }

    var last: DriverState = .rendered(lastGood)
    for op in replies {
      do {
        try await session.applyOp(op)
        lastGood = try RenderProjection.decodeNode(await session.projectResolved())
        self.lastGood = lastGood
        last = .rendered(lastGood)
      } catch {
        last = .rejected(error: error, tree: lastGood)
      }
      onState(last)
    }
    return last
  }
}
