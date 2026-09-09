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

  /// **§19.1 — the `embed` class**: a stricter floor for a slot that EXECUTES.
  ///
  /// `EmbedSpec.src` does not ride `allowedSchemes`. Everything else §19 governs
  /// is fetch-and-display or navigate-on-a-click; an embed is
  /// fetch-and-**execute**, and the floor for it is correspondingly narrower:
  /// normalise exactly as ``normalisedForFloor(_:)`` does and extract the scheme
  /// exactly as ``scheme(of:)`` does — sharing both is deliberate, because that
  /// is what makes any positional or prefix test see the string a browser's
  /// parser will see — then **accept if and only if the scheme is `https`**.
  ///
  /// **Two of the exclusions are things §19 accepts, and both are deliberate.**
  /// `http` is refused because a document delivered over a channel any
  /// intermediary can rewrite is an intermediary's script running in a frame
  /// this page created — a risk that does not arise when the same channel
  /// delivers an image. And a **schemeless** reference is refused, which is the
  /// sharper departure: a relative reference names a same-origin document, and a
  /// same-origin frame is exactly the shape where a document granted both
  /// `AllowSameOrigin` and `AllowScripts` can reach its own frame ELEMENT and
  /// remove the sandbox attribute from it. A host that wants to compose its own
  /// content has `Mount`; this kind is for the uncooperative third party.
  ///
  /// **The class admits no schemeless reference, so it needs no protocol-relative
  /// test** — and that is a property rather than an omission. The general floor
  /// needs one because its schemeless branch would otherwise admit `//host`; a
  /// class that accepts exactly one scheme performs no positional test and
  /// cannot inherit that surface. The check is still run on the normalised
  /// string, so `htt\tps:` classifies as `https` exactly as it does above.
  ///
  /// This is a RENDER-time obligation and NOT a wire constraint: a document
  /// naming an `http` or relative embed source is a valid wire document, the
  /// decoder does not reject it, and this surface carries the value through
  /// unchanged — which is why the check lives here and not in `embedSpec`.
  public static func sanitizeEmbed(_ url: String) -> String? {
    let trimmed = normalisedForFloor(url)
    guard scheme(of: trimmed) == "https" else { return nil }
    return trimmed
  }

  /// ``sanitizeEmbed(_:)``, with the refusal reason retained.
  static func classifyEmbed(_ url: String) -> SanitizedUrl {
    if let ok = sanitizeEmbed(url) { return .allowed(ok) }
    let trimmed = normalisedForFloor(url)
    let scheme = self.scheme(of: trimmed)
    guard let scheme else {
      return .rejected(
        raw: url,
        reason:
          "the embed class admits no schemeless reference — a relative source names a same-origin document, and a same-origin frame is where a document granted both AllowSameOrigin and AllowScripts can reach its own frame element and remove the sandbox from it"
      )
    }
    return .rejected(
      raw: url,
      reason: "the embed class accepts 'https:' only; '\(scheme):' is refused "
        + "(an embed is fetch-and-execute, not fetch-and-display)")
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

extension SrcSetEntry {
  /// A `srcSet` candidate is a URL a client fetches with NO user act — the same
  /// class as the primary `src`, and therefore the same obligation. A slot that
  /// skipped the floor would be a documented way around it (§3.6.4).
  ///
  /// Note what a refusal MEANS here differs from the primary source's: a
  /// candidate that fails the floor is DROPPED from the emitted list rather
  /// than emitted in neutered form, because the primary `src` must exist so it
  /// collapses to the refusal substitute, while a candidate has no such
  /// obligation and offering a client a rendition guaranteed to fail is worse
  /// than offering it one fewer.
  public var sanitizedSrc: SanitizedUrl { src.sanitizedUrl }
}

extension MediaSpec {
  /// `src` put through the URL floor. A media source is fetched with no user
  /// act exactly as an image source is.
  public var sanitizedSrc: SanitizedUrl { src.sanitizedUrl }

  /// The `Video` poster put through the same floor; `nil` on `Audio` and on a
  /// `Video` carrying no poster.
  ///
  /// The dropped-candidate rule of §3.6.4 applied to a single slot: a refused
  /// poster simply LEAVES. A `<video>` with no poster shows its first frame,
  /// which is a working rendering; a poster pointing at the refusal URL is a
  /// broken image painted over the player.
  public var sanitizedPoster: SanitizedUrl? {
    guard case .video(_, let poster) = kind, let poster else { return nil }
    return poster.sanitizedUrl
  }
}

extension EmbedSpec {
  /// `src` put through the **`embed`** egress class (§19.1), never the general
  /// floor. **Use this, not `src`, when the value is about to become a browsing
  /// context.**
  ///
  /// Naming the class explicitly matters beyond the scheme set: a composition
  /// that declared an origin for image egress has said nothing about which
  /// DOCUMENTS it is willing to run, so a surface that checked an embed under
  /// `media`'s class would let the first declaration answer the second question.
  ///
  /// What a refusal COSTS here is unlike every other slot on this surface, and
  /// it is the one place a refusal does not take a substitute destination: see
  /// `embedFramePlan`, which omits the source entirely and records the refusal
  /// as a separate fact.
  public var sanitizedSrc: SanitizedUrl {
    guard let literal = src.literalString else { return .dynamic }
    return FuaranUrlPolicy.classifyEmbed(literal)
  }
}

extension TrackEntry {
  /// A track file is fetched by the browser with NO user act, so it carries the
  /// same §19 render-time obligation `src` and `poster` do (§3.6.6 obligation
  /// 4).
  ///
  /// It takes the POSTER's disposition rather than the primary source's: an
  /// element must have a source, but it need not have this track, and a track
  /// pointing at a refusal URL is a menu entry that opens onto nothing. The
  /// general floor, not the embed class — a caption file is fetch-and-display.
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
  ///
  /// Phase 1536 — the route is a `TextSource`, so only its LITERAL arm has a
  /// destination a static classification can see. A bound route is `dynamic`
  /// for the same reason a bound `href` is: the string the router receives is
  /// resolved at dispatch, and §3.6.21 states the obligation as RESOLVE, THEN
  /// GATE — classifying the declaration would consult the floor about a
  /// template nobody navigates to while the string that matters went
  /// unexamined.
  public var sanitizedNavigateRoute: SanitizedUrl? {
    guard case .navigate(let route, _) = self else { return nil }
    guard case .literal(let text) = route else { return .dynamic }
    return FuaranUrlPolicy.classify(text)
  }
}
