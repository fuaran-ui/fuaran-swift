// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Phase 1541 streaming-driver gate. Three properties the buffered loop could
// not have, each asserted by a fixture that a buffered reader structurally
// cannot pass:
//
//  - ops render AS THEY ARRIVE, proven against a stream that NEVER ENDS (the one
//    shape a buffering reader can never render anything from, and the shape a
//    live server-driven session actually has);
//  - a transport failure part-way through the stream is TERMINAL and typed —
//    `.fatal`, not a survivable per-op reject, because there is no next op;
//  - an event's REPLY OPS are applied through the same apply-then-project path
//    the stream uses, so an interaction has visible consequences.

import XCTest

@testable import FuaranUI
@testable import FuaranUIDriver

/// An ordered, thread-safe event log. The transport and the driver's `onState`
/// run on different tasks, and what is under test is the ORDER of what they did.
final class EventLog: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []

  func add(_ item: String) {
    lock.lock()
    items.append(item)
    lock.unlock()
  }

  var all: [String] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }
}

/// A transport whose op stream yields `ops` and then, depending on `ending`,
/// finishes, fails, or NEVER ENDS.
///
/// It implements `openOpLineStream` directly rather than riding the protocol's
/// buffered bridge — which is the point: the buffered form cannot express "and
/// then nothing more, ever", and that is the case a live SDUI session is in for
/// as long as the screen is open.
struct StreamingFixtureTransport: FuaranTransport {
  enum Ending: Sendable {
    case finish
    case fail(String)
    case never
  }

  let tree: String
  let ops: [String]
  let ending: Ending
  let replyOps: [String]

  init(tree: String, ops: [String], ending: Ending = .finish, replyOps: [String] = []) {
    self.tree = tree
    self.ops = ops
    self.ending = ending
    self.replyOps = replyOps
  }

  func fetchInitialTree() async throws -> String { tree }

  /// The deprecated buffered form. It cannot represent `.never` at all — asked
  /// for an endless stream it would never return — so it reports what it can and
  /// the streaming form below is what the tests drive.
  func openOpStream() async throws -> [String] { ops }

  func openOpLineStream() -> AsyncThrowingStream<String, any Error> {
    let ops = self.ops
    let ending = self.ending
    return AsyncThrowingStream { continuation in
      let task = Task {
        for op in ops {
          continuation.yield(op)
        }
        switch ending {
        case .finish:
          continuation.finish()
        case .fail(let message):
          continuation.finish(throwing: TransportError(message))
        case .never:
          // Hold the stream open until the consumer terminates it. A buffered
          // reader parked here renders nothing at all, which is the whole point.
          while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 20_000_000)
          }
          continuation.finish()
        }
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  func postEvent(_ eventJSON: String) async throws -> String { "" }

  func postEventOps(_ eventJSON: String) async throws -> [String] { replyOps }
}

/// File-level rather than methods on the test case: the endless-stream leg runs
/// the driver inside a `Task`, and a method would capture the (non-`Sendable`)
/// `XCTestCase` along with it.
private func md(_ text: String) -> String {
  #"{"id":"root","kind":{"$type":"Markdown","text":{"$type":"Literal","text":"\#(text)"}}}"#
}

private func text(_ node: Node) -> String {
  guard case .markdown(let m) = node.kind, case .literal(let t) = m.text else { return "?" }
  return t
}

final class StreamingDriverTests: XCTestCase {

  /// Wait, BOUNDED, for the log to reach `count` entries. Bounded rather than a
  /// blocking handshake on purpose: if incremental delivery is broken the test
  /// must FAIL with a readable assertion, not hang the suite.
  private func waitFor(_ log: EventLog, count: Int, seconds: Double = 5) async {
    let deadline = Date().addingTimeInterval(seconds)
    while log.all.count < count, Date() < deadline {
      try? await Task.sleep(nanoseconds: 5_000_000)
    }
  }

  // ── Incremental delivery ───────────────────────────────────────────────────

  func testOpsRenderAsTheyArriveFromAStreamThatNeverEnds() async {
    let log = EventLog()
    let transport = StreamingFixtureTransport(
      tree: md("Hello"),
      ops: [
        #"{"cmd":"replace","node":\#(md("One"))}"#,
        #"{"cmd":"replace","node":\#(md("Two"))}"#,
      ],
      ending: .never)
    let driver = ServerDrivenDriver(transport: transport) { FixtureSession($0) }

    let run = Task {
      // The result is discarded rather than returned: `DriverState` carries a
      // `Node` and is not `Sendable`, so a `Task` yielding one could not be
      // awaited here. What this leg is about is the log, not the terminal state.
      _ = await driver.run { state in
        if case .rendered(let node) = state { log.add(text(node)) }
      }
    }

    // The seed plus both ops, while the stream is still open. Under the buffered
    // loop this reaches ONE entry (the seed) and then waits for a body that
    // never arrives.
    await waitFor(log, count: 3)
    XCTAssertEqual(
      log.all, ["Hello", "One", "Two"],
      "each op must render when it arrives, not when the stream ends")

    run.cancel()
    _ = await run.value
  }

  // ── A mid-stream transport failure is terminal ─────────────────────────────

  func testATransportFailurePartWayThroughTheStreamIsFatalNotRejected() async {
    let transport = StreamingFixtureTransport(
      tree: md("Hello"),
      ops: [#"{"cmd":"replace","node":\#(md("One"))}"#],
      ending: .fail("the connection dropped"))
    let driver = ServerDrivenDriver(transport: transport) { FixtureSession($0) }

    var states: [DriverState] = []
    let final = await driver.run { states.append($0) }

    XCTAssertEqual(states.count, 3, "seed, one op, then the failure")
    guard case .rendered(let seeded) = states[0] else { return XCTFail("s0 not rendered") }
    XCTAssertEqual(text(seeded), "Hello")
    guard case .rendered(let applied) = states[1] else { return XCTFail("s1 not rendered") }
    XCTAssertEqual(text(applied), "One")

    // NOT `.rejected`. A validator reject is survivable because the next op is
    // still coming; a dead transport has no next op, so calling it survivable
    // would leave a host waiting forever on a screen that looks merely stale.
    guard case .fatal(let error) = states[2] else {
      return XCTFail("a mid-stream transport failure must be fatal, got \(states[2])")
    }
    XCTAssertEqual((error as? TransportError)?.kind, .transport)
    guard case .fatal = final else { return XCTFail("and it must be the terminal state") }
  }

  /// The bound is enforced ON the driver's path, not merely inside the splitter:
  /// a hostile over-cap line reaches the loop as a typed terminal failure.
  func testAnOverCapOpLineReachesTheDriverAsAFatalNamingTheCap() async {
    let bounds = OpStreamBounds(maxLineBytes: 8, maxBodyBytes: 1 << 20)
    let hostile = String(repeating: "x", count: 4096)
    let transport = CappedFixtureTransport(tree: md("Hello"), body: hostile, bounds: bounds)
    let driver = ServerDrivenDriver(transport: transport) { FixtureSession($0) }

    var states: [DriverState] = []
    _ = await driver.run { states.append($0) }

    guard case .fatal(let error) = states.last else {
      return XCTFail("an over-cap op line must end the loop, got \(String(describing: states.last))")
    }
    let transportError = error as? TransportError
    XCTAssertEqual(transportError?.kind, .lineCapExceeded)
    XCTAssertTrue(
      transportError?.message.contains("maxLineBytes") == true,
      "refused by name, got: \(transportError?.message ?? "")")
  }

  // ── The reply channel ──────────────────────────────────────────────────────

  func testPostedEventRepliesAreAppliedThroughTheSameProjectionPath() async {
    let session = FixtureSession(md("Hello"))
    let transport = StreamingFixtureTransport(
      tree: md("Hello"),
      ops: [],
      replyOps: [#"{"cmd":"setState","key":"greeting","value":"Clicked"}"#])
    let driver = ServerDrivenDriver(transport: transport) { _ in session }

    _ = await driver.run { _ in }

    var replies: [DriverState] = []
    let final = await driver.postEventApplyingReply(#"{"type":"click","target":"root"}"#) {
      replies.append($0)
    }

    XCTAssertEqual(replies.count, 1, "one state per applied reply op")
    guard case .rendered(let node) = final else {
      return XCTFail("the reply op must render, got \(final)")
    }
    XCTAssertEqual(
      text(node), "Clicked",
      "an event's consequences must reach the projection, not stop at the transport")
    let state = await session.state
    XCTAssertEqual(state["greeting"], "Clicked", "and reach the session's own slot")
  }

  /// A reply op the session rejects is SURVIVED, exactly as a streamed one is —
  /// the last-good tree is retained rather than the screen being blanked because
  /// a button was pressed.
  func testARejectedReplyOpIsSurvivedWithTheLastGoodTreeRetained() async {
    let transport = StreamingFixtureTransport(
      tree: md("Hello"),
      ops: [],
      replyOps: [#"{"cmd":"reject","code":"VALIDATION_REJECT","path":"/root"}"#])
    let driver = ServerDrivenDriver(transport: transport) { FixtureSession($0) }

    _ = await driver.run { _ in }
    let final = await driver.postEventApplyingReply(#"{"type":"click"}"#) { _ in }

    guard case .rejected(let error, let tree) = final else {
      return XCTFail("expected a survivable reject, got \(final)")
    }
    XCTAssertEqual((error as? FixtureReject)?.code, "VALIDATION_REJECT")
    XCTAssertEqual(text(tree), "Hello", "last-good tree retained across a rejected reply")
  }

  /// The default `postEventOps` is the EMPTY sequence, not the response body.
  /// A transport whose server answers with an acknowledgement has not
  /// implemented a reply channel, and reading `{"ok":true}` as a `TreeOp` would
  /// turn every successful event into a validator reject.
  func testATransportWithNoReplyChannelYieldsNoReplyOps() async throws {
    let transport = FixtureTransport(tree: md("Hello"), ops: [])
    let ops = try await transport.postEventOps(#"{"type":"click"}"#)
    XCTAssertEqual(ops, [], "the default reply channel is empty, never the acknowledgement body")

    // …and the POST still happened: the default is "no reply ops", not "no post".
    let posted = await transport.posted
    XCTAssertEqual(posted.count, 1)
  }
}

/// A transport that serves a fixed body through the BOUNDED splitter, so the
/// cap-breach path is exercised end to end without a socket.
struct CappedFixtureTransport: FuaranTransport {
  let tree: String
  let body: String
  let bounds: OpStreamBounds

  func fetchInitialTree() async throws -> String { tree }

  func openOpStream() async throws -> [String] {
    try URLSessionTransport.splitOps(body, bounds: bounds, label: "/ops")
  }

  func postEvent(_ eventJSON: String) async throws -> String { "" }
}
