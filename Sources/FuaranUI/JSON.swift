// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// A minimal JSON value tree the render-projection decoder walks, plus a small
// portable recursive-descent parser. It is a read-only view of the canonical
// wire JSON (as read back from the Rust reference core's session): the Swift
// surface never canonically *encodes*, so this layer models values, not
// canonical number/byte form. A hand parser (rather than JSONSerialization)
// keeps the number/bool distinction unambiguous across every Swift platform,
// including Windows where CoreFoundation's CFBoolean check is unavailable.

/// A parsed JSON value. `object` is keyed (decode-only; wire key order is not
/// modelled because there is no re-encode leg).
public enum JSON: Equatable, Sendable {
  case null
  case bool(Bool)
  case number(Double)
  case string(String)
  case array([JSON])
  case object([String: JSON])

  /// Parse a UTF-8 JSON document into the value tree.
  public static func parse(_ text: String) throws -> JSON {
    var p = JSONParser(Array(text.unicodeScalars))
    let value = try p.parseValue()
    p.skipWhitespace()
    guard p.atEnd else {
      throw FuaranDecodeError(
        code: .invalidJson, path: "$", message: "trailing content after JSON value")
    }
    return value
  }
}

/// A tiny recursive-descent JSON parser over Unicode scalars.
private struct JSONParser {
  private let scalars: [Unicode.Scalar]
  private var i = 0

  /// Current SYNTACTIC nesting depth (``WireLimits/maxJSONDepth``). Incremented on the
  /// way DOWN — before the recursion that would breach the bound — so nothing has been
  /// allocated when it fires, and never by measuring the value that was built. A field on
  /// the parser rather than shared state precisely because a parser is per-parse: two
  /// concurrent parses cannot see each other's count, with no locking and no thread-local.
  private var depth = 0

  init(_ scalars: [Unicode.Scalar]) { self.scalars = scalars }

  var atEnd: Bool { i >= scalars.count }

  private func err(_ message: String) -> FuaranDecodeError {
    FuaranDecodeError(code: .invalidJson, path: "$", message: message)
  }

  /// A limit breach is NOT a syntax error, and the two must not collapse: the input is
  /// well-formed and merely too large to walk. Only the parser can tell them apart, which
  /// is why it raises the distinction rather than leaving the decoder to infer it.
  private func limit(_ message: String) -> FuaranDecodeError {
    FuaranDecodeError(code: .limitExceeded, path: "$", message: message)
  }

  /// Enters one composite level, refusing the level that would breach the bound.
  private mutating func enterComposite() throws {
    depth += 1
    if depth > WireLimits.maxJSONDepth {
      throw limit(
        "JSON nesting deeper than the wire limit maxJSONDepth = \(WireLimits.maxJSONDepth); "
          + "expected a document nesting no more than \(WireLimits.maxJSONDepth) levels deep")
    }
  }

  mutating func skipWhitespace() {
    while i < scalars.count {
      switch scalars[i] {
      case " ", "\t", "\n", "\r": i += 1
      default: return
      }
    }
  }

  private mutating func peek() -> Unicode.Scalar? { i < scalars.count ? scalars[i] : nil }

  private mutating func expect(_ s: Unicode.Scalar) throws {
    guard i < scalars.count, scalars[i] == s else {
      throw err("expected '\(s)'")
    }
    i += 1
  }

  mutating func parseValue() throws -> JSON {
    skipWhitespace()
    guard let c = peek() else { throw err("unexpected end of input") }
    switch c {
    case "{": return try parseObject()
    case "[": return try parseArray()
    case "\"": return .string(try parseString())
    case "t", "f": return .bool(try parseBool())
    case "n":
      try parseLiteral("null")
      return .null
    case "-", "0"..."9": return .number(try parseNumber())
    default: throw err("unexpected character '\(c)'")
    }
  }

  private mutating func parseLiteral(_ word: String) throws {
    for ch in word.unicodeScalars {
      guard i < scalars.count, scalars[i] == ch else { throw err("invalid literal '\(word)'") }
      i += 1
    }
  }

  private mutating func parseBool() throws -> Bool {
    if peek() == "t" {
      try parseLiteral("true")
      return true
    }
    try parseLiteral("false")
    return false
  }

  private mutating func parseObject() throws -> JSON {
    try expect("{")
    // BEFORE the empty-composite arm below, deliberately: every `{` counts, empty or not.
    // Testing after it leaves the innermost level of a `{{{…}}}` payload unmeasured —
    // the exact off-by-one that made the host family disagree by one level here.
    try enterComposite()
    defer { depth -= 1 }
    var out: [String: JSON] = [:]
    skipWhitespace()
    if peek() == "}" {
      i += 1
      return .object(out)
    }
    while true {
      skipWhitespace()
      guard peek() == "\"" else { throw err("expected string key in object") }
      let key = try parseString()
      skipWhitespace()
      try expect(":")
      out[key] = try parseValue()
      if out.count > WireLimits.maxArrayLength {
        throw limit(
          "an object has more members than the wire limit maxArrayLength = "
            + "\(WireLimits.maxArrayLength); expected objects of no more than "
            + "\(WireLimits.maxArrayLength) members")
      }
      skipWhitespace()
      switch peek() {
      case ",": i += 1
      case "}":
        i += 1
        return .object(out)
      default: throw err("expected ',' or '}' in object")
      }
    }
  }

  private mutating func parseArray() throws -> JSON {
    try expect("[")
    // See the note in parseObject: before the empty arm, every `[` counts.
    try enterComposite()
    defer { depth -= 1 }
    var out: [JSON] = []
    skipWhitespace()
    if peek() == "]" {
      i += 1
      return .array(out)
    }
    while true {
      out.append(try parseValue())
      if out.count > WireLimits.maxArrayLength {
        throw limit(
          "an array is longer than the wire limit maxArrayLength = "
            + "\(WireLimits.maxArrayLength); expected arrays of no more than "
            + "\(WireLimits.maxArrayLength) elements")
      }
      skipWhitespace()
      switch peek() {
      case ",": i += 1
      case "]":
        i += 1
        return .array(out)
      default: throw err("expected ',' or ']' in array")
      }
    }
  }

  private mutating func parseString() throws -> String {
    try expect("\"")
    var out = String.UnicodeScalarView()
    // Counted rather than measured: `out.count` is O(n) on a scalar view, so checking it
    // per iteration would make the loop quadratic — on exactly the hostile input the
    // bound exists to refuse.
    var appended = 0
    while i < scalars.count {
      // Inside the accumulation loop rather than after it, so a hostile 100 MB literal is
      // refused partway through rather than built in full and measured afterwards.
      // `>` and not `>=`: a string of exactly maxStringLength scalars is admissible, and a
      // bound one character too tight would refuse a document every host must accept.
      if appended > WireLimits.maxStringLength {
        throw limit(
          "a string is longer than the wire limit maxStringLength = "
            + "\(WireLimits.maxStringLength); expected strings of no more than "
            + "\(WireLimits.maxStringLength) characters")
      }
      let c = scalars[i]
      i += 1
      switch c {
      case "\"":
        return String(out)
      case "\\":
        guard i < scalars.count else { throw err("unterminated escape") }
        let e = scalars[i]
        i += 1
        switch e {
        case "\"": out.append("\"")
        case "\\": out.append("\\")
        case "/": out.append("/")
        case "b": out.append(Unicode.Scalar(0x08))
        case "f": out.append(Unicode.Scalar(0x0C))
        case "n": out.append("\n")
        case "r": out.append("\r")
        case "t": out.append("\t")
        case "u": out.append(try parseUnicodeEscape())
        default: throw err("invalid escape '\\\(e)'")
        }
      default:
        out.append(c)
      }
      appended += 1
    }
    throw err("unterminated string")
  }

  private mutating func parseUnicodeEscape() throws -> Unicode.Scalar {
    let hi = try readHex4()
    // Surrogate pair.
    if hi >= 0xD800, hi <= 0xDBFF {
      guard i + 1 < scalars.count, scalars[i] == "\\", scalars[i + 1] == "u" else {
        throw err("expected low surrogate")
      }
      i += 2
      let lo = try readHex4()
      // The LOW half must be IN the low-surrogate range, and checking it is not
      // pedantry about a spelling: the arithmetic below subtracts 0xDC00
      // unconditionally, so any other value shifts the result by an arbitrary amount.
      // A high surrogate followed by an escape for U+0041 combined to U+0F83D — a
      // Tibetan character bearing no relation to either half — and the
      // `Unicode.Scalar` guard below said nothing about it, because the sum happened
      // to land on a scalar that exists. A malformed pair became a plausible-looking
      // wrong character, silently, in decoded document text.
      guard lo >= 0xDC00, lo <= 0xDFFF else {
        throw err("expected a low surrogate (DC00-DFFF) after a high surrogate")
      }
      let combined = 0x10000 + ((hi - 0xD800) << 10) + (lo - 0xDC00)
      guard let s = Unicode.Scalar(combined) else { throw err("invalid surrogate pair") }
      return s
    }
    // An UNPAIRED low surrogate is refused by name. It is not a valid scalar on its
    // own, so the guard below already returns nil for it — but that reports "invalid
    // unicode escape", which sends an author to inspect their hex digits rather than
    // to notice the missing high half.
    if hi >= 0xDC00, hi <= 0xDFFF {
      throw err("a low surrogate (DC00-DFFF) must follow a high surrogate (D800-DBFF)")
    }
    guard let s = Unicode.Scalar(hi) else { throw err("invalid unicode escape") }
    return s
  }

  private mutating func readHex4() throws -> Int {
    var value = 0
    for _ in 0..<4 {
      guard i < scalars.count else { throw err("truncated \\u escape") }
      let c = scalars[i]
      i += 1
      guard let d = hexDigit(c) else { throw err("invalid hex digit in \\u escape") }
      value = value * 16 + d
    }
    return value
  }

  private func hexDigit(_ c: Unicode.Scalar) -> Int? {
    switch c {
    case "0"..."9": return Int(c.value - 48)
    case "a"..."f": return Int(c.value - 97 + 10)
    case "A"..."F": return Int(c.value - 65 + 10)
    default: return nil
    }
  }

  private mutating func parseNumber() throws -> Double {
    let start = i
    if peek() == "-" { i += 1 }
    while i < scalars.count {
      let c = scalars[i]
      switch c {
      case "0"..."9", ".", "e", "E", "+", "-": i += 1
      default:
        return try finishNumber(from: start)
      }
    }
    return try finishNumber(from: start)
  }

  private func finishNumber(from start: Int) throws -> Double {
    let text = String(String.UnicodeScalarView(scalars[start..<i]))
    guard let d = Double(text) else { throw err("invalid number '\(text)'") }
    return d
  }
}

/// A structured, recoverable decode failure. Codes + `$`-rooted dotted paths
/// mirror the reference hosts so a rejection is host-neutral. (For the v1
/// render projection the decoder is exercised over the valid node corpus; the
/// error surface exists so an unknown discriminator hard-refuses rather than
/// falling to a silent fallback arm.)
public struct FuaranDecodeError: Error, Equatable {
  public enum Code: String, Equatable, Sendable {
    case invalidJson = "INVALID_JSON"
    case missingField = "MISSING_FIELD"
    case wrongType = "WRONG_TYPE"
    case unknownDuCase = "UNKNOWN_DU_CASE"
    case emptyNodeId = "EMPTY_NODE_ID"
    case wrongNodeKind = "WRONG_NODE_KIND"

    /// A ``WireLimits`` resource bound is breached — node depth, JSON depth, string
    /// length, array length, or total node count. The input is well-formed JSON; it is
    /// refused for being structurally unbounded, which is exactly why this is not
    /// ``invalidJson``: calling a well-formed-but-too-deep document malformed is an
    /// actively wrong diagnosis. `message` names the limit and the observed shape, so an
    /// author repairing the document knows which bound to come back under.
    case limitExceeded = "LIMIT_EXCEEDED"
  }

  public let code: Code
  public let path: String
  public let message: String

  public init(code: Code, path: String, message: String) {
    self.code = code
    self.path = path
    self.message = message
  }
}
