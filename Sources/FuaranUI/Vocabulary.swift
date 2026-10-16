// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The hand-written half of the bare-string vocabulary (WIRE_FORMAT §3.5).
//
// Every closed wire enumeration the IDL declares is GENERATED into
// `Model.generated.swift` (Phase 2299): a Swift `String`-raw enum whose
// `rawValue` is the wire spelling, so `init?(rawValue:)` is the from-wire parse
// and a missing case is a (throwable) unknown-discriminator, never a silent
// fallback. What stays here is what the IDL does not state: the dataframe
// compute layer's closed sets (carried inside host-declared transform payloads,
// not as wire vocabulary of their own), and the render-side projections of two
// generated enums, kept beside the case set so the two cannot drift — the
// sandbox mapping is an exhaustive `switch`, so a permission added by
// regeneration is a build error here until it is classified.

import Foundation

// ── Compute layer (dataframe algebra) ────────────────────────────────────────

public enum ColumnType: String, CaseIterable, Equatable, Sendable {
  case int = "int"
  case float = "float"
  case bool = "bool"
  case string = "string"
  case date = "date"
  case timestamp = "timestamp"
}

public enum BinOp: String, CaseIterable, Equatable, Sendable {
  case add, sub, mul, div, mod, eq, ne, lt, le, gt, ge, and, or
  // 0.2.x string predicates.
  case contains
  case startsWith = "startsWith"
  case endsWith = "endsWith"
}

public enum ScalarFn: String, CaseIterable, Equatable, Sendable {
  case abs, round, floor, ceil, length, lower, upper, substr
  case datePart = "datePart"
  // 0.2.x string/date scalar functions.
  case concat, trim, replace
  case dateDiffDays = "dateDiffDays"
}

public enum AggFn: String, CaseIterable, Equatable, Sendable {
  case sum, mean, min, max, count, median, stddev, first, last
}

public enum JoinKind: String, CaseIterable, Equatable, Sendable {
  case inner, left, right, outer
}

public enum WindowFn: String, CaseIterable, Equatable, Sendable {
  case rowNumber = "rowNumber"
  case rank = "rank"
  case lag = "lag"
  case lead = "lead"
  // `cumulSum` is the canonical tag; the legacy `cumSum` spelling decodes as a
  // lenient alias.
  case cumulSum = "cumulSum"
  case rollingMean = "rollingMean"
}

public enum SortDir: String, CaseIterable, Equatable, Sendable {
  case asc, desc
}

// ── Render-side projections of generated enums ───────────────────────────────

extension TrackKind {
  /// The lower-case HTML token a rendering host emits for this case
  /// (§3.6.6 obligation 1). Kept beside the case set so the two cannot drift.
  public var htmlToken: String { rawValue.lowercased() }
}

extension EmbedPermission {
  /// The `sandbox` attribute token for this relaxation, or `nil` where the
  /// relaxation is not a sandbox token at all.
  ///
  /// `AllowFullscreen` returns `nil` deliberately: it is a **permissions-policy
  /// directive** riding `allow="fullscreen"`, not a sandbox relaxation. A host
  /// that mapped the whole enum onto sandbox tokens round-trips every fixture
  /// and fails its render obligation on `nodes/embed-permissions-1.json`, which
  /// is authored with exactly that one permission for exactly that reason.
  public var sandboxToken: String? {
    switch self {
    case .allowScripts: return "allow-scripts"
    case .allowSameOrigin: return "allow-same-origin"
    case .allowForms: return "allow-forms"
    case .allowFullscreen: return nil
    }
  }

  /// The `allow` (permissions-policy) directive for this relaxation, or `nil`
  /// where it rides `sandbox` instead. The inverse of `sandboxToken`, and the
  /// two are exhaustive complements by construction.
  public var allowDirective: String? {
    switch self {
    case .allowFullscreen: return "fullscreen"
    case .allowScripts, .allowSameOrigin, .allowForms: return nil
    }
  }
}
