// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The interaction host's SERIAL WRITE QUEUE (Phase 1541) — one in-flight write
// at a time, FIFO, with each write's outcome recorded in the order it was made.
//
// **Deliberately OUTSIDE `#if canImport(SwiftUI)`**, and the reason is the one
// this repository already records for the accessibility and trend-sentiment
// projections: ordering is a DECISION, not a platform detail, and a decision
// testable on only one platform is a decision nobody re-checks. `FuaranHost` is
// an `ObservableObject` and cannot leave the SwiftUI guard; the guarantee it
// rests on can, so it does — and the acceptance test for the ordering runs on
// every box, Apple or not.
//
// It is a `@MainActor` type rather than an `actor`, which is the load-bearing
// choice. The queue's whole job is that the ENQUEUE order is the CALL order, and
// the callers are control callbacks that are already on the main actor: reading
// and reassigning `tail` between two suspension points on the same actor is
// order-preserving by construction. An `actor` would have had to be reached
// through `Task { await queue.enqueue(…) }`, which starts a concurrent task per
// call and so re-introduces, at the enqueue step, exactly the race the queue
// exists to remove.

import Foundation

/// The outcome of one enqueued write, recorded in the order the writes were
/// MADE — which, because the queue is serial, is also the order they were
/// applied.
///
/// It exists because a single latched "last error" property cannot answer the
/// question a caller actually has after two writes: not "was the last one
/// rejected" but "which of them was". Collapsing a sequence of outcomes into one
/// value makes a reject-then-success indistinguishable from a success-then-
/// reject.
public struct WriteRecord {
  public enum Subject: Sendable, Equatable {
    /// A control `Action` dispatched through the host's `send`.
    case action
    /// A form-control edit written through the host's `writeState`.
    case state(key: String)
  }

  public let subject: Subject
  /// The failure this write produced, or `nil` when it was accepted.
  public let error: Error?

  public init(subject: Subject, error: Error?) {
    self.subject = subject
    self.error = error
  }

  public var accepted: Bool { error == nil }
}

/// A FIFO queue of asynchronous writes with at most one in flight.
@MainActor
public final class SerialWriteQueue {
  /// The most recent writes retained by `records`.
  ///
  /// Bounded on purpose: an interaction host lives as long as the screen does,
  /// so an unbounded audit log is a leak that grows with how much the reader
  /// typed. The oldest records are dropped, because the recent ones are the ones
  /// a host shows or asserts on.
  public static let maxRecords = 64

  /// Each completed write's outcome, oldest first, capped at `maxRecords`.
  public private(set) var records: [WriteRecord] = []

  /// The tail of the chain. Read and written only from the MainActor, so
  /// appending happens in call order with no lock.
  private var tail: Task<Void, Never>?

  public init() {}

  /// Append `work` to the queue. `work` returns the write's own outcome — `nil`
  /// when it was accepted — which is recorded against `subject`.
  ///
  /// The predecessor is awaited BEFORE the work runs, which is what makes "one
  /// in flight" true rather than merely likely. Without it, two writes started
  /// as bare concurrent tasks are applied in whatever order the runtime
  /// scheduled, so two edits to the same slot can land backwards, and a latched
  /// error is written by whichever finishes LAST — a rejected write that started
  /// first and finished second attributes its error to a later write that was
  /// accepted.
  public func enqueue(
    _ subject: WriteRecord.Subject, _ work: @escaping @MainActor () async -> Error?
  ) {
    let previous = tail
    tail = Task { @MainActor in
      await previous?.value
      let error = await work()
      self.record(WriteRecord(subject: subject, error: error))
    }
  }

  /// Await every write enqueued so far.
  ///
  /// The host's sink methods are synchronous because a control's callback is — a
  /// SwiftUI `Button` action returns `Void` — so the work they start has no value
  /// a caller can await. This is that value, and it is what makes the ordering
  /// guarantee testable rather than merely asserted: a test issues two writes and
  /// awaits the queue, instead of sleeping and hoping.
  public func settled() async {
    await tail?.value
  }

  private func record(_ record: WriteRecord) {
    records.append(record)
    if records.count > Self.maxRecords {
      records.removeFirst(records.count - Self.maxRecords)
    }
  }
}
