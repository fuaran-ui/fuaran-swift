// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// FuaranSession — the Swift `actor` wrapper over the Fuaran UI wire-format Rust
// reference core's C-ABI session surface. The core owns a live session over one
// decoded wire tree (render / apply-op / write-store); the C header declares the
// surface `single-owner` — confine the handle and every call taking it to one
// executor for its whole lifetime. A Swift `actor` expresses that contract by
// construction: every method is actor-isolated, so no two calls touch the raw
// pointer concurrently, and the pointer never escapes the actor.
//
// This whole file compiles only when the native core is linked (the
// FUARAN_CORE_AVAILABLE flag, set by Package.swift when the Rust staticlib /
// XCFramework leg is present). On a machine without it, the file is empty and
// the pure-Swift render projection (Phase 538) stands alone.

#if FUARAN_CORE_AVAILABLE

  import FuaranCore

  /// A typed error surfaced from the core's `fuaran_last_error` protocol or an
  /// operation's structured error envelope
  /// (`{"error":{"class","code","message"[,"path"][,"batchIndex"]}}`).
  public struct FuaranError: Error, Equatable, Sendable {
    /// `"decode"` | `"apply"` when carried by an operation envelope; nil for a
    /// session-open failure that carried no class.
    public let errorClass: String?
    public let code: String
    public let message: String
    public let path: String?
    public let batchIndex: Int?

    public init(
      errorClass: String? = nil, code: String, message: String, path: String? = nil,
      batchIndex: Int? = nil
    ) {
      self.errorClass = errorClass
      self.code = code
      self.message = message
      self.path = path
      self.batchIndex = batchIndex
    }
  }

  /// A live session over one wire tree, held under the single-owner contract.
  ///
  /// Concurrency: as an `actor`, every call is serialized and isolated, so the
  /// raw session pointer is never accessed concurrently (the primary safety
  /// property the `!Send` core requires). Each method is a single synchronous
  /// C-call sequence with no internal suspension, so it runs to completion on
  /// one executor thread; `fuaran_last_error` (a per-thread slot) is therefore
  /// read on the same call that saw the failing `fuaran_session_new`. A
  /// dedicated pinned serial executor is the stricter option if strict
  /// thread-affinity is ever required; the actor's serialization is the
  /// contract's load-bearing guarantee.
  public actor FuaranSession {
    // The raw session pointer, stored as its bit pattern (a `Sendable` `UInt`)
    // so the nonisolated `deinit` may read it under Swift 6 strict concurrency.
    // The live pointer is reconstructed for each isolated call.
    private let handleBits: UInt

    private var handle: OpaquePointer { OpaquePointer(bitPattern: handleBits)! }

    /// Decode a canonical wire `Node` JSON into a new session. Throws a
    /// `FuaranError` (the core's `fuaran_last_error` envelope) on a decode
    /// failure.
    public init(treeJSON: String) throws {
      let created: OpaquePointer? = Array(treeJSON.utf8).withUnsafeBufferPointer { bp in
        fuaran_session_new(bp.baseAddress, bp.count)
      }
      guard let created else {
        // Read the failure envelope on THIS thread (per the header's per-thread
        // contract) — the same synchronous context as the failing `new`.
        throw FuaranSession.consumeLastError()
      }
      self.handleBits = UInt(bitPattern: UnsafeRawPointer(created))
    }

    deinit {
      // No other reference can exist at deinit, so freeing here cannot race a
      // concurrent call. Frees exactly once (the handle is a `let` bit pattern).
      if let h = OpaquePointer(bitPattern: handleBits) {
        fuaran_session_free(h)
      }
    }

    // ── Reads ──────────────────────────────────────────────────────────────────

    /// The session's current tree, re-encoded to canonical wire JSON — the
    /// round-trip exit point re-projected by the Phase 538 decoder.
    public func treeJSON() -> String {
      FuaranSession.consume(fuaran_session_tree_json(handle))
    }

    /// Render the session's current tree to a body-fragment HTML string.
    public func render() -> String {
      FuaranSession.consume(fuaran_session_render(handle))
    }

    // ── Mutations (structured `{"ok":true}` / error envelope) ──────────────────

    /// Apply a canonical wire `TreeOp` JSON. Throws `FuaranError` on a decode or
    /// apply failure (the held tree is untouched on failure, per the core).
    public func applyOp(_ opJSON: String) throws {
      let out = Array(opJSON.utf8).withUnsafeBufferPointer { bp in
        FuaranSession.consume(fuaran_session_apply_op(handle, bp.baseAddress, bp.count))
      }
      try FuaranSession.throwIfError(out)
    }

    /// Write a reactive `$state.<key>` slot from a JSON value; re-render to
    /// observe the change.
    public func setState(key: String, valueJSON: String) throws {
      try FuaranSession.throwIfError(
        writeSlot(fuaran_session_set_state, key: key, value: valueJSON))
    }

    /// Write a `$filters.<name>` slot.
    public func setFilter(name: String, valueJSON: String) throws {
      try FuaranSession.throwIfError(
        writeSlot(fuaran_session_set_filter, key: name, value: valueJSON))
    }

    /// Seed a `$queries.<name>` result slot from host-fed data.
    public func setQuery(name: String, valueJSON: String) throws {
      try FuaranSession.throwIfError(
        writeSlot(fuaran_session_set_query, key: name, value: valueJSON))
    }

    // ── Boundary helpers ───────────────────────────────────────────────────────

    private func writeSlot(
      // `fn` is always an imported C function (`fuaran_session_set_*`) — it captures
      // nothing and is inherently Sendable. Annotate it so Swift 6 region isolation
      // accepts passing it into the `withUnsafeBufferPointer` closures below.
      _ fn: @Sendable (OpaquePointer?, UnsafePointer<UInt8>?, Int, UnsafePointer<UInt8>?, Int) ->
        FuaranBuf,
      key: String, value: String
    ) -> String {
      Array(key.utf8).withUnsafeBufferPointer { kp in
        Array(value.utf8).withUnsafeBufferPointer { vp in
          FuaranSession.consume(fn(handle, kp.baseAddress, kp.count, vp.baseAddress, vp.count))
        }
      }
    }

    /// Copy a Rust-owned output buffer into a Swift `String` (honouring `len`,
    /// no trailing NUL) then free it with `fuaran_dealloc`, exactly once.
    private static func consume(_ buf: FuaranBuf) -> String {
      guard let ptr = buf.ptr else { return "" }
      defer { fuaran_dealloc(ptr, buf.len) }
      if buf.len == 0 { return "" }
      return String(decoding: UnsafeBufferPointer(start: ptr, count: buf.len), as: UTF8.self)
    }

    private static func consumeLastError() -> FuaranError {
      let envelope = consume(fuaran_last_error())
      if let e = parseErrorEnvelope(envelope) { return e }
      return FuaranError(code: "DECODE", message: "session decode failed (no error envelope)")
    }

    /// Throw when a `{"ok":true}` / error-envelope response carried an error.
    private static func throwIfError(_ response: String) throws {
      if let e = parseErrorEnvelope(response) { throw e }
    }

    /// Parse a `{"error":{…}}` envelope into a `FuaranError`, or nil for a
    /// success / empty / non-error response.
    private static func parseErrorEnvelope(_ json: String) -> FuaranError? {
      guard !json.isEmpty, let value = try? JSON.parse(json),
        case .object(let root) = value, case .object(let e)? = root["error"]
      else { return nil }
      func str(_ k: String) -> String? {
        if case .string(let s)? = e[k] { return s }
        return nil
      }
      func intVal(_ k: String) -> Int? {
        if case .number(let n)? = e[k] { return Int(n) }
        return nil
      }
      return FuaranError(
        errorClass: str("class"),
        code: str("code") ?? "ERROR",
        message: str("message") ?? "",
        path: str("path"),
        batchIndex: intVal("batchIndex"))
    }
  }

  /// Conform the live session to the transport-neutral `FuaranTreeSession` seam
  /// the interaction host + server-driven driver (Phase 541) are written
  /// against. The actor's isolated synchronous methods (`treeJSON` / `applyOp` /
  /// `setState` / `setFilter` / `setQuery`) satisfy the `async` requirements by
  /// construction — a cross-actor call to a synchronous actor method suspends.
  extension FuaranSession: FuaranTreeSession {}

#endif
