// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The session abstraction the interaction host (Phase 541) and the server-driven
// driver (Phase 541) are written against. It is the narrow, transport-neutral
// surface the certified Rust reference core exposes over its C-ABI: read the
// current tree as canonical wire JSON, apply a canonical `TreeOp`, and write a
// reactive slot. The concrete conformer is the `FuaranSession` actor (gated on
// the native core); a native-free fake conforms it for the pure test legs.
//
// Pure by design: this protocol carries no native dependency, so the host + the
// driver + their fake-session tests build and run in the pure `swift` job, while
// the concrete `FuaranSession` conformance + the live round-trip test are gated
// on `FUARAN_CORE_AVAILABLE`. The methods are `async` because the concrete
// conformer is an `actor` (cross-actor calls suspend); a synchronous in-memory
// fake satisfies them trivially.

/// A live session over one wire tree — the mutation + read surface the host and
/// driver round-trip through. The Rust core owns canonical encode, apply,
/// mutation, and validation; this is the seam over it.
public protocol FuaranTreeSession: Sendable {
  /// The session's current tree, re-encoded to canonical wire JSON.
  func treeJSON() async -> String

  /// Apply a canonical wire `TreeOp` JSON; throws on a decode or validator
  /// reject (the held tree is untouched on failure).
  func applyOp(_ opJSON: String) async throws

  /// Write a reactive `$state.<key>` slot from a JSON value.
  func setState(key: String, valueJSON: String) async throws

  /// Write a `$filters.<name>` slot.
  func setFilter(name: String, valueJSON: String) async throws

  /// Seed a `$queries.<name>` result slot from host-fed data.
  func setQuery(name: String, valueJSON: String) async throws
}
