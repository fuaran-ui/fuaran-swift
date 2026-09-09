// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Phase 1541 transport-bounds gate: the two caps an op stream is read under,
// and the scheme gate in front of them.
//
// These assert the COMPONENT the live transport uses, not a re-implementation of
// it — `BoundedOpLineSplitter` is what `URLSessionTransport.openOpLineStream`
// feeds and what `splitOps` runs the buffered form through, so a bound proven
// here is the bound that ships. A cap reachable only through a socket is a cap
// nobody can test without one, which is how a limit comes to be written down and
// never enforced.

import XCTest

@testable import FuaranUIDriver

final class TransportBoundsTests: XCTestCase {

  // ── The line cap ───────────────────────────────────────────────────────────

  /// The hostile input this cap exists for: ONE op, arbitrarily long, that a
  /// buffering reader would assemble in full before discovering it could not.
  func testAnOverLongOpLineIsRefusedByName() {
    let bounds = OpStreamBounds(maxLineBytes: 16, maxBodyBytes: 1 << 20)
    var splitter = BoundedOpLineSplitter(bounds: bounds, label: "/ops")

    var thrown: TransportError?
    do {
      for byte in Array(String(repeating: "x", count: 64).utf8) {
        _ = try splitter.push(byte)
      }
      XCTFail("a 64-byte line must not pass a 16-byte cap")
    } catch let error as TransportError {
      thrown = error
    } catch {
      return XCTFail("expected a TransportError, got \(error)")
    }

    // Refused BY NAME, in both senses: a typed kind a host can branch on, and a
    // message naming the limit that was breached rather than "too long".
    XCTAssertEqual(thrown?.kind, .lineCapExceeded)
    XCTAssertTrue(
      thrown?.message.contains("maxLineBytes") == true,
      "the refusal must name the cap it breached, got: \(thrown?.message ?? "")")
    XCTAssertTrue(
      thrown?.message.contains("16") == true,
      "the refusal must carry the limit's VALUE, got: \(thrown?.message ?? "")")
    XCTAssertTrue(thrown?.message.contains("/ops") == true, "and the endpoint it was reading")
  }

  /// The cap is on ONE line, not on the stream: a thousand short ops are fine.
  /// Without this the previous assertion is satisfied by a splitter that refuses
  /// everything.
  func testManyShortOpsPassTheLineCap() throws {
    let bounds = OpStreamBounds(maxLineBytes: 16, maxBodyBytes: 1 << 20)
    let body = Array(repeating: "{\"i\":1}", count: 1_000).joined(separator: "\n")
    let ops = try URLSessionTransport.splitOps(body, bounds: bounds, label: "/ops")
    XCTAssertEqual(ops.count, 1_000)
  }

  // ── The body cap ───────────────────────────────────────────────────────────

  /// The other hostile shape: a stream of individually-legal ops that never
  /// ends. The line cap cannot see it; only a total can.
  func testAnOverLongBodyIsRefusedByName() {
    let bounds = OpStreamBounds(maxLineBytes: 1 << 20, maxBodyBytes: 32)
    var splitter = BoundedOpLineSplitter(bounds: bounds, label: "/ops")

    var thrown: TransportError?
    do {
      for byte in Array(Array(repeating: "{\"i\":1}", count: 64).joined(separator: "\n").utf8) {
        _ = try splitter.push(byte)
      }
      XCTFail("a body past maxBodyBytes must not pass")
    } catch let error as TransportError {
      thrown = error
    } catch {
      return XCTFail("expected a TransportError, got \(error)")
    }

    XCTAssertEqual(thrown?.kind, .bodyCapExceeded)
    XCTAssertTrue(
      thrown?.message.contains("maxBodyBytes") == true,
      "the refusal must name the cap it breached, got: \(thrown?.message ?? "")")
    XCTAssertTrue(thrown?.message.contains("32") == true, "and carry its value")
  }

  // ── Framing ────────────────────────────────────────────────────────────────

  func testFramingDropsBlankLinesAndCarriageReturnsAndKeepsAnUnterminatedTail() throws {
    // `\r` is FRAMING on an NDJSON wire, not payload: handing it to a JSON parser
    // is a refusal of a document the server sent correctly.
    let body = "{\"a\":1}\r\n\n  \n{\"b\":2}"
    let ops = try URLSessionTransport.splitOps(body, bounds: .default, label: "/ops")
    XCTAssertEqual(ops, ["{\"a\":1}", "{\"b\":2}"], "blank lines dropped, tail without a newline kept")
  }

  // ── The idle policy ────────────────────────────────────────────────────────

  /// An SDUI stream is idle whenever the screen is idle, so the request must not carry Foundation's
  /// 60-second default: `timeoutInterval` is an INTER-PACKET limit for a response still arriving,
  /// which is exactly the sibling Kotlin surface's `idleBudgetMillis`, and leaving it defaulted would
  /// be the two surfaces disagreeing on the one axis this phase is about.
  ///
  /// There is no HTTP server in Foundation, so the socket-level proof lives on the Kotlin twin (a
  /// fixture that genuinely goes quiet for 35 s). What is checkable here without a socket is that the
  /// declaration is MADE and carries the bound — a policy nobody checks is one that quietly reverts.
  func testTheOpStreamRequestCarriesTheIdleBudget() throws {
    let transport = URLSessionTransport(baseURL: "https://example.test")
    let req = try transport.makeOpStreamRequest()
    XCTAssertEqual(req.timeoutInterval, OpStreamBounds.defaultIdleTimeout)
    XCTAssertEqual(OpStreamBounds.defaultIdleTimeout, 120, "matched to the Kotlin twin's budget")

    let patient = URLSessionTransport(
      baseURL: "https://example.test", bounds: OpStreamBounds(idleTimeout: 600))
    XCTAssertEqual(try patient.makeOpStreamRequest().timeoutInterval, 600, "and it is tunable")
  }

  // ── The scheme gate ────────────────────────────────────────────────────────

  func testPlainHttpIsRefusedWithATypedErrorUnlessOptedIn() {
    let url = URL(string: "http://example.test/ops")!

    do {
      try URLSessionTransport.requireAllowedScheme(url, allowInsecure: false)
      XCTFail("a non-loopback http:// base must be refused")
    } catch let error as TransportError {
      // TYPED, not a silent downgrade and not a silent upgrade to https — the
      // library does not get to decide what the deployment meant.
      XCTAssertEqual(error.kind, .insecureScheme)
      XCTAssertTrue(
        error.message.contains("allowInsecure"),
        "the refusal must name the opt-in, got: \(error.message)")
    } catch {
      XCTFail("expected a TransportError, got \(error)")
    }

    // The opt-in is honoured, deliberately and explicitly.
    XCTAssertNoThrow(try URLSessionTransport.requireAllowedScheme(url, allowInsecure: true))
  }

  func testHttpsIsAlwaysAllowedAndLoopbackIsExemptWithoutTheFlag() {
    XCTAssertNoThrow(
      try URLSessionTransport.requireAllowedScheme(
        URL(string: "https://example.test/ops")!, allowInsecure: false))

    // A development fixture server on the same machine has no intermediary to
    // fear. Requiring a certificate for it would push every developer to pass
    // allowInsecure permanently — which is how an opt-in becomes a default.
    for host in ["http://localhost:8080/ops", "http://127.0.0.1:8080/ops", "http://[::1]:8080/ops"] {
      XCTAssertNoThrow(
        try URLSessionTransport.requireAllowedScheme(URL(string: host)!, allowInsecure: false),
        "\(host) is loopback and is exempt")
    }

    // A host that merely LOOKS loopback is not: the exemption is on the resolved
    // host, never on a substring of it.
    XCTAssertThrowsError(
      try URLSessionTransport.requireAllowedScheme(
        URL(string: "http://localhost.example.test/ops")!, allowInsecure: false))
  }
}
