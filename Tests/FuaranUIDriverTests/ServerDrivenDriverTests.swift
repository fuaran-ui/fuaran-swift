// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Phase 541 server-driven-driver gate. An in-memory fixture transport serves
// an initial tree and an ordered op list (a valid op, a rejected op, a valid op);
// the driver runs the full loop over a fake session (no native core). Asserts:
//
//  - the initial tree seeds and re-projects (first `.rendered`);
//  - each op applies and re-projects;
//  - a validator reject surfaces as `.rejected` with the last-good tree retained
//    — the loop **survives** and keeps going;
//  - an interaction event posts back and the transport records it;
//  - a transport failure surfaces as `.fatal`.
//
// Pure (fake transport + fake session), so it runs in the `swift` job. The live
// URLSession transport ships as the reference impl (`URLSessionTransport`) and is
// type-checked here; Foundation has no built-in HTTP server, so the loop is
// proven over the in-memory transport rather than a live socket (the deviation
// from the Kotlin twin, which used `com.sun.net.httpserver`).

import XCTest

@testable import FuaranUI
@testable import FuaranUIDriver

final class ServerDrivenDriverTests: XCTestCase {
  private func md(_ id: String, _ text: String) -> String {
    #"{"id":"\#(id)","kind":{"$type":"Markdown","text":{"$type":"Literal","text":"\#(text)"}}}"#
  }

  private func text(_ node: Node) -> String {
    guard case .markdown(let m) = node.kind, case .literal(let t) = m.text else { return "?" }
    return t
  }

  func testDriverRunsTheFullLoopAndSurvivesAReject() async throws {
    let seed = md("root", "Hello")
    let ops = [
      #"{"cmd":"replace","node":\#(md("root", "One"))}"#,
      #"{"cmd":"reject","code":"VALIDATION_REJECT","path":"/root"}"#,
      #"{"cmd":"replace","node":\#(md("root", "Three"))}"#,
    ]
    let transport = FixtureTransport(tree: seed, ops: ops)
    let driver = ServerDrivenDriver(transport: transport) { initial in FixtureSession(initial) }

    var states: [DriverState] = []
    let final = await driver.run { states.append($0) }

    XCTAssertEqual(states.count, 4, "expected one state per step (seed + 3 ops)")

    guard case .rendered(let t0) = states[0] else { return XCTFail("s0 not rendered") }
    XCTAssertEqual(text(t0), "Hello")

    guard case .rendered(let t1) = states[1] else { return XCTFail("s1 not rendered") }
    XCTAssertEqual(text(t1), "One")

    guard case .rejected(let error, let t2) = states[2] else { return XCTFail("s2 not rejected") }
    XCTAssertEqual((error as? FixtureReject)?.code, "VALIDATION_REJECT")
    XCTAssertEqual(text(t2), "One", "last-good tree retained across the reject")

    guard case .rendered(let t3) = states[3] else { return XCTFail("s3 not rendered") }
    XCTAssertEqual(text(t3), "Three")

    guard case .rendered = final else { return XCTFail("final not rendered") }

    let response = try await driver.postEvent(#"{"type":"click","target":"root"}"#)
    XCTAssertEqual(response, #"{"ok":true}"#)
    let posted = await transport.posted
    XCTAssertEqual(posted.count, 1)
    XCTAssertTrue(posted[0].contains("click"))
  }

  func testTransportFailureSurfacesAsFatal() async {
    let driver = ServerDrivenDriver(transport: FailingTransport()) { initial in FixtureSession(initial) }
    var states: [DriverState] = []
    let final = await driver.run { states.append($0) }
    guard case .fatal = final else { return XCTFail("expected a fatal terminal state") }
    XCTAssertEqual(states.count, 1)
  }
}

// ── Fixtures ─────────────────────────────────────────────────────────────────

struct FixtureReject: Error { let code: String; let path: String? }
private struct FixtureError: Error { let message: String }

/// An in-memory session interpreting the tiny fixture op protocol
/// (`{"cmd":"replace","node":…}` / `{"cmd":"reject",…}`) — the driver is
/// op-agnostic, so the op semantics are the session's concern.
actor FixtureSession: FuaranTreeSession {
  private var current: String
  init(_ initial: String) { self.current = initial }

  func treeJSON() -> String { current }
  func projectResolved() -> String { current }

  func applyOp(_ opJSON: String) throws {
    guard case .object(let op) = try JSON.parse(opJSON) else {
      throw FixtureError(message: "op not an object")
    }
    switch stringField(op, "cmd") {
    case "replace":
      guard let node = op["node"] else { throw FixtureError(message: "replace missing node") }
      current = encodeJSON(node)
    case "reject":
      throw FixtureReject(code: stringField(op, "code") ?? "VALIDATION_REJECT", path: stringField(op, "path"))
    default:
      throw FixtureError(message: "unrecognised fixture op")
    }
  }

  func setState(key: String, valueJSON: String) throws {}
  func setFilter(name: String, valueJSON: String) throws {}
  func setQuery(name: String, valueJSON: String) throws {}
}

actor FixtureTransport: FuaranTransport {
  private let tree: String
  private let ops: [String]
  private(set) var posted: [String] = []

  init(tree: String, ops: [String]) {
    self.tree = tree
    self.ops = ops
  }

  func fetchInitialTree() -> String { tree }
  func openOpStream() -> [String] { ops }
  func postEvent(_ eventJSON: String) -> String {
    posted.append(eventJSON)
    return #"{"ok":true}"#
  }
}

struct FailingTransport: FuaranTransport {
  func fetchInitialTree() async throws -> String { throw FixtureError(message: "boom") }
  func openOpStream() async throws -> [String] { [] }
  func postEvent(_ eventJSON: String) async throws -> String { "" }
}

private func stringField(_ o: [String: JSON], _ key: String) -> String? {
  if case .string(let s)? = o[key] { return s }
  return nil
}

/// A minimal JSON value → wire-string re-encoder (test-local), so the fixture
/// session can adopt a `replace` op's node subtree as its new tree JSON.
func encodeJSON(_ value: JSON) -> String {
  switch value {
  case .null: return "null"
  case .bool(let b): return b ? "true" : "false"
  case .number(let n):
    if n.isFinite, n == n.rounded(), abs(n) < 1e15 { return String(Int(n)) }
    return String(n)
  case .string(let s): return "\"" + jsonEscape(s) + "\""
  case .array(let items): return "[" + items.map(encodeJSON).joined(separator: ",") + "]"
  case .object(let members):
    let body = members.map { "\"\(jsonEscape($0.key))\":\(encodeJSON($0.value))" }.joined(separator: ",")
    return "{" + body + "}"
  }
}

private func jsonEscape(_ s: String) -> String {
  var out = ""
  for ch in s.unicodeScalars {
    switch ch {
    case "\"": out += "\\\""
    case "\\": out += "\\\\"
    case "\n": out += "\\n"
    case "\r": out += "\\r"
    case "\t": out += "\\t"
    default:
      if ch.value < 0x20 { out += String(format: "\\u%04x", ch.value) } else { out.unicodeScalars.append(ch) }
    }
  }
  return out
}
