// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The bare-string enumerations of the Fuaran UI wire format (WIRE_FORMAT §3.5):
// closed vocabularies that ride the wire as a plain JSON string. Each is a
// Swift `String`-raw enum whose `rawValue` is the wire spelling, so
// `init?(rawValue:)` is the from-wire parse and a missing case is an
// (throwable) unknown-discriminator, never a silent fallback.

import Foundation

public enum Orientation: String, CaseIterable, Equatable, Sendable {
  case vertical = "Vertical"
  case horizontal = "Horizontal"
}

public enum ScrollOrientation: String, CaseIterable, Equatable, Sendable {
  case vertical = "Vertical"
  case horizontal = "Horizontal"
  case both = "Both"
}

public enum BadgeVariant: String, CaseIterable, Equatable, Sendable {
  case neutral = "Neutral"
  case brand = "Brand"
  case success = "Success"
  case warning = "Warning"
  case critical = "Critical"
  case info = "Info"
}

public enum ButtonVariant: String, CaseIterable, Equatable, Sendable {
  case primary = "Primary"
  case secondary = "Secondary"
  case tertiary = "Tertiary"
  case destructive = "Destructive"
}

public enum HeadingVariant: String, CaseIterable, Equatable, Sendable {
  case standard = "Standard"
  case eyebrow = "Eyebrow"
  case caption = "Caption"
  case lead = "Lead"
}

public enum ToneVariant: String, CaseIterable, Equatable, Sendable {
  case `default` = "Default"
  case subdued = "Subdued"
  case brand = "Brand"
  case success = "Success"
  case warning = "Warning"
  case critical = "Critical"
  case info = "Info"
}

public enum StyleWeight: String, CaseIterable, Equatable, Sendable {
  case compact = "Compact"
  case standard = "Standard"
  case spacious = "Spacious"
}

public enum Emphasis: String, CaseIterable, Equatable, Sendable {
  case quiet = "Quiet"
  case normal = "Normal"
  case loud = "Loud"
}

public enum StyleRole: String, CaseIterable, Equatable, Sendable {
  case none = "None"
  case eyebrow = "Eyebrow"
  case data = "Data"
  case lede = "Lede"
  case caption = "Caption"
}

public enum FontVoice: String, CaseIterable, Equatable, Sendable {
  case `default` = "Default"
  case display = "Display"
  case structural = "Structural"
}

public enum ChartKind: String, CaseIterable, Equatable, Sendable {
  case line = "Line"
  case bar = "Bar"
  case area = "Area"
  case pie = "Pie"
  case scatter = "Scatter"
  case heatmap = "Heatmap"
}

public enum ImageVariant: String, CaseIterable, Equatable, Sendable {
  case `default` = "Default"
  case avatar = "Avatar"
  case rounded = "Rounded"
}

/// Anti-scraper render strategy for a `Link` — `email` marks a `mailto:` link
/// whose address must not appear in plaintext in emitted markup (the emission
/// strategy is renderer-owned; a render projection may treat it as advisory).
/// Lower-case on the wire.
public enum LinkProtection: String, CaseIterable, Equatable, Sendable {
  case email = "email"
}

/// The rendered size of a standalone `Icon`. Omitted on the wire at `Medium`.
public enum IconSize: String, CaseIterable, Equatable, Sendable {
  case small = "Small"
  case medium = "Medium"
  case large = "Large"
}

/// The unit a `Duration` cell format's raw value counts in.
public enum DurationUnit: String, CaseIterable, Equatable, Sendable {
  case seconds = "Seconds"
  case minutes = "Minutes"
  case hours = "Hours"
}

/// How a `Duration` renders: `1h 5m` / `01:05:00` / `1 hour 5 minutes`.
public enum DurationStyle: String, CaseIterable, Equatable, Sendable {
  case compact = "Compact"
  case clock = "Clock"
  case long = "Long"
}

/// A sort direction. Lower-case on the wire, like `LinkProtection`.
public enum SortDirection: String, CaseIterable, Equatable, Sendable {
  case asc = "asc"
  case desc = "desc"
}

public enum MathDisplay: String, CaseIterable, Equatable, Sendable {
  case inline = "Inline"
  case block = "Block"
}

public enum DateVariant: String, CaseIterable, Equatable, Sendable {
  case date = "Date"
  case time = "Time"
  case dateTime = "DateTime"
}

public enum FileReadEncoding: String, CaseIterable, Equatable, Sendable {
  case text = "Text"
  case base64 = "Base64"
  case dataUrl = "DataUrl"
}

public enum LiveRegionKind: String, CaseIterable, Equatable, Sendable {
  case polite = "polite"
  case assertive = "assertive"
  case off = "off"
}

public enum DateStyle: String, CaseIterable, Equatable, Sendable {
  case short = "Short"
  case medium = "Medium"
  case long = "Long"
  case full = "Full"
}

public enum RelativeTimeUnit: String, CaseIterable, Equatable, Sendable {
  case second = "Second"
  case minute = "Minute"
  case hour = "Hour"
  case day = "Day"
  case week = "Week"
  case month = "Month"
  case year = "Year"
}

public enum HashStrictness: String, CaseIterable, Equatable, Sendable {
  case strictReplay = "StrictReplay"
  case advisoryWarning = "AdvisoryWarning"
  case enforced = "Enforced"
}

public enum BoxRole: String, CaseIterable, Equatable, Sendable {
  case group = "Group"
  case card = "Card"
  case dashboard = "Dashboard"
  case separator = "Separator"
}

public enum HostEffect: String, CaseIterable, Equatable, Sendable {
  case pure = "Pure"
  case readsHost = "ReadsHost"
  case writesHost = "WritesHost"
}

public enum DeterminismSource: String, CaseIterable, Equatable, Sendable {
  case deterministic = "Deterministic"
  case clock = "Clock"
  case random = "Random"
  case network = "Network"
}

public enum ChannelDirection: String, CaseIterable, Equatable, Sendable {
  case outOnly = "OutOnly"
  case twoWay = "TwoWay"
}

public enum TextAnchor: String, CaseIterable, Equatable, Sendable {
  case start = "Start"
  case middle = "Middle"
  case end = "End"
}

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
