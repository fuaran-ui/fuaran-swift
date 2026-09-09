// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The transport seam for the server-driven driver (Phase 541; bounded streaming
// + typed refusals + the reply channel, Phase 1541). Four primitives are all the
// mobile SDUI loop needs:
//
//   - fetchInitialTree — GET the initial canonical `Node` JSON the session is
//     seeded with.
//   - openOpLineStream — the ordered canonical `TreeOp` JSON strings (newline-
//     delimited on the wire) delivered AS THEY ARRIVE; the driver applies each
//     against the session in order.
//   - postEvent — POST an interaction event back to the server, returning the
//     response body.
//   - postEventOps — the same POST, read as the server's REPLY OPS, so an
//     event's consequences reach the screen through the same apply-then-project
//     path the stream uses.
//
// The seam is transport-agnostic on purpose: `URLSessionTransport` is a
// dependency-light reference over Foundation's `URLSession` (no third-party HTTP
// client), but a consumer can supply a WebSocket / gRPC implementation without
// touching the driver. Tests supply an in-memory fixture transport.
//
// **Why the stream is bounded and the bounds are named.** A server-driven client
// applies whatever the server sends, so the op stream is the one place an SDUI
// host reads an unbounded amount of attacker-influenced input into memory. The
// buffered form below read the WHOLE `/ops` body into a `String` before yielding
// anything: a stream that never ends is a client that never renders, and a single
// enormous line is a client that dies with no diagnosis. Both caps are therefore
// explicit values with documented defaults, and a breach is refused BY NAME —
// `.lineCapExceeded` / `.bodyCapExceeded` carrying the limit in the message —
// rather than surfacing as an allocation failure somewhere else.

import Foundation

#if canImport(FoundationNetworking)
  // On non-Darwin platforms the URL-loading system (URLSession /
  // HTTPURLResponse) lives in the separate FoundationNetworking module.
  import FoundationNetworking
#endif

/// A transport-layer failure (non-2xx, connection error, bad URL, a refused
/// scheme, a breached stream bound) — distinct from a session-layer validator
/// reject.
///
/// `kind` is the TYPED half: a host that wants to tell "the server is not
/// reachable" from "the server sent something this client refuses to read" can,
/// without parsing `message`. `message` stays the human sentence and names the
/// limit that was breached.
public struct TransportError: Error, Sendable {
  public enum Kind: String, Sendable {
    /// A connection failure, a non-2xx status, a non-HTTP response, a bad URL.
    case transport
    /// The base URL is not `https` and `allowInsecure` was not passed.
    case insecureScheme
    /// One newline-delimited op exceeded `OpStreamBounds.maxLineBytes`.
    case lineCapExceeded
    /// The op stream body exceeded `OpStreamBounds.maxBodyBytes`.
    case bodyCapExceeded
  }

  public let kind: Kind
  public let message: String

  public init(_ message: String) {
    self.kind = .transport
    self.message = message
  }

  public init(kind: Kind, _ message: String) {
    self.kind = kind
    self.message = message
  }
}

/// The explicit bounds an op stream is read under.
///
/// Both defaults are stated here rather than buried at a call site, because the
/// value a host is willing to read is a DEPLOYMENT decision — an embedded client
/// on a metered link and a desktop console do not want the same number — and a
/// limit nobody can find is a limit nobody tunes.
public struct OpStreamBounds: Sendable, Equatable {
  /// 1 MiB. One `TreeOp` is a small document; a megabyte is already far past any
  /// legitimate op and comfortably inside what a phone can hold.
  public static let defaultMaxLineBytes = 1 << 20
  /// 64 MiB. A whole SESSION's worth of ops, not one op — the cap exists to end
  /// a stream that never ends, not to ration ordinary use.
  public static let defaultMaxBodyBytes = 64 << 20

  /// 120 seconds, matching the sibling Kotlin surface's idle budget.
  ///
  /// A server-driven stream is idle whenever the screen is idle, which is most of the time, so this
  /// is the point at which silence stops meaning "nothing happened" and starts meaning "nothing is
  /// coming".
  public static let defaultIdleTimeout: TimeInterval = 120

  /// The largest single newline-delimited op this stream will assemble.
  public let maxLineBytes: Int
  /// The largest total body this stream will read before refusing.
  public let maxBodyBytes: Int
  /// How long the stream may produce NO bytes before the request is given up on.
  ///
  /// `URLRequest.timeoutInterval` is an INTER-PACKET idle limit for a response that is still
  /// arriving, not a deadline on the whole transfer — which is exactly the Kotlin twin's
  /// `idleBudgetMillis`, so the two surfaces state the same policy in each platform's own terms.
  /// It is set explicitly rather than left to Foundation's 60-second default, because a default is a
  /// policy nobody chose: on the twin the equivalent default was 30 seconds and it killed healthy
  /// sessions, which is the defect this phase closes there. A divergence between the two surfaces on
  /// the one axis this phase is about would be residue.
  public let idleTimeout: TimeInterval

  public init(
    maxLineBytes: Int = OpStreamBounds.defaultMaxLineBytes,
    maxBodyBytes: Int = OpStreamBounds.defaultMaxBodyBytes,
    idleTimeout: TimeInterval = OpStreamBounds.defaultIdleTimeout
  ) {
    self.maxLineBytes = maxLineBytes
    self.maxBodyBytes = maxBodyBytes
    self.idleTimeout = idleTimeout
  }

  public static let `default` = OpStreamBounds()
}

/// Assembles newline-delimited ops from a byte stream under `OpStreamBounds`.
///
/// A value type fed one byte at a time, deliberately: it is the SAME component
/// the live `URLSessionTransport` uses and the one the acceptance tests drive
/// directly, so the bound that is proven is the bound that ships. A splitter
/// reachable only through a socket is a bound nobody can test without one.
///
/// The caps are checked BEFORE the byte is retained, so a hostile line is
/// refused at the limit rather than one allocation past it.
public struct BoundedOpLineSplitter: Sendable {
  private var pending: [UInt8] = []
  private var bodyBytes = 0
  private let bounds: OpStreamBounds
  private let label: String

  /// - Parameter label: what the refusal names (an endpoint path, a fixture id).
  public init(bounds: OpStreamBounds = .default, label: String) {
    self.bounds = bounds
    self.label = label
  }

  /// Feed one byte. Returns a completed op when the byte closed a non-blank
  /// line, `nil` otherwise. Throws when either cap is breached.
  public mutating func push(_ byte: UInt8) throws -> String? {
    bodyBytes += 1
    if bodyBytes > bounds.maxBodyBytes {
      throw TransportError(
        kind: .bodyCapExceeded,
        "\(label): op stream body exceeded maxBodyBytes (\(bounds.maxBodyBytes) bytes)")
    }
    if byte == UInt8(ascii: "\n") {
      let line = takePending()
      return line.isEmpty ? nil : line
    }
    if pending.count >= bounds.maxLineBytes {
      throw TransportError(
        kind: .lineCapExceeded,
        "\(label): op line exceeded maxLineBytes (\(bounds.maxLineBytes) bytes)")
    }
    pending.append(byte)
    return nil
  }

  /// Close the stream: returns the final op when the body did not end with a
  /// newline, `nil` otherwise.
  public mutating func finish() -> String? {
    let line = takePending()
    return line.isEmpty ? nil : line
  }

  private mutating func takePending() -> String {
    // `\r\n` is a legitimate NDJSON line ending on the wire; the carriage return
    // is framing, not payload, so it is dropped rather than handed to a JSON
    // parser that would refuse it.
    if pending.last == UInt8(ascii: "\r") { pending.removeLast() }
    let text = String(decoding: pending, as: UTF8.self)
    pending.removeAll(keepingCapacity: true)
    return text.trimmingCharacters(in: .whitespaces)
  }
}

/// The transport the server-driven driver drives. Transport-agnostic; the
/// reference impl is `URLSessionTransport`.
public protocol FuaranTransport: Sendable {
  /// GET the initial tree as canonical wire `Node` JSON.
  func fetchInitialTree() async throws -> String

  /// **Deprecated (Phase 1541) — prefer `openOpLineStream()`.**
  ///
  /// The buffered form: the whole op stream, collected before the first op is
  /// handed back. It is kept because it is the cheapest thing for a fixture or a
  /// finite replay to implement and nothing public is removed, but it is the
  /// wrong shape for a live server-driven session: an SDUI stream is open for as
  /// long as the screen is, so buffering it means the first op renders when the
  /// LAST one arrives, and an endless stream renders nothing at all. It also
  /// carries no bound — see `OpStreamBounds`.
  func openOpStream() async throws -> [String]

  /// The ordered canonical `TreeOp` JSON strings, delivered as they arrive.
  ///
  /// Every failure — the request, a non-2xx status, a breached bound — surfaces
  /// as the stream's terminating error rather than as a throw from this call, so
  /// the driver has ONE place to map a transport failure to `DriverState.fatal`
  /// whether it happened before the first op or after the thousandth.
  ///
  /// The default implementation bridges `openOpStream()`, so an existing
  /// conformer keeps working unchanged (buffered, and honestly so).
  func openOpLineStream() -> AsyncThrowingStream<String, any Error>

  /// POST an interaction event JSON back to the server; returns the response
  /// body.
  func postEvent(_ eventJSON: String) async throws -> String

  /// POST an interaction event and read the reply as the server's REPLY OPS —
  /// the ops the event caused, in order.
  ///
  /// The default is the EMPTY sequence, and that is a decision rather than a
  /// stub: a transport whose server answers a POST with an acknowledgement
  /// (`{"ok":true}`) has not implemented a reply channel, and a default that
  /// read any response body as ops would hand that acknowledgement to the
  /// session as a `TreeOp` and turn every successful event into a validator
  /// reject. A transport that DOES carry reply ops overrides this;
  /// `URLSessionTransport` does.
  func postEventOps(_ eventJSON: String) async throws -> [String]
}

extension FuaranTransport {
  public func openOpLineStream() -> AsyncThrowingStream<String, any Error> {
    AsyncThrowingStream { continuation in
      let task = Task {
        do {
          for op in try await self.openOpStream() { continuation.yield(op) }
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  public func postEventOps(_ eventJSON: String) async throws -> [String] {
    _ = try await postEvent(eventJSON)
    return []
  }
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
  private let bounds: OpStreamBounds
  private let allowInsecure: Bool

  /// - Parameters:
  ///   - bounds: the explicit caps the op stream is read under. See
  ///     `OpStreamBounds` for the defaults and why they are values rather than
  ///     constants at a call site.
  ///   - allowInsecure: permit a non-`https` `baseURL`. **Off by default**: a
  ///     server-driven client applies whatever arrives over this connection to
  ///     its own tree, so a plaintext transport is not a weaker version of this
  ///     feature, it is a different one — any intermediary becomes an author of
  ///     the UI. A LOOPBACK host (`localhost`, `127.0.0.1`, `::1`) is exempt
  ///     without the flag, because a development fixture server on the same
  ///     machine has no intermediary to fear and requiring a certificate for it
  ///     would push every developer to pass the flag permanently — which is how
  ///     an opt-in becomes a default. Every other `http://` base is refused with
  ///     a TYPED `TransportError` of kind `.insecureScheme`; nothing is
  ///     silently downgraded or silently upgraded.
  public init(
    baseURL: String,
    treePath: String = "/tree",
    opsPath: String = "/ops",
    eventsPath: String = "/events",
    session: URLSession = .shared,
    bounds: OpStreamBounds = .default,
    allowInsecure: Bool = false
  ) {
    self.baseURL = baseURL
    self.treePath = treePath
    self.opsPath = opsPath
    self.eventsPath = eventsPath
    self.session = session
    self.bounds = bounds
    self.allowInsecure = allowInsecure
  }

  public func fetchInitialTree() async throws -> String { try await get(treePath) }

  public func postEvent(_ eventJSON: String) async throws -> String {
    try await post(eventsPath, body: eventJSON)
  }

  /// The reply ops for an event, read as NDJSON under the same bounds as the
  /// stream — an event's consequences are ops like any other, so they are read
  /// like any other. An empty (or whitespace-only) reply body means no ops.
  public func postEventOps(_ eventJSON: String) async throws -> [String] {
    let body = try await post(eventsPath, body: eventJSON)
    return try Self.splitOps(body, bounds: bounds, label: eventsPath)
  }

  public func openOpStream() async throws -> [String] {
    let body = try await get(opsPath)
    return try Self.splitOps(body, bounds: bounds, label: opsPath)
  }

  public func openOpLineStream() -> AsyncThrowingStream<String, any Error> {
    let bounds = self.bounds
    let opsPath = self.opsPath
    let configuration = self.session.configuration

    return AsyncThrowingStream { continuation in
      let req: URLRequest
      do {
        req = try makeOpStreamRequest()
      } catch {
        continuation.finish(throwing: error)
        return
      }

      let chunks = URLSessionChunkStream(
        request: req, configuration: configuration, label: opsPath)
      let task = Task {
        var splitter = BoundedOpLineSplitter(bounds: bounds, label: opsPath)
        do {
          for try await chunk in chunks.stream {
            for byte in chunk {
              if let op = try splitter.push(byte) { continuation.yield(op) }
            }
          }
          if let tail = splitter.finish() { continuation.yield(tail) }
          continuation.finish()
        } catch {
          // A breached bound cancels the REQUEST, not merely the read: leaving
          // the connection open would let a hostile server keep sending into a
          // socket nobody is reading.
          chunks.cancel()
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { _ in
        task.cancel()
        chunks.cancel()
      }
    }
  }

  // ── Boundary helpers ────────────────────────────────────────────────────────

  /// The `/ops` request, built where a test can inspect it.
  ///
  /// Separated out because the idle policy is a property of the REQUEST and there is no HTTP server
  /// in Foundation to prove it against on every platform (this repo's driver tests already record
  /// that limit, and drive the loop over an in-memory transport for the same reason). What can be
  /// asserted without a socket is that the declaration is made and carries the bound — and a policy
  /// nobody can check is one that quietly reverts to the platform default.
  func makeOpStreamRequest() throws -> URLRequest {
    var req = URLRequest(url: try makeURL(opsPath))
    req.httpMethod = "GET"
    req.setValue("application/x-ndjson", forHTTPHeaderField: "Accept")
    req.timeoutInterval = bounds.idleTimeout
    return req
  }

  /// Split an already-buffered body into ops under the same bounds the streaming
  /// path applies, so the two forms cannot come to disagree about what is too
  /// long.
  static func splitOps(_ body: String, bounds: OpStreamBounds, label: String) throws -> [String] {
    var splitter = BoundedOpLineSplitter(bounds: bounds, label: label)
    var ops: [String] = []
    for byte in Array(body.utf8) {
      if let op = try splitter.push(byte) { ops.append(op) }
    }
    if let tail = splitter.finish() { ops.append(tail) }
    return ops
  }

  private func makeURL(_ path: String) throws -> URL {
    var base = baseURL
    if base.hasSuffix("/") { base.removeLast() }
    guard let url = URL(string: base + path) else {
      throw TransportError("invalid URL: \(base + path)")
    }
    try Self.requireAllowedScheme(url, allowInsecure: allowInsecure)
    return url
  }

  /// The scheme gate. A typed refusal, never a downgrade and never an upgrade:
  /// rewriting the caller's `http://` to `https://` would be this library
  /// deciding what the deployment meant.
  static func requireAllowedScheme(_ url: URL, allowInsecure: Bool) throws {
    let scheme = (url.scheme ?? "").lowercased()
    if scheme == "https" { return }
    if allowInsecure { return }
    if isLoopback(url.host) { return }
    throw TransportError(
      kind: .insecureScheme,
      "refusing a non-https base URL (\(scheme.isEmpty ? "no scheme" : scheme)): pass "
        + "allowInsecure: true to accept it deliberately, or use https. Loopback hosts "
        + "(localhost, 127.0.0.1, ::1) are exempt.")
  }

  static func isLoopback(_ host: String?) -> Bool {
    guard var host = host?.lowercased(), !host.isEmpty else { return false }
    // `URL.host` keeps the brackets on an IPv6 literal on some platforms and
    // strips them on others; normalise so one spelling is tested.
    if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
    return host == "localhost" || host == "127.0.0.1" || host == "::1"
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
    try Self.checkOK(response, path)
  }

  static func checkOK(_ response: URLResponse, _ path: String) throws {
    guard let http = response as? HTTPURLResponse else {
      throw TransportError("\(path): non-HTTP response")
    }
    guard (200..<300).contains(http.statusCode) else {
      throw TransportError("\(path) returned HTTP \(http.statusCode)")
    }
  }
}

/// An incremental byte source over `URLSession`'s DELEGATE callbacks.
///
/// **Not `URLSession.bytes(for:)`.** That API exists only in Apple's Foundation;
/// swift-corelibs-foundation (Linux, Windows) does not have it, so reaching for
/// it made this transport stream on Darwin and fail to compile anywhere else —
/// and the tempting repair, a `#if canImport(Darwin)` with a buffered fallback,
/// is worse than the compile error it silences: one public seam with two
/// behaviours, where the platform that buffers is the one nobody develops on and
/// therefore the one that discovers it in production. The data-task delegate
/// callbacks are present in BOTH Foundations, so one implementation serves every
/// platform and the streaming property is a property of the seam rather than of
/// the operating system.
///
/// `@unchecked Sendable` with an explicit lock: `URLSession` calls its delegate
/// on its own queue, and the continuation is handed across that boundary.
final class URLSessionChunkStream: NSObject, URLSessionDataDelegate, @unchecked Sendable {
  let stream: AsyncThrowingStream<Data, any Error>

  private let continuation: AsyncThrowingStream<Data, any Error>.Continuation
  private let label: String
  private let lock = NSLock()
  private var finished = false
  private var session: URLSession?
  private var task: URLSessionDataTask?

  init(request: URLRequest, configuration: URLSessionConfiguration, label: String) {
    var captured: AsyncThrowingStream<Data, any Error>.Continuation?
    self.stream = AsyncThrowingStream { captured = $0 }
    // The builder closure runs synchronously inside that initialiser, so this is
    // set by the time control reaches here.
    self.continuation = captured!
    self.label = label
    super.init()

    let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    self.session = session
    let task = session.dataTask(with: request)
    self.task = task
    task.resume()
  }

  func cancel() {
    lock.lock()
    let task = self.task
    let session = self.session
    lock.unlock()
    task?.cancel()
    // `invalidateAndCancel` also releases the session's strong reference to this
    // delegate, which is what keeps the pair from outliving the stream.
    session?.invalidateAndCancel()
  }

  // ── URLSessionDataDelegate ─────────────────────────────────────────────────

  func urlSession(
    _ session: URLSession,
    dataTask: URLSessionDataTask,
    didReceive response: URLResponse,
    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
  ) {
    do {
      try URLSessionTransport.checkOK(response, label)
      completionHandler(.allow)
    } catch {
      // Refuse the body rather than reading a 500's error page as ops.
      finish(throwing: error)
      completionHandler(.cancel)
    }
  }

  func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
    continuation.yield(data)
  }

  func urlSession(
    _ session: URLSession, task: URLSessionTask, didCompleteWithError error: (any Error)?
  ) {
    finish(throwing: error)
    session.finishTasksAndInvalidate()
  }

  private func finish(throwing error: (any Error)?) {
    lock.lock()
    if finished {
      lock.unlock()
      return
    }
    finished = true
    lock.unlock()
    continuation.finish(throwing: error)
  }
}
