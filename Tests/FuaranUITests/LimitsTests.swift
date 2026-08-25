// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The §21 resource limits — the host-local half.
//
// The shared corpus pins three of the five bounds (node depth past the limit, node depth
// AT the limit, and the syntactic boundary from both sides). The two LINEAR limits stay
// host-local by the corpus's own decision: committing a megabyte of "aaaa…" to a shared
// repository to assert one integer comparison is a poor trade, and unlike the depth bounds
// it is not a recursion hazard. So they are asserted here, generated from a rule rather
// than stored — as every ported host does.
//
// The BOUNDARY cases matter more than the breaches. A guard one level too tight refuses a
// document every host must accept, and a refusal-only family passes throughout that defect.

import Foundation
import XCTest

@testable import FuaranUI

/// A lock-guarded collector, so the concurrency case below can report from several
/// workers without the shared-mutable-state capture Swift 6 rightly refuses.
private final class Problems: @unchecked Sendable {
  private let lock = NSLock()
  private var items: [String] = []

  func add(_ s: String) {
    lock.lock()
    defer { lock.unlock() }
    items.append(s)
  }

  func all() -> [String] {
    lock.lock()
    defer { lock.unlock() }
    return items
  }
}

final class LimitsTests: XCTestCase {
  /// Built from the inside out, the same rule the corpus's stored depth fixtures follow:
  /// `n` levels of `Box`, the innermost carrying no children. A `Box` needs `role` AND
  /// `layout` before it is a valid node — omit them and the decoder refuses on shape at
  /// the innermost level, which measures nothing about depth while looking exactly like a
  /// depth failure.
  ///
  /// One tree level is three JSON levels here (the node object, its `children` array, the
  /// child object), which is why the node-axis cases below stay well under the syntactic
  /// bound — otherwise a node-depth assertion could be satisfied by the syntactic guard
  /// firing first, and would pass while the node guard did nothing.
  static func nestedNodes(_ n: Int) -> String {
    let tail = "],\"layout\":{\"$type\":\"Flex\",\"direction\":\"Vertical\",\"wrap\":false},\"role\":\"Group\"}}"
    var inner = ""
    for i in stride(from: n - 1, through: 0, by: -1) {
      inner = "{\"id\":\"n\(i)\",\"kind\":{\"$type\":\"Box\",\"children\":[" + inner + tail
    }
    return inner
  }

  /// The decode's verdict as a bare string, so a test can assert on the CODE rather than
  /// merely on "it threw".
  static func verdict(_ json: String) -> String {
    do {
      _ = try RenderProjection.decodeNode(json)
      return "ACCEPTED"
    } catch let e as FuaranDecodeError {
      return e.code.rawValue
    } catch {
      return "UNTYPED(\(error))"
    }
  }

  func testTreeAtExactlyTheNodeLimitDecodes() throws {
    // Rule 1, and the half hosts actually fail: two of the codec hosts aborted the
    // process on exactly this document.
    XCTAssertEqual(Self.verdict(Self.nestedNodes(WireLimits.maxNodeDepth)), "ACCEPTED")
  }

  func testTreeOneLevelPastTheNodeLimitIsRefused() throws {
    XCTAssertEqual(Self.verdict(Self.nestedNodes(WireLimits.maxNodeDepth + 1)), "LIMIT_EXCEEDED")
  }

  func testADeepTreeIsALimitBreachNotInvalidJSON() throws {
    // The distinction §21.2 rule 2 is explicit about: the input is well-formed and merely
    // too large to walk, so INVALID_JSON is an actively wrong diagnosis. All three depths
    // stay under the SYNTACTIC bound, so each is genuinely the node guard answering.
    for n in [25, 40, 80] {
      XCTAssertEqual(Self.verdict(Self.nestedNodes(n)), "LIMIT_EXCEEDED", "at node depth \(n)")
    }
  }

  func testBareNestingAtTheSyntacticLimitFailsOnShapeNotOnTheLimit() throws {
    // Exactly maxJSONDepth levels: not a valid node, so it must fail — but on SHAPE, not
    // as a limit breach. A guard one level too tight answers LIMIT_EXCEEDED here, which is
    // the off-by-one that made the host family disagree at this boundary.
    let n = WireLimits.maxJSONDepth
    let doc = String(repeating: "[", count: n) + String(repeating: "]", count: n)
    XCTAssertEqual(Self.verdict(doc), "WRONG_TYPE")
  }

  func testBareNestingOnePastTheSyntacticLimitIsRefused() throws {
    let n = WireLimits.maxJSONDepth + 1
    let doc = String(repeating: "[", count: n) + String(repeating: "]", count: n)
    XCTAssertEqual(Self.verdict(doc), "LIMIT_EXCEEDED")
  }

  func testGenuinelyMalformedInputIsStillInvalidJSON() throws {
    // The other direction: adding the limit code must not turn a syntax error into a
    // limit report.
    XCTAssertEqual(Self.verdict("{\"id\":\"x\","), "INVALID_JSON")
  }

  func testStringAtTheLimitIsAcceptedAndOnePastItIsRefused() throws {
    // A bare string is not a node, so the accepted case still fails — on shape.
    let atMax = "\"" + String(repeating: "a", count: WireLimits.maxStringLength) + "\""
    XCTAssertEqual(Self.verdict(atMax), "WRONG_TYPE", "a string at the limit must pass the reader")
    let past = "\"" + String(repeating: "a", count: WireLimits.maxStringLength + 1) + "\""
    XCTAssertEqual(Self.verdict(past), "LIMIT_EXCEEDED")
  }

  func testAnOverLongArrayIsRefused() throws {
    let doc = "[" + String(repeating: "1,", count: WireLimits.maxArrayLength) + "1]"
    XCTAssertEqual(Self.verdict(doc), "LIMIT_EXCEEDED")
  }

  func testARefusedDecodeDoesNotPoisonTheNext() throws {
    // The counter is decremented in `defer` precisely so a refusal leaves no residue.
    // Without that, each refused decode would tighten the budget until a valid tree was
    // refused too — and the corpus, which decodes hundreds of trees in one process, would
    // fail somewhere far from the cause.
    for _ in 0..<50 { _ = Self.verdict(Self.nestedNodes(WireLimits.maxNodeDepth + 5)) }
    XCTAssertEqual(Self.verdict(Self.nestedNodes(WireLimits.maxNodeDepth)), "ACCEPTED")
  }

  func testConcurrentDecodesDoNotShareCounters() throws {
    // `decodeNode` is public API, so concurrent decode is expected usage. The walk state
    // is created per call and threaded down, which is what makes this hold; the assertion
    // is on the RESULT rather than on the absence of a race report, because a mis-bounded
    // decode shows up as a VALID tree refused, and that is the damage that matters.
    let ok = Self.nestedNodes(WireLimits.maxNodeDepth)
    let over = Self.nestedNodes(WireLimits.maxNodeDepth + 1)
    let found = Problems()
    DispatchQueue.concurrentPerform(iterations: 8) { t in
      for _ in 0..<20 {
        let a = Self.verdict(ok)
        let b = Self.verdict(over)
        if a != "ACCEPTED" || b != "LIMIT_EXCEEDED" {
          found.add("worker \(t): at-limit=\(a) past-limit=\(b)")
        }
      }
    }
    let problems = found.all()
    XCTAssertTrue(problems.isEmpty, problems.joined(separator: "\n"))
  }
}
