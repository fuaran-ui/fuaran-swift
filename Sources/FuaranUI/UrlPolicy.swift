// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The URL safety floor for tree-supplied destinations.
//
// The native surface has NO WebView and no HTML-parsing text path, so it carries
// no direct script-injection sink — that is a structural property of rendering a
// decoded tree into native views, and it is worth stating because it is the whole
// reason this file is small. What it does NOT remove is the *destination* sink: a
// `Link.href`, an `Image.src` and a `Navigate.route` all arrive from the tree, and
// an embedding app that hands one to `UIApplication.open` (or an `NSWorkspace`
// open, or a web view it adds later) has a scheme-injection / deep-link sink the
// wire format never promised it was safe from.
//
// The projection deliberately hands those values on RAW — `href` / `src` are
// `Binding`s, so their value may not exist until the core resolves a `State`,
// `Query` or `Format` slot at render time, and a decode-time allowlist would then
// be checking a placeholder. The floor therefore lives here, as a pure function
// the embedding app calls at the moment it has a resolved string, plus
// `sanitized*` accessors for the common case where the binding IS a literal.
//
// Consumer obligation, stated once and loudly: **never pass a tree-supplied URL to
// an open/navigate API without routing it through `FuaranUrlPolicy` first.**

/// The result of applying the URL floor to a tree-supplied destination.
///
/// Three states rather than an optional, because "rejected" and "not knowable
/// yet" call for different handling: a rejected URL is a document the app should
/// refuse to follow, while a dynamic one is a value the app must resolve itself
/// (through the session's state / query channel) and then re-check.
public enum SanitizedUrl: Equatable, Sendable {
  /// A literal destination that passed the allowlist. Safe to open.
  case allowed(String)
  /// A literal destination that failed the allowlist. Do not open it.
  case rejected(raw: String, reason: String)
  /// The slot holds a non-literal `Binding` — resolve it against the session,
  /// then call `FuaranUrlPolicy.sanitize` on the resolved string.
  case dynamic

  /// The URL when it is both literal and allowed; `nil` in every other case.
  /// The convenience for a call site that simply must not open anything else.
  public var openable: String? {
    if case .allowed(let url) = self { return url }
    return nil
  }
}

/// The scheme allowlist every tree-supplied destination is measured against.
///
/// Deliberately narrower than a browser's: a native surface has no legitimate
/// use for `data:`, `blob:`, `file:` or a custom app scheme it was handed by a
/// document, and an unknown scheme is refused rather than passed through — a
/// deny-by-default posture matching the closed-vocabulary stance the decoder
/// takes everywhere else.
public enum FuaranUrlPolicy {
  /// The four schemes a tree may name. `mailto` and `tel` are here because a
  /// contact link is an ordinary thing for a document to carry and both are
  /// handled by the platform without a fetch.
  public static let allowedSchemes: [String] = ["http", "https", "mailto", "tel"]

  /// Schemes refused by name, so the refusal reason can teach rather than say
  /// "unknown scheme". Anything not in `allowedSchemes` is refused regardless.
  public static let deniedSchemes: [String] = [
    "javascript", "vbscript", "data", "file", "blob", "about",
  ]

  /// The scheme candidate of a URL, lower-cased, or `nil` when the URL carries
  /// no scheme (relative path, query, or fragment).
  ///
  /// ASCII whitespace and C0 controls are stripped from the candidate before
  /// comparison, so `java\tscript:` classifies as `javascript` — the classic
  /// evasion, and the reason a naive `hasPrefix("javascript:")` check is not a
  /// floor.
  static func scheme(of url: String) -> String? {
    var candidate = ""
    for ch in url.unicodeScalars {
      switch ch {
      case ":": return candidate.trimmingASCIIWhitespace().lowercased()
      case "/", "?", "#": return nil
      default:
        if ch.value > 0x20 { candidate.unicodeScalars.append(ch) }
      }
    }
    return nil
  }

  /// Apply the floor to an already-resolved URL string.
  ///
  /// Accepted: the empty string (a same-page destination), a relative path or
  /// fragment, and an absolute URL whose scheme is in `allowedSchemes`.
  /// Refused: any other scheme; a **protocol-relative** `//host` form (it
  /// inherits whatever scheme the caller happens to be using, which on a native
  /// surface is not a meaningful thing to inherit); and any **backslash** form
  /// (`\\host`, `/\host`), which several URL parsers normalise to `//` and which
  /// therefore smuggles a protocol-relative URL past a `//` check.
  public static func sanitize(_ url: String) -> String? {
    let trimmed = normalisedForFloor(url)
    if trimmed.isEmpty { return trimmed }
    if isProtocolRelative(trimmed) { return nil }
    guard let scheme = scheme(of: trimmed) else { return trimmed }
    return allowedSchemes.contains(scheme) ? trimmed : nil
  }

  /// WIRE_FORMAT §19 rule 1 — normalise a URL string exactly as the WHATWG URL
  /// Standard's basic URL parser does BEFORE it parses anything, ASCII-exact, in
  /// this order:
  ///
  ///   1. remove leading and trailing C0-control-or-space — ALL of U+0000–U+0020,
  ///      not merely the whitespace subset;
  ///   2. remove every U+0009 / U+000A / U+000D from anywhere in what remains.
  ///
  /// Deliberately NOT a stdlib trim. A native trim answers a different question in
  /// every language — Python's `strip` also removes U+001C–U+001F where Swift, JS,
  /// .NET, Go and Rust do not — and all of them remove non-ASCII whitespace
  /// (U+00A0, U+2028, …) that the parser KEEPS. The floor's whole purpose is that a
  /// tree vetted on one host is safe on another, so the normalisation has to be
  /// defined by the parser that will actually consume the string rather than by the
  /// host's standard library.
  ///
  /// Step 2 is those three scalars ONLY: the parser removes U+000B and U+000C at the
  /// EDGES (step 1) and KEEPS them in the interior, so `/<VT>/host/x` is an ordinary
  /// same-origin path and must stay one.
  ///
  /// The normalised form is also what is EMITTED on acceptance, so an accepted URL
  /// carrying an interior tab loses it — which is what the browser would have parsed
  /// anyway. Emitting the raw string instead would hand the embedding app a value the
  /// floor never actually inspected.
  static func normalisedForFloor(_ url: String) -> String {
    var scalars = Array(url.unicodeScalars)
    while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
    while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
    scalars.removeAll { $0.value == 0x09 || $0.value == 0x0A || $0.value == 0x0D }
    return String(String.UnicodeScalarView(scalars))
  }

  /// A protocol-relative URL: `//host/path`, plus the backslash forms browsers
  /// normalise to it. WHATWG URL parsing treats `\` as `/` for special schemes, so
  /// `\\host`, `/\host` and `\/host` all resolve exactly as `//host` does.
  ///
  /// These carry no scheme, so the schemeless branch of `sanitize` would otherwise
  /// admit them — but the resolver supplies the CURRENT origin's scheme and lands
  /// OFF-ORIGIN, defeating the same-origin intent that makes a schemeless URL safe
  /// in the first place.
  ///
  /// The test is POSITIONAL — the first two characters — rather than "contains a
  /// backslash". That distinction is the whole finding: a blanket contains-check
  /// refuses `\host` (a single leading backslash, which the parser reads as the
  /// same-origin path `/host`), while a single interior tab slips `/<TAB>/host`
  /// past a `hasPrefix("//")` check entirely. Normalise first, then test position,
  /// and both come out right.
  static func isProtocolRelative(_ url: String) -> Bool {
    let s = Array(url.unicodeScalars)
    guard s.count >= 2 else { return false }
    let a = s[0]
    let b = s[1]
    return (a == "/" || a == "\\") && (b == "/" || b == "\\")
  }

  /// `sanitize`, with the refusal reason retained for the `SanitizedUrl` cases.
  static func classify(_ url: String) -> SanitizedUrl {
    if let ok = sanitize(url) { return .allowed(ok) }
    let trimmed = normalisedForFloor(url)
    if isProtocolRelative(trimmed) {
      return .rejected(
        raw: url,
        reason:
          "protocol-relative URLs are refused — '\(trimmed)' resolves off-origin (the backslash forms normalise to '//' too)"
      )
    }
    let scheme = self.scheme(of: trimmed) ?? "<none>"
    if deniedSchemes.contains(scheme) {
      return .rejected(raw: url, reason: "the '\(scheme):' scheme is refused")
    }
    return .rejected(
      raw: url,
      reason: "scheme '\(scheme):' is not one of "
        + allowedSchemes.map { "\($0):" }.joined(separator: " ") + " (deny by default)")
  }
}

extension String {
  fileprivate func trimmingASCIIWhitespace() -> String {
    var scalars = Array(unicodeScalars)
    while let first = scalars.first, first.value <= 0x20 { scalars.removeFirst() }
    while let last = scalars.last, last.value <= 0x20 { scalars.removeLast() }
    return String(String.UnicodeScalarView(scalars))
  }
}

// ── Sanitising accessors on the decoded tree ────────────────────────────────
//
// These cover the literal case — by far the most common shape a model emits —
// and report `.dynamic` for everything else rather than guessing.

extension Binding {
  /// The literal string this binding carries, when it is a `Static` string (or
  /// a `Static` optional-string slot); `nil` for every dynamic case.
  public var literalString: String? {
    guard case .staticValue(let v) = self else { return nil }
    switch v {
    case .ast(.string(let s)): return s
    case .stringOpt(let s): return s
    default: return nil
    }
  }

  /// This binding's literal value put through the URL floor.
  public var sanitizedUrl: SanitizedUrl {
    guard let literal = literalString else { return .dynamic }
    return FuaranUrlPolicy.classify(literal)
  }
}

extension LinkSpec {
  /// `href` put through the URL floor. **Use this, not `href`, when the value
  /// is about to be opened.**
  public var sanitizedHref: SanitizedUrl { href.sanitizedUrl }
}

extension ImageSpec {
  /// `src` put through the URL floor. **Use this, not `src`, when the value is
  /// about to be fetched.**
  public var sanitizedSrc: SanitizedUrl { src.sanitizedUrl }
}

extension Action {
  /// For a `Navigate` action, its `route` put through the URL floor; `nil` for
  /// every other action. A `Navigate` route is always a literal on the wire, so
  /// this never reports `.dynamic`.
  ///
  /// The surface itself does not route a `Navigate` anywhere — it is handed to
  /// the embedding app, which is exactly why the app must floor it before
  /// turning it into an open call.
  public var sanitizedNavigateRoute: SanitizedUrl? {
    guard case .navigate(let route) = self else { return nil }
    return FuaranUrlPolicy.classify(route)
  }
}
