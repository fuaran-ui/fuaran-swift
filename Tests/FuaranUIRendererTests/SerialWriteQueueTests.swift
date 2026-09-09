// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Phase 1541 write-ordering gate.
//
// It runs on EVERY platform, which is the reason `SerialWriteQueue` lives
// outside `#if canImport(SwiftUI)` at all: the interaction host is an
// `ObservableObject` and cannot leave that guard, but ordering is a decision
// rather than an Apple detail, and this repository's own rule is that a decision
// testable on only one platform is a decision nobody re-checks.
//
// The go-red property is exact. Against the previous implementation — a bare
// `Task { await self.dispatch(action) }` per interaction — the slow first write
// and the fast second one overlap, so `order` interleaves and `maxInFlight`
// reaches 2; and because the latched error is written by whichever finishes
// LAST, the first write's reject lands on the second write's record.

import XCTest

@testable import FuaranUIRenderer

private struct QueueRejection: Error {
  let detail: String
}

/// A MainActor-confined observer of what the queue actually did. A class rather
/// than captured locals so the closures share one instance under the same
/// isolation the queue runs on.
@MainActor
private final class WriteProbe {
  private(set) var order: [String] = []
  private(set) var inFlight = 0
  private(set) var maxInFlight = 0

  func begin(_ name: String) {
    inFlight += 1
    maxInFlight = max(maxInFlight, inFlight)
    order.append("start:\(name)")
  }

  func end(_ name: String) {
    order.append("end:\(name)")
    inFlight -= 1
  }
}

@MainActor
final class SerialWriteQueueTests: XCTestCase {

  func testWritesRunInCallOrderWithOneInFlight() async {
    let queue = SerialWriteQueue()
    let probe = WriteProbe()

    // The SLOW write first, the fast one second — the arrangement in which
    // concurrent tasks visibly reorder themselves. Enqueued back to back with no
    // await between them, exactly as two control callbacks arrive.
    queue.enqueue(.state(key: "a")) {
      probe.begin("a")
      try? await Task.sleep(nanoseconds: 80_000_000)
      probe.end("a")
      return QueueRejection(detail: "a was rejected")
    }
    queue.enqueue(.state(key: "b")) {
      probe.begin("b")
      probe.end("b")
      return nil
    }

    await queue.settled()

    XCTAssertEqual(
      probe.order, ["start:a", "end:a", "start:b", "end:b"],
      "the second write must not begin until the first has finished")
    XCTAssertEqual(probe.maxInFlight, 1, "at most one write in flight at a time")
  }

  func testARejectedEarlierWriteIsNotOverwrittenByALaterSuccess() async {
    let queue = SerialWriteQueue()

    queue.enqueue(.state(key: "quantity")) {
      try? await Task.sleep(nanoseconds: 80_000_000)
      return QueueRejection(detail: "out of range")
    }
    queue.enqueue(.state(key: "note")) { nil }

    await queue.settled()

    // BOTH outcomes are observable, and in the order they were made. A single
    // latched "last error" cannot say this: it collapses the sequence into one
    // value, so a reject-then-success is indistinguishable from the reverse.
    XCTAssertEqual(queue.records.count, 2)
    XCTAssertEqual(queue.records.map(\.accepted), [false, true])
    XCTAssertEqual(queue.records[0].subject, .state(key: "quantity"))
    XCTAssertEqual(queue.records[1].subject, .state(key: "note"))
    XCTAssertEqual((queue.records[0].error as? QueueRejection)?.detail, "out of range")
    XCTAssertNil(queue.records[1].error, "the accepted write records no error")
  }

  func testTheRecordLogIsBoundedAndDropsTheOldest() async {
    let queue = SerialWriteQueue()
    let overflow = 5
    for index in 0..<(SerialWriteQueue.maxRecords + overflow) {
      queue.enqueue(.state(key: "k\(index)")) { nil }
    }
    await queue.settled()

    // A host lives as long as the screen does, so an unbounded audit log grows
    // with how much the reader typed. The RECENT records are the ones a host
    // shows, so the oldest go.
    XCTAssertEqual(queue.records.count, SerialWriteQueue.maxRecords)
    XCTAssertEqual(queue.records.first?.subject, .state(key: "k\(overflow)"))
    XCTAssertEqual(
      queue.records.last?.subject,
      .state(key: "k\(SerialWriteQueue.maxRecords + overflow - 1)"))
  }

  func testAnActionWriteRecordsItsSubject() async {
    let queue = SerialWriteQueue()
    queue.enqueue(.action) { nil }
    await queue.settled()
    XCTAssertEqual(queue.records.map(\.subject), [.action])
  }
}
