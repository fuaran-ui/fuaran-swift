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
// FUARAN_CORE_AVAILABLE flag, set by Package.swift when the Rust staticlib is
// present beside this repository). On a machine without it, the file is empty
// and the pure-Swift render projection (Phase 538) stands alone.

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

    /// The session's current tree as a **resolved projection** (Phase 650):
    /// identical to `treeJSON` except every scalar-slot `Binding.Transform` is
    /// folded to the literal / `Static` number it evaluates to against the live
    /// sources. The decode-only render projection cannot itself evaluate a
    /// `Transform`, so this is what the render path decodes — the Rust core
    /// resolves compute values, the Swift surface stays decode-only.
    public func projectResolved() -> String {
      FuaranSession.consume(fuaran_session_project_resolved(handle))
    }

    /// Render the session's current tree to a body-fragment HTML string.
    public func render() -> String {
      FuaranSession.consume(fuaran_session_render(handle))
    }

    /// The **resolved rows** of one row-bearing node, evaluated core-side —
    /// what a decode-only surface cannot get from the tree, because a resolved
    /// collection cannot ride a `Static` slot (§2 rule 11). See
    /// ``FuaranTreeSession/resolvedRows(nodeId:)``.
    ///
    /// The three outcomes stay distinct all the way to the renderer; an
    /// unparseable or empty response degrades to ``ResolvedRows/notResolved``
    /// (a loading surface) rather than to zero rows, so a boundary failure can
    /// never masquerade as "this grid is empty".
    public func resolvedRows(nodeId: String) -> ResolvedRows {
      let out = Array(nodeId.utf8).withUnsafeBufferPointer { bp in
        FuaranSession.consume(fuaran_session_resolved_rows(handle, bp.baseAddress, bp.count))
      }
      return FuaranSession.parseResolvedRows(out)
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

    // ── Placement (Phase 833; `move` Phase 1673; the other four Phase 1703) ──
    //
    // The op vocabulary is positionless — InsertChild and MoveNode APPEND, and an
    // explicit order is stated only by a ReorderChildren naming every sibling —
    // so "put this node there" is an algebra, not an op. The core owns that
    // algebra and these verbs reach it. This surface is a DECODE-ONLY projection:
    // it cannot author a TreeOp, so without these entry points the only way to
    // place a node from Swift would be to reimplement the algebra here, which is
    // the second implementation the C-ABI exists to prevent.
    //
    // ALL FIVE are surfaced (Phase 1703). Phase 1673 asked whether a decode-only
    // projection should author placements GENERALLY, deliberately left it open,
    // and surfaced only the drag-move. The answer is yes, and the argument is that
    // the question was settled by `move` rather than raised by it: a surface that
    // can relocate a node but not insert one is not a narrower answer to "may this
    // tier author placements" — it is the same answer applied to one fifth of the
    // algebra, with the other four fifths reachable only through the
    // reimplementation this seam exists to prevent. The helpers below were left
    // shaped for the whole family; this is that shape being taken up.
    //
    // A node arrives as a canonical wire JSON DOCUMENT (`childJSON`,
    // `subtreeJSON`), never as a `Node`, and that follows from the tier being
    // decode-only: `RenderProjection` parses the wire form and does not emit it,
    // so there is no `Node` → JSON direction here to offer and inventing one would
    // be a second encoder — the same defect one layer up. The document is spliced
    // verbatim and judged by the CORE's parser, which is the decoder that owns
    // that judgement; every STRING member still goes through this tier's own
    // writer, so an awkward node id is escaped rather than closing the string.
    //
    // Each returns the emitted canonical `TreeOp` JSON. That is not a courtesy:
    // the op is the artefact the verb COMPUTED, and a host that journals, replays
    // or diffs its op-stream needs it and cannot re-derive it from the resulting
    // tree. Discard it with `_ =` when you do not.
    //
    // On refusal the held tree is UNTOUCHED and a `FuaranError` is thrown whose
    // `errorClass` is `"placement"` (the apply-side refusal this placement would
    // have met, pre-stated — so a drag can be greyed out without a dry run) or
    // `"request"` (the request document itself was wrong).

    /// Where a placement puts the node among its new siblings.
    ///
    /// An anchor belongs to `before` / `after` and to nothing else, which is why
    /// it is carried by those cases rather than by a separate optional
    /// parameter: the core REFUSES an anchor supplied with `last` / `first`
    /// rather than dropping it, and a type that cannot express the refused shape
    /// is better than one that can and is told off for it.
    public enum Placement: Equatable, Sendable {
      case last
      case first
      case before(String)
      case after(String)

      fileprivate var caseName: String {
        switch self {
        case .last: return "Last"
        case .first: return "First"
        case .before: return "Before"
        case .after: return "After"
        }
      }

      fileprivate var anchor: String? {
        switch self {
        case .last, .first: return nil
        case .before(let a), .after(let a): return a
        }
      }
    }

    /// Relocate a node ALREADY IN THE TREE — the drag-move.
    ///
    /// The node KEEPS ITS ID: the core emits `MoveNode` (plus a
    /// `ReorderChildren` when appending does not already give the wanted order),
    /// so nothing is minted and nothing is remapped. That is why a caller cannot
    /// spell a move as place-then-remove: between those two ops the moved id
    /// either does not exist or exists twice.
    ///
    /// Throws with code `MoveIntoSelf` or `MoveIntoDescendant` when the
    /// destination is the node itself or sits inside its own subtree — refused
    /// before any op is emitted.
    @discardableResult
    public func move(source: String, parentId: String, placement: Placement) throws -> String {
      try placementVerb(
        fuaran_session_move,
        request(parentId: parentId, placement: placement, extra: [("source", .string(source))]))
    }

    /// Insert a NEW node among a parent's children.
    ///
    /// `childJSON` is a canonical wire `Node` document, not a `Node`: this tier
    /// decodes the wire form and does not emit it, so the document comes from
    /// wherever the caller obtained it (a peer, a template, a previous
    /// `treeJSON`) and is judged by the core's parser — a malformed one comes
    /// back as a `request` error rather than being silently reshaped here.
    ///
    /// Throws `ParentNotFound` / `ChildlessKind` when the destination cannot take
    /// a child, `UnknownAnchor` when the anchor is not among its post-op
    /// children, and `DuplicateId` when an id in the child already exists — a
    /// `place` mints and remaps NOTHING, which is what separates it from `paste`.
    @discardableResult
    public func place(childJSON: String, parentId: String, placement: Placement) throws -> String {
      try placementVerb(
        fuaran_session_place,
        request(parentId: parentId, placement: placement, extra: [("child", .raw(childJSON))]))
    }

    /// Move a node one or more positions among its OWN siblings — the
    /// keyboard/handle nudge, which needs no destination because it never leaves
    /// its parent.
    ///
    /// `delta` is a whole number of sibling positions; negative moves earlier.
    /// Throws `CannotNudgeRoot` (the root has no siblings) or `NudgeOutOfRange`
    /// (the result would fall outside the sibling list) — both refused before any
    /// op is emitted, so a held-key repeat stops at the end rather than clamping
    /// silently.
    @discardableResult
    public func nudge(target: String, delta: Int) throws -> String {
      try placementVerb(
        fuaran_session_nudge,
        object([("target", .string(target)), ("delta", .raw(String(delta)))]))
    }

    /// Copy a node ALREADY IN THE TREE and place the copy.
    ///
    /// Unlike `move`, the copy is a NEW node: every id in it that collides with
    /// one already in the tree is remapped, and ids that do not collide are
    /// preserved. `idPrefix` selects the deterministic strategy — minted ids are
    /// `<prefix>-1`, `-2`, … in traversal order — and omitting it takes the
    /// derived strategy (`<oldId>-copy`, then `-copy-2`, …). Pass one when the
    /// caller needs to PREDICT the minted ids; omit it when the copy should read
    /// as a copy of something.
    @discardableResult
    public func duplicate(
      source: String, parentId: String, placement: Placement, idPrefix: String? = nil
    ) throws -> String {
      var extra: [(String, JSONFragment)] = [("source", .string(source))]
      if let idPrefix { extra.append(("idPrefix", .string(idPrefix))) }
      return try placementVerb(
        fuaran_session_duplicate,
        request(parentId: parentId, placement: placement, extra: extra))
    }

    /// Place a subtree lifted from ANOTHER tree — the clipboard verb.
    ///
    /// The same id-remapping contract as `duplicate` (that is the whole
    /// difference from `place`, which refuses a collision rather than remapping);
    /// what differs is where the subtree came from, so it arrives as a document
    /// rather than as an id.
    @discardableResult
    public func paste(
      subtreeJSON: String, parentId: String, placement: Placement, idPrefix: String? = nil
    ) throws -> String {
      var extra: [(String, JSONFragment)] = [("subtree", .raw(subtreeJSON))]
      if let idPrefix { extra.append(("idPrefix", .string(idPrefix))) }
      return try placementVerb(
        fuaran_session_paste,
        request(parentId: parentId, placement: placement, extra: extra))
    }

    // ── Placement boundary helpers ───────────────────────────────────────────

    /// A member value: either a string this encoder quotes and escapes, or a
    /// caller-supplied JSON document spliced verbatim (a node, or a number).
    /// Splicing is not a hole in the encoder — a malformed `.raw` is refused by
    /// the CORE's own parser and comes back as a `request` error, which is the
    /// decoder that owns that judgement.
    fileprivate enum JSONFragment {
      case string(String)
      case raw(String)

      var encoded: String {
        switch self {
        case .raw(let r): return r
        case .string(let s): return FuaranSession.quote(s)
        }
      }
    }

    /// The JSON string form, written here rather than reached for from
    /// Foundation because this target hand-rolls its JSON reader for the same
    /// reason (`JSON.swift`) — a dependency-light surface.
    fileprivate static func quote(_ s: String) -> String {
      var out = "\""
      for scalar in s.unicodeScalars {
        switch scalar {
        case "\"": out += "\\\""
        case "\\": out += "\\\\"
        case "\u{08}": out += "\\b"
        case "\u{0C}": out += "\\f"
        case "\n": out += "\\n"
        case "\r": out += "\\r"
        case "\t": out += "\\t"
        default:
          if scalar.value < 0x20 {
            let hex = String(scalar.value, radix: 16)
            out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
          } else {
            out.unicodeScalars.append(scalar)
          }
        }
      }
      return out + "\""
    }

    fileprivate func object(_ members: [(String, JSONFragment)]) -> String {
      "{" + members.map { "\(FuaranSession.quote($0.0)):\($0.1.encoded)" }.joined(separator: ",")
        + "}"
    }

    /// The destination members every placement verb but `nudge` carries.
    fileprivate func request(
      parentId: String, placement: Placement, extra: [(String, JSONFragment)]
    ) -> String {
      var members: [(String, JSONFragment)] = [
        ("parentId", .string(parentId)),
        ("placement", .string(placement.caseName)),
      ]
      if let anchor = placement.anchor { members.append(("anchor", .string(anchor))) }
      return object(members + extra)
    }

    /// One placement call: marshal the request, read the envelope, throw on a
    /// refusal, hand back the emitted op.
    @discardableResult
    private func placementVerb(
      // As `writeSlot` below: `fn` is an imported C function, captures nothing,
      // and is annotated `@Sendable` so Swift 6 region isolation accepts passing
      // it into the `withUnsafeBufferPointer` closure.
      _ fn: @Sendable (OpaquePointer?, UnsafePointer<UInt8>?, Int) -> FuaranBuf,
      _ requestJSON: String
    ) throws -> String {
      let out = Array(requestJSON.utf8).withUnsafeBufferPointer { bp in
        FuaranSession.consume(fn(handle, bp.baseAddress, bp.count))
      }
      try FuaranSession.throwIfError(out)
      return out
    }

    // ── Boundary helpers ───────────────────────────────────────────────────────

    private func writeSlot(
      // `fn` is always an imported C function (`fuaran_session_set_*`) — it captures
      // nothing and is inherently Sendable. Annotate it so Swift 6 region isolation
      // accepts passing it into the `withUnsafeBufferPointer` closures below.
      _ fn:
        @Sendable (OpaquePointer?, UnsafePointer<UInt8>?, Int, UnsafePointer<UInt8>?, Int) ->
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

    /// Parse the resolved-rows envelope: `{"resolved":true,"rows":[…]}`,
    /// `{"resolved":false}`, or the `NO_ROW_SOURCE` error envelope.
    ///
    /// Anything unrecognised — an empty buffer, unparseable bytes, `resolved`
    /// true with a missing or non-array `rows` — degrades to `.notResolved`.
    /// That is deliberate: the failure then shows as a loading surface, which is
    /// honest about not knowing, where `.rows([])` would assert emptiness the
    /// core never claimed.
    private static func parseResolvedRows(_ json: String) -> ResolvedRows {
      guard !json.isEmpty, let value = try? JSON.parse(json), case .object(let root) = value
      else { return .notResolved }
      if parseErrorEnvelope(json) != nil { return .noRowSource }
      guard case .bool(true)? = root["resolved"], case .array(let rows)? = root["rows"]
      else { return .notResolved }
      return .rows(rows)
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
