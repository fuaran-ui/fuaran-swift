// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The transport seam for the server-driven driver (Phase 541). Three primitives
// are all the mobile SDUI loop needs:
//
//   - fetchInitialTree — GET the initial canonical `Node` JSON the session is
//     seeded with.
//   - openOpStream — the ordered canonical `TreeOp` JSON strings (newline-
//     delimited on the wire); the driver applies each against the session in
//     order.
//   - postEvent — POST an interaction event back to the server, returning the
//     response body.
//
// The seam is transport-agnostic on purpose: `URLSessionTransport` is a
// dependency-light reference over Foundation's `URLSession` (no third-party HTTP
// client), but a consumer can supply a WebSocket / gRPC implementation without
// touching the driver. Tests supply an in-memory fixture transport.

import Foundation

#if canImport(FoundationNetworking)
  // On non-Darwin platforms the URL-loading system (URLSession /
  // HTTPURLResponse) lives in the separate FoundationNetworking module.
  import FoundationNetworking
#endif

/// A transport-layer failure (non-2xx, connection error, bad URL) — distinct
/// from a session-layer validator reject.
public struct TransportError: Error, Sendable {
  public let message: String
  public init(_ message: String) { self.message = message }
}

/// The transport the server-driven driver drives. Transport-agnostic; the
/// reference impl is `URLSessionTransport`.
public protocol FuaranTransport: Sendable {
  /// GET the initial tree as canonical wire `Node` JSON.
  func fetchInitialTree() async throws -> String

  /// The ordered canonical `TreeOp` JSON strings to apply. The reference impl
  /// reads a newline-delimited (NDJSON) response; a streaming transport can
  /// deliver them incrementally behind the same seam.
  func openOpStream() async throws -> [String]

  /// POST an interaction event JSON back to the server; returns the response
  /// body.
  func postEvent(_ eventJSON: String) async throws -> String
}

/// The reference `FuaranTransport` over `URLSession` (Foundation — no
/// third-party HTTP client, per the dependency-light stance). The op stream is
/// **newline-delimited JSON** (NDJSON): each non-blank line of the ops response
/// is one `TreeOp`. Endpoints default to `/tree`, `/ops`, `/events` under
/// `baseURL` and are individually overridable.
public struct URLSessionTransport: FuaranTransport {
  private let baseURL: String
  private let treePath: String
  private let opsPath: String
  private let eventsPath: String
  private let session: URLSession

  public init(
    baseURL: String,
    treePath: String = "/tree",
    opsPath: String = "/ops",
    eventsPath: String = "/events",
    session: URLSession = .shared
  ) {
    self.baseURL = baseURL
    self.treePath = treePath
    self.opsPath = opsPath
    self.eventsPath = eventsPath
    self.session = session
  }

  public func fetchInitialTree() async throws -> String { try await get(treePath) }

  public func postEvent(_ eventJSON: String) async throws -> String {
    try await post(eventsPath, body: eventJSON)
  }

  public func openOpStream() async throws -> [String] {
    let body = try await get(opsPath)
    return body.split(separator: "\n", omittingEmptySubsequences: true)
      .map { String($0) }
      .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
  }

  // ── Boundary helpers ────────────────────────────────────────────────────────

  private func makeURL(_ path: String) throws -> URL {
    var base = baseURL
    if base.hasSuffix("/") { base.removeLast() }
    guard let url = URL(string: base + path) else {
      throw TransportError("invalid URL: \(base + path)")
    }
    return url
  }

  private func get(_ path: String) async throws -> String {
    var req = URLRequest(url: try makeURL(path))
    req.httpMethod = "GET"
    req.setValue("application/json", forHTTPHeaderField: "Accept")
    let (data, response) = try await session.data(for: req)
    try requireOK(response, path)
    return String(decoding: data, as: UTF8.self)
  }

  private func post(_ path: String, body: String) async throws -> String {
    var req = URLRequest(url: try makeURL(path))
    req.httpMethod = "POST"
    req.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
    req.httpBody = Data(body.utf8)
    let (data, response) = try await session.data(for: req)
    try requireOK(response, path)
    return String(decoding: data, as: UTF8.self)
  }

  private func requireOK(_ response: URLResponse, _ path: String) throws {
    guard let http = response as? HTTPURLResponse else {
      throw TransportError("\(path): non-HTTP response")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw TransportError("\(path) returned HTTP \(http.statusCode)")
    }
  }
}
