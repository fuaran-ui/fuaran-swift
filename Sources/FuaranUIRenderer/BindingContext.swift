// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The render-side `Binding` resolver — the "BindingContext mirror sufficient for
// rendering" Phase 540 calls for. It resolves a static-or-state-backed value to
// a display string; the full state round-trip (write-back, live queries,
// transforms) is Phase 541. Reactive, closure-bearing, and host-owned sources
// (`query` / `filter` / `selection` / `computed` / `transform` / `invoke`) have
// no wire-surviving value here, so they resolve to empty — a deliberate
// render-only floor, not a silent drop.
//
// Pure (no SwiftUI): compiles on every platform. The `switch`es over the sealed
// `Binding` / `TextSource` / `StaticValue` hierarchies are exhaustive with no
// `default`, so a new wire case is a build error until its arm lands.

import Foundation
import FuaranUI

/// The ambient render context: seed state for `State`-backed bindings plus the
/// optional coverage sink threaded to every projected node.
public struct BindingContext: Sendable {
  /// State-key -> current value, seeding `State`-backed bindings for the render.
  public var state: [String: JSON]
  /// The render-coverage sink, or nil in production (no tracking).
  public var coverage: RenderCoverage?

  public init(state: [String: JSON] = [:], coverage: RenderCoverage? = nil) {
    self.state = state
    self.coverage = coverage
  }

  public static let empty = BindingContext()

  /// Resolve a `Binding` to a display string. Exhaustive over the sealed DU.
  public func resolve(_ binding: Binding) -> String {
    switch binding {
    case .staticValue(let v): return flatten(v)
    case .state(let key, let defaultValue):
      return state[key].map(jsonScalar) ?? flatten(defaultValue)
    case .query: return ""
    case .filter: return ""
    case .selection: return ""
    case .computed: return ""
    case .i18n(let key, _): return key
    case .local(_, let initialFrom): return resolve(initialFrom)
    case .format(_, _, let source):
      // Render floor: show the underlying value; number/date formatting is
      // applied by the host in Phase 541.
      return resolve(source)
    case .transform: return ""
    case .invoke: return ""
    }
  }

  /// Resolve a `TextSource` to a display string. Exhaustive over the sealed DU.
  public func resolveText(_ text: TextSource) -> String {
    switch text {
    case .literal(let s): return s
    case .bound(let b): return resolve(b)
    case .i18n(let key, _): return key
    }
  }

  public func resolveInt(_ binding: Binding, _ fallback: Int) -> Int {
    Int(resolve(binding).trimmingCharacters(in: .whitespaces)) ?? fallback
  }

  public func resolveFloat(_ binding: Binding, _ fallback: Double) -> Double {
    Double(resolve(binding).trimmingCharacters(in: .whitespaces)) ?? fallback
  }

  public func resolveBool(_ binding: Binding?) -> Bool {
    guard let binding else { return false }
    return resolve(binding).trimmingCharacters(in: .whitespaces).lowercased() == "true"
  }

  /// Flatten a typed `Static` payload slot to a display string. Exhaustive.
  func flatten(_ value: StaticValue) -> String {
    switch value {
    case .ast(let j): return jsonScalar(j)
    case .options(let opts): return opts.map { resolveText($0.label) }.joined(separator: ", ")
    case .stringOpt(let s): return s ?? ""
    case .stringList(let xs): return xs.joined(separator: ", ")
    case .floatSeq(let ns): return ns.map(numberString).joined(separator: ", ")
    case .markers(let ms): return ms.map { resolveText($0.label) }.joined(separator: ", ")
    }
  }
}

/// Flatten a raw `JSON` value to a human display string (render-only).
/// Exhaustive over `JSON`.
func jsonScalar(_ value: JSON) -> String {
  switch value {
  case .null: return ""
  case .bool(let b): return b ? "true" : "false"
  case .number(let n): return numberString(n)
  case .string(let s): return s
  case .array(let items): return items.map(jsonScalar).joined(separator: ", ")
  case .object(let members):
    return members.sorted { $0.key < $1.key }
      .map { "\($0.key): \(jsonScalar($0.value))" }.joined(separator: ", ")
  }
}

/// Print an integral `Double` without a trailing `.0` (the wire carries all
/// numbers as `Double`, but a level / count reads better as `3` than `3.0`).
func numberString(_ d: Double) -> String {
  if d.isFinite, d == d.rounded(), abs(d) < 1e15 { return String(Int(d)) }
  return String(d)
}
