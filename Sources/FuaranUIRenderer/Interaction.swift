// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The interaction round-trip state-holder (Phase 541) — the Swift twin of the
// Kotlin interaction driver. A `FuaranHost` wraps a live `FuaranTreeSession` and
// exposes the **re-projected tree as SwiftUI state** (`@Published`), so the loop
// is:
//
//   control interaction → FuaranHost.dispatch / writeBack
//     → session.applyOp / setState → session re-encodes tree_json
//     → RenderProjection.decodeNode re-projects → `tree` @Published changes
//     → SwiftUI recomposes the subtree.
//
// **No wire-JSON handling happens outside the session boundary.** The host only
// ever hands raw op / value JSON to the session and decodes the JSON the session
// hands back — the Rust core owns canonical encode, apply, mutation, and
// validation. A validator reject surfaces as a typed `lastError` while `tree`
// keeps the last-good projection: the interaction is rejected, the UI is not
// crashed. Re-projection is deliberately coarse for the floor (re-decode the
// whole tree per step; "measured before optimising").
//
// Guarded by `#if canImport(SwiftUI)` — the host is an `ObservableObject` and the
// action-sink seam is a SwiftUI `@Environment` value. The host is written against
// the pure `FuaranTreeSession` protocol, so it needs no native core: the fake
// session drives it in the pure `swift` job, and the live `FuaranSession` drives
// it in `swift-core`.

#if canImport(SwiftUI)

  import Combine
  import Foundation
  import FuaranUI
  import SwiftUI

  // ── The action sink seam (nil in the static render floor) ──────────────────

  /// The ambient action sink the interactive renderer dispatches through. `nil`
  /// in the static render floor (Phase 540 coverage gate / server-side static
  /// render) — controls are then inert. A `FuaranHost` is provided by
  /// `InteractiveFuaranTree`; the interactive control arms consult it and stay
  /// no-ops when it is absent.
  @MainActor
  public protocol FuaranActionSink: AnyObject, Sendable {
    /// Dispatch a control `Action` through the session and re-project.
    func send(_ action: Action)
    /// Write a form-control edit through the `$state.<key>` channel.
    func writeState(stateKey: String, value: JSON)
  }

  private struct FuaranActionSinkKey: EnvironmentKey {
    static let defaultValue: (any FuaranActionSink)? = nil
  }

  extension EnvironmentValues {
    public var fuaranActionSink: (any FuaranActionSink)? {
      get { self[FuaranActionSinkKey.self] }
      set { self[FuaranActionSinkKey.self] = newValue }
    }
  }

  /// The `$state.<key>` a binding writes to, or `nil` when the binding is not a
  /// state slot. Qualified as `FuaranUI.Binding` to disambiguate from
  /// `SwiftUI.Binding`, both in scope here.
  public func stateKeyOf(_ binding: FuaranUI.Binding?) -> String? {
    guard let binding, case .state(let key, _) = binding else { return nil }
    return key
  }

  // ── The interaction host ───────────────────────────────────────────────────

  @MainActor
  public final class FuaranHost: ObservableObject, FuaranActionSink {
    private let session: any FuaranTreeSession

    /// The current re-projected tree, as SwiftUI state. Reading it in a view
    /// subscribes to it.
    @Published public private(set) var tree: Node

    /// The last validator reject, or `nil` when the last write succeeded.
    @Published public private(set) var lastError: Error?

    public init(session: any FuaranTreeSession, tree: Node) {
      self.session = session
      self.tree = tree
      self.lastError = nil
    }

    /// Seed a host from a live session by reading + projecting its current tree.
    /// The render tree is the **resolved projection** (Phase 650), so a scalar
    /// `Transform` renders its evaluated value; the core resolves it and the
    /// decode-only surface renders what it decodes.
    public static func start(session: any FuaranTreeSession) async throws -> FuaranHost {
      let tree = try RenderProjection.decodeNode(await session.projectResolved())
      return FuaranHost(session: session, tree: tree)
    }

    // ── Async API (tests + programmatic drive) ───────────────────────────────

    /// Apply a raw canonical `TreeOp` JSON (e.g. a structural edit) and
    /// re-project. A validator reject sets `lastError` and leaves `tree`
    /// unchanged.
    public func applyOp(_ opJSON: String) async {
      await guarded {
        try await self.session.applyOp(opJSON)
        try await self.reproject()
      }
    }

    /// Dispatch a control `Action` through the session's state channel and
    /// re-project. Host-side actions (`Navigate` / `Call` / `Notify` / …) carry
    /// no session effect at the floor — the embedding app routes those.
    public func dispatch(_ action: Action) async {
      await guarded {
        try await self.applySessionEffect(action)
        try await self.reproject()
      }
    }

    /// Write a form-control edit through the `$state.<key>` channel per the wire
    /// write-back rules.
    public func writeBack(stateKey: String, value: JSON) async {
      await guarded {
        try await self.session.setState(key: stateKey, valueJSON: jsonToWire(value))
        try await self.reproject()
      }
    }

    // ── FuaranActionSink (sync, for rendered controls) ───────────────────────

    public func send(_ action: Action) {
      Task { await self.dispatch(action) }
    }

    public func writeState(stateKey: String, value: JSON) {
      Task { await self.writeBack(stateKey: stateKey, value: value) }
    }

    // ── Internals ────────────────────────────────────────────────────────────

    private func applySessionEffect(_ action: Action) async throws {
      switch action {
      // A `value` SetState is wire-complete: the payload is right there. A `valueFrom`
      // SetState is NOT - resolving the binding needs the render context (a `Selection`
      // reads the clicked row of a named grid), which this dispatch seam does not carry.
      // Leaving it unapplied is the honest answer; writing a placeholder would put a
      // wrong value under a right-looking key.
      case .setState(let key, let value, _):
        if let value { try await session.setState(key: key, valueJSON: jsonToWire(value)) }
      case .chain(let actions):
        for a in actions { try await applySessionEffect(a) }
      default:
        break  // host-routed actions carry no session effect at the floor
      }
    }

    private func reproject() async throws {
      // Re-read the RESOLVED projection so a state / filter / selection write
      // that feeds a scalar `Transform` param re-evaluates it (Phase 650).
      tree = try RenderProjection.decodeNode(await session.projectResolved())
    }

    private func guarded(_ block: () async throws -> Void) async {
      do {
        try await block()
        lastError = nil
      } catch {
        lastError = error
      }
    }
  }

  /// Render a live `host`'s tree with interaction wired: the host's `tree`
  /// state is projected through the exhaustive `FuaranNode` spine under a
  /// `fuaranActionSink` environment value, so a control interaction round-trips
  /// through the session and recomposes this subtree.
  public struct InteractiveFuaranTree: View {
    @ObservedObject private var host: FuaranHost
    private let ctx: BindingContext

    public init(host: FuaranHost, ctx: BindingContext = .empty) {
      self.host = host
      self.ctx = ctx
    }

    public var body: some View {
      FuaranNode(host.tree, ctx).environment(\.fuaranActionSink, host)
    }
  }

  // ── Minimal JSON value → wire-string encoder (state / write-back values) ────
  //
  // The render projection is decode-only, but a state write-back must hand a
  // value *back* to the session as JSON. This is a scalar/value serialiser (not
  // a canonical tree encoder) — enough to encode a `$state` write.

  func jsonToWire(_ value: JSON) -> String {
    switch value {
    case .null: return "null"
    case .bool(let b): return b ? "true" : "false"
    case .number(let n):
      if n.isFinite, n == n.rounded(), abs(n) < 1e15 { return String(Int(n)) }
      return String(n)
    case .string(let s): return "\"" + escapeJSONString(s) + "\""
    case .array(let items): return "[" + items.map(jsonToWire).joined(separator: ",") + "]"
    case .object(let members):
      let body = members.sorted { $0.key < $1.key }
        .map { "\"\(escapeJSONString($0.key))\":\(jsonToWire($0.value))" }
        .joined(separator: ",")
      return "{" + body + "}"
    }
  }

  private func escapeJSONString(_ s: String) -> String {
    var out = ""
    for ch in s.unicodeScalars {
      switch ch {
      case "\"": out += "\\\""
      case "\\": out += "\\\\"
      case "\n": out += "\\n"
      case "\r": out += "\\r"
      case "\t": out += "\\t"
      default:
        if ch.value < 0x20 {
          out += String(format: "\\u%04x", ch.value)
        } else {
          out.unicodeScalars.append(ch)
        }
      }
    }
    return out
  }

#endif
