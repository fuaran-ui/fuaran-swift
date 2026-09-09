// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The per-kind spec decode legs of the render projection, plus the node
// envelope and the `NodeKind` dispatch (including the legacy decode-upgrade
// tags folded onto their modern equivalents). Ported from the reference host.

import Foundation

extension Decode {
  // ── Display specs ──────────────────────────────────────────────────────────

  static func metricSpec(_ path: String, _ j: JSON) throws -> MetricSpec {
    let f = try object(path, j)
    var trendFormat: CellFormat? = nil
    if let v = f["trendFormat"] { trendFormat = try cellFormat("\(path).trendFormat", v) }
    return MetricSpec(
      label: try reqTextSource(path, f, "label"),
      // 0.2.0 rename law — scalar displayed value ⇒ `value`; the retired
      // `source` spelling is a hard error, the web-prior `data` alias remains.
      value: try reqBindingSlotAliased(path, f, "value", ["data"], .float),
      // Phase 460 — the stylistic fields are omitted-when-default on the wire.
      format: try optCellFormatDefault(path, f, "format"),
      tone: try optToneDefault(path, f, "tone"),
      weight: try optWeightDefault(path, f, "weight"),
      emphasis: try optEmphasisDefault(path, f, "emphasis"),
      trend: try optBindingSlot(path, f, "trend", .float),
      trendFormat: trendFormat,
      // Phase 867 §3.6.1 — omitted-when-default, decoded independently of
      // `trend`; an inert declaration round-trips rather than being dropped.
      trendPolarity: try optTrendPolarityDefault(path, f, "trendPolarity"),
      icon: try optString(path, f, "icon"),
      subtext: try optTextSource(path, f, "subtext"))
  }

  static func headingSpec(_ path: String, _ j: JSON) throws -> HeadingSpec {
    let f = try object(path, j)
    return HeadingSpec(
      level: try reqInt(path, f, "level"),
      text: try reqTextSource(path, f, "text"),
      variant: try headingVariant("\(path).variant", try req(path, f, "variant")))
  }

  static func labelValueRowSpec(_ path: String, _ j: JSON) throws -> LabelValueRowSpec {
    let f = try object(path, j)
    // The `emphasis` here is the behavioural bool: 0.2.2 omitted-when-false,
    // cross-vocab coerced when a model writes the enum spelling.
    let emphasis: Bool
    if let v = f["emphasis"] {
      emphasis = try emphasisFlag("\(path).emphasis", v)
    } else {
      emphasis = false
    }
    return LabelValueRowSpec(
      label: try reqTextSource(path, f, "label"),
      // 0.2.0 rename law — scalar displayed value ⇒ `value` (`data` alias kept).
      value: try reqBindingSlotAliased(path, f, "value", ["data"], .float),
      format: try optCellFormatDefault(path, f, "format"),
      emphasis: emphasis,
      help: try optTextSource(path, f, "help"))
  }

  static func factSpec(_ path: String, _ j: JSON) throws -> FactSpec {
    let f = try object(path, j)
    let emphasis: Bool
    if let v = f["emphasis"] {
      emphasis = try emphasisFlag("\(path).emphasis", v)
    } else {
      emphasis = false
    }
    return FactSpec(
      label: try reqTextSource(path, f, "label"),
      value: try reqTextSource(path, f, "value"),
      emphasis: emphasis,
      tone: try optToneDefault(path, f, "tone"),
      help: try optTextSource(path, f, "help"),
      icon: try optString(path, f, "icon"))
  }

  static func markdownSpec(_ path: String, _ j: JSON) throws -> MarkdownSpec {
    let f = try object(path, j)
    return MarkdownSpec(text: try reqTextSource(path, f, "text"))
  }

  static func badgeSpec(_ path: String, _ j: JSON) throws -> BadgeSpec {
    let f = try object(path, j)
    return BadgeSpec(
      label: try reqTextSource(path, f, "label"),
      variant: try badgeVariant("\(path).variant", try req(path, f, "variant")))
  }

  static func linkSpec(_ path: String, _ j: JSON) throws -> LinkSpec {
    let f = try object(path, j)
    // `protection` is an optional closed BARE enumeration — a plain string, no
    // `$type` on the wire — so an unknown case is UNKNOWN_DU_CASE at
    // `$.kind.protection`, with no `.$type` suffix (Phase 1073; the corpus
    // reject family pins exactly that path).
    let protection: LinkProtection? =
      try f["protection"].map { try bareEnum("\(path).protection", $0, "LinkProtection") }
    return LinkSpec(
      href: try reqBindingSlot(path, f, "href", .str),
      label: try reqTextSource(path, f, "label"),
      download: try reqBool(path, f, "download"),
      rel: try optString(path, f, "rel"),
      target: try optString(path, f, "target"),
      protection: protection)
  }

  /// §3.6.4 — one `srcSet` entry. `width` is checked for the POSITIVE floor
  /// here, at decode, because the floor is a decode rule (a `0w` candidate is
  /// one a client can never select). The refusal names the entry by INDEX, so
  /// a corpus fixture that puts a well-formed entry first has to see the
  /// second identified.
  static func srcSetEntry(_ path: String, _ j: JSON) throws -> SrcSetEntry {
    let f = try object(path, j)
    let width = try reqInt(path, f, "width")
    guard width >= 1 else {
      throw wrongType("\(path).width", "a positive integer pixel width (>= 1)")
    }
    return SrcSetEntry(src: try reqBindingSlot(path, f, "src", .str), width: width)
  }

  static func imageSpec(_ path: String, _ j: JSON) throws -> ImageSpec {
    let f = try object(path, j)
    // §3.6.4 — absent MEANS the empty list. An explicit `null` is REFUSED
    // (`WRONG_TYPE` at `$.kind.srcSet`) rather than read as absence: absence
    // already has a spelling, and admitting a second would let two conformant
    // hosts emit different canonical bytes for one document. `array` refuses a
    // `.null` at exactly that path, so the refusal falls out of the reader
    // rather than needing a branch of its own. AUTHORED ORDER is preserved —
    // `map` over the parsed array, never a sort.
    var srcSet: [SrcSetEntry] = []
    if let v = f["srcSet"] {
      srcSet = try array("\(path).srcSet", v).enumerated()
        .map { try srcSetEntry("\(path).srcSet[\($0.0)]", $0.1) }
    }
    return ImageSpec(
      alt: try reqTextSource(path, f, "alt"),
      src: try reqBindingSlot(path, f, "src", .str),
      variant: try bareEnum("\(path).variant", try req(path, f, "variant"), "ImageVariant"),
      // §3.6.2 — bare enums, so an unknown token reports at the FIELD's own
      // path with no `.$type` suffix (Phase 1073; `reject-unknown-image-aspect`
      // pins it). Absent decodes to the identity default, which is what makes a
      // pre-1077 document decode to today's behaviour.
      fit: try f["fit"].map { try bareEnum("\(path).fit", $0, "ImageFit") } ?? .natural,
      aspectRatio: try f["aspectRatio"].map {
        try bareEnum("\(path).aspectRatio", $0, "ImageAspect")
      } ?? .natural,
      loading: try f["loading"].map { try bareEnum("\(path).loading", $0, "ImageLoading") }
        ?? .eager,
      // §3.6.3 — a TextSource, so the enveloped `{"$type":"Literal","text":…}`
      // input canonicalises exactly as it does on `alt`.
      caption: try optTextSource(path, f, "caption"),
      srcSet: srcSet,
      // §3.6.5 — a plain bool. A stringified boolean is REFUSED rather than
      // coerced: a truthiness rule would have to rule on `"false"` and `""` as
      // well, and two hosts ruling differently would disagree about whether a
      // document declares an affordance at all.
      expandable: try optBool(path, f, "expandable") ?? false)
  }

  /// §3.6.6 — the `MediaKind` variant, `$type`-discriminated at `kind.kind`.
  /// The set is CLOSED at `Video | Audio`, so an unknown case reports at
  /// `$.kind.kind.$type` — the `Binding` / `TextSource` position, not the
  /// bare-enum one (§6) — and admitting a third surface later is an ADDITION
  /// rather than a re-meaning of shipped bytes.
  static func mediaKind(_ path: String, _ j: JSON) throws -> MediaKind {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Video":
      return .video(
        autoplay: try optBool(path, f, "autoplay") ?? false,
        poster: try optBindingSlot(path, f, "poster", .str))
    // No slot is read here, and that is the point: `Audio` declares none, so
    // an `"autoplay":true` riding an Audio payload has nowhere to land.
    case "Audio":
      return .audio
    case let other:
      throw unknownEnumCase("\(path).$type", other, "MediaKind: Video | Audio")
    }
  }

  /// §3.6.6 (Phase 1110) — one `TrackEntry`, the strictest record on the wire.
  ///
  /// FOUR required members and one omitted-at-`false` slot, and the strictness
  /// is the contract rather than this host being fussy: a track with no
  /// language is one nothing downstream can route, and an unlabelled track is
  /// offered as its kind alone, so a reader choosing between a plain and a
  /// verbose captions cut is shown two identical choices.
  ///
  /// **The path carries the array index** (`$.kind.tracks[0].srcLang`), which is
  /// why this reader takes the already-indexed path from its caller rather than
  /// composing one: a document with four tracks must name the one at fault.
  ///
  /// `default` goes through the ordinary strict `bool` reader, so the
  /// stringified boolean is REFUSED rather than coerced. That is the position
  /// `reject-media-track-default-nonbool` pins — one level further in than
  /// `reject-media-autoplay-nonbool`, at exactly the place a host decoding array
  /// ELEMENTS with a looser walker than its records gets it wrong. This host was
  /// that host until this change: the whole slot was unmodelled, so both track
  /// reject vectors decoded happily.
  static func trackEntry(_ path: String, _ j: JSON) throws -> TrackEntry {
    let f = try object(path, j)
    return TrackEntry(
      kind: try bareEnum("\(path).kind", try req(path, f, "kind"), "TrackKind"),
      src: try reqBindingSlot(path, f, "src", .str),
      srcLang: try reqString(path, f, "srcLang"),
      label: try reqTextSource(path, f, "label"),
      isDefault: try optBool(path, f, "default") ?? false)
  }

  static func mediaSpec(_ path: String, _ j: JSON) throws -> MediaSpec {
    let f = try object(path, j)
    // §3.6.6 — absent MEANS the empty list, exactly as `ImageSpec.srcSet` does,
    // and AUTHORED ORDER is preserved: `map` over the parsed array, never a
    // sort. The re-sort is the failure this slot is most likely to attract,
    // because the neighbouring `srcSet` rule is its exact opposite.
    var tracks: [TrackEntry] = []
    if let v = f["tracks"] {
      tracks = try array("\(path).tracks", v).enumerated()
        .map { try trackEntry("\(path).tracks[\($0.0)]", $0.1) }
    }
    return MediaSpec(
      kind: try mediaKind("\(path).kind", try req(path, f, "kind")),
      // REQUIRED — a transport is never decorative, so there is no default to
      // fall back to (`reject-media-missing-label`, MISSING_FIELD at
      // `$.kind.label`).
      label: try reqTextSource(path, f, "label"),
      src: try reqBindingSlot(path, f, "src", .str),
      // Omitted at TRUE — the `Toast.dismissable` polarity.
      controls: try optBool(path, f, "controls") ?? true,
      loop: try optBool(path, f, "loop") ?? false,
      tracks: tracks,
      // An ORDINARY optional: absent means the document offers no transcript,
      // which is a different statement from offering an empty one.
      transcript: try optTextSource(path, f, "transcript"))
  }

  // ── Embed (§3.6.8) ─────────────────────────────────────────────────────────

  /// §3.6.8 (Phase 1111) — the sandboxed third-party embed.
  ///
  /// `EmbedPermission` is a BARE enum (§3.5), so an unrecognised token reports
  /// at the ELEMENT's own path with no `$type` suffix —
  /// `$.kind.permissions[0]`, which is what `reject-embed-unknown-permission`
  /// pins against the HTML token `"allow-top-navigation"` an author reaches for
  /// from memory.
  ///
  /// **A decoder MUST NOT silently drop an unrecognised permission.** That would
  /// turn a document asking for something this vocabulary has no name for into a
  /// document asking for LESS, which reads as success — the one failure mode a
  /// default-deny list makes tempting. A non-string element is `WRONG_TYPE` at
  /// the same path (`reject-embed-permission-nonstring`): a bare `true` is
  /// refused rather than read as a present-and-enabled flag, since a host that
  /// coerced it would have to invent WHICH permission it names.
  static func embedSpec(_ path: String, _ j: JSON) throws -> EmbedSpec {
    let f = try object(path, j)
    var permissions: [EmbedPermission] = []
    if let v = f["permissions"] {
      permissions = try array("\(path).permissions", v).enumerated()
        .map { try bareEnum("\(path).permissions[\($0.0)]", $0.1, "EmbedPermission") }
    }
    return EmbedSpec(
      src: try reqBindingSlot(path, f, "src", .str),
      // REQUIRED (`reject-embed-missing-title`, MISSING_FIELD at
      // `$.kind.title`) — an invented title is a claim about somebody else's
      // document.
      title: try reqTextSource(path, f, "title"),
      permissions: permissions,
      // REUSES `ImageAspect`; a bare enum, so an unknown token reports at the
      // field's own path with no `.$type` suffix.
      aspectRatio: try f["aspectRatio"].map {
        try bareEnum("\(path).aspectRatio", $0, "ImageAspect")
      } ?? .natural)
  }

  // ── Tree (§3.6.12) ─────────────────────────────────────────────────────────

  /// §3.6.12 / §21.5 (Phase 1120) — one `TreeItem`, and the format's first
  /// self-referential recursion.
  ///
  /// The §21.5 item budget is entered HERE, before the shape check, so a
  /// hierarchy past the bound is refused for being too deep rather than for
  /// whatever the over-deep value happens to look like — the `enterNode`
  /// ordering, applied to the axis that node counter structurally cannot see.
  ///
  /// `id` and `label` are required at every level, and the nested reject vector
  /// exists because a host whose child walker is looser than its root walker
  /// passes the two top-level ones. There is exactly one reader here and the
  /// recursion goes through it, so that divergence is unavailable.
  static func treeItem(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> TreeItem {
    try walk.enterItem(path)
    defer { walk.exitItem() }
    let f = try object(path, j)
    var children: [TreeItem] = []
    if let v = f["children"] {
      children = try array("\(path).children", v).enumerated()
        .map { try treeItem("\(path).children[\($0.0)]", $0.1, walk) }
    }
    return TreeItem(
      id: try reqString(path, f, "id"),
      label: try reqTextSource(path, f, "label"),
      icon: try optString(path, f, "icon"),
      children: children)
  }

  static func treeSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> TreeSpec {
    let f = try object(path, j)
    let items = try array("\(path).items", try req(path, f, "items")).enumerated()
      .map { try treeItem("\(path).items[\($0.0)]", $0.1, walk) }
    return TreeSpec(
      items: items,
      // Both State slots are NAMES, never state. A host reads the value under
      // the named key; nothing about the reader's current expansion or
      // selection rides the wire.
      expandedStateKey: try optString(path, f, "expandedStateKey"),
      selectionStateKey: try optString(path, f, "selectionStateKey"),
      onSelect: optClosure(f, "onSelect"))
  }

  static func listSpec(_ path: String, _ j: JSON) throws -> ListSpec {
    let f = try object(path, j)
    let items = try array("\(path).items", try req(path, f, "items")).enumerated()
      .map { try textSource("\(path).items[\($0.0)]", $0.1) }
    return ListSpec(items: items, ordered: try reqBool(path, f, "ordered"))
  }

  static func toastSpec(_ path: String, _ j: JSON) throws -> ToastSpec {
    let f = try object(path, j)
    return ToastSpec(
      message: try reqTextSource(path, f, "message"),
      tone: try optToneDefault(path, f, "tone"),
      open: try reqBindingSlot(path, f, "open", .bool),
      // 0.2.0 — omitted-when-TRUE (a toast is dismissable unless said
      // otherwise; the one inverted default in §3.6's table).
      dismissable: try optBool(path, f, "dismissable") ?? true)
  }

  static func codeBlockSpec(_ path: String, _ j: JSON) throws -> CodeBlockSpec {
    let f = try object(path, j)
    let lines = try array("\(path).highlightLines", try req(path, f, "highlightLines")).enumerated()
      .map { try int("\(path).highlightLines[\($0.0)]", $0.1) }
    return CodeBlockSpec(
      code: try reqString(path, f, "code"),
      language: try reqString(path, f, "language"),
      lineNumbers: try reqBool(path, f, "lineNumbers"),
      highlightLines: lines,
      copyable: try reqBool(path, f, "copyable"))
  }

  static func mathSpec(_ path: String, _ j: JSON) throws -> MathSpec {
    let f = try object(path, j)
    return MathSpec(
      source: try reqString(path, f, "source"),
      display: try bareEnum("\(path).display", try req(path, f, "display"), "MathDisplay"))
  }

  static func sparklineSpec(_ path: String, _ j: JSON) throws -> SparklineSpec {
    let f = try object(path, j)
    // Field alias: data → source.
    return SparklineSpec(source: try reqBindingSlotAliased(path, f, "source", ["data"], .floatSeq))
  }

  static func skeletonSpec(_ path: String, _ j: JSON) throws -> SkeletonSpec {
    let f = try object(path, j)
    return SkeletonSpec(rows: try reqInt(path, f, "rows"))
  }

  static func calloutSpec(_ path: String, _ j: JSON) throws -> CalloutSpec {
    let f = try object(path, j)
    return CalloutSpec(
      body: try reqTextSource(path, f, "body"),
      // 0.2.0 — omitted-when-default (false).
      dismissable: try optBool(path, f, "dismissable") ?? false,
      tone: try optToneDefault(path, f, "tone"),
      // Field alias: title → heading (Callout is in the scoped set).
      heading: try optTextSourceAliased(path, f, "heading", ["title"]),
      icon: try optString(path, f, "icon"))
  }

  static func progressSpec(_ path: String, _ j: JSON) throws -> ProgressSpec {
    let f = try object(path, j)
    return ProgressSpec(
      fraction: try reqBindingSlot(path, f, "fraction", .float),
      // 0.2.0 — omitted-when-default (false).
      indeterminate: try optBool(path, f, "indeterminate") ?? false,
      tone: try optToneDefault(path, f, "tone"),
      label: try optTextSource(path, f, "label"),
      caveat: try optTextSource(path, f, "caveat"))
  }

  // ── Drawing ────────────────────────────────────────────────────────────────

  static func viewBox(_ path: String, _ j: JSON) throws -> ViewBox {
    let f = try object(path, j)
    return ViewBox(
      minX: try reqFloat(path, f, "minX"), minY: try reqFloat(path, f, "minY"),
      width: try reqFloat(path, f, "width"), height: try reqFloat(path, f, "height"))
  }

  static func drawPoint(_ path: String, _ j: JSON) throws -> DrawPoint {
    let f = try object(path, j)
    return DrawPoint(x: try reqFloat(path, f, "x"), y: try reqFloat(path, f, "y"))
  }

  static func reqPoint(_ path: String, _ f: [String: JSON], _ key: String) throws -> DrawPoint {
    try drawPoint("\(path).\(key)", try req(path, f, key))
  }

  static func pointList(_ path: String, _ f: [String: JSON]) throws -> [DrawPoint] {
    try array("\(path).points", try req(path, f, "points")).enumerated()
      .map { try drawPoint("\(path).points[\($0.0)]", $0.1) }
  }

  static func drawStyle(_ path: String, _ j: JSON) throws -> DrawStyle {
    let f = try object(path, j)
    var textAnchor: TextAnchor? = nil
    if let v = f["textAnchor"] { textAnchor = try bareEnum("\(path).textAnchor", v, "TextAnchor") }
    var emphasis: Emphasis? = nil
    if let v = f["emphasis"] { emphasis = try emphasisEnum("\(path).emphasis", v) }
    return DrawStyle(
      fill: try optBindingSlot(path, f, "fill", .str),
      stroke: try optBindingSlot(path, f, "stroke", .str),
      strokeWidth: try optBindingSlot(path, f, "strokeWidth", .float),
      opacity: try optBindingSlot(path, f, "opacity", .float),
      textAnchor: textAnchor,
      fontSize: try optFloat(path, f, "fontSize"),
      emphasis: emphasis,
      fontFamily: try optString(path, f, "fontFamily"),
      // Phase 642 — keyed mark identity; omitted-when-None.
      markId: try optString(path, f, "markId"),
      // Label rotation (degrees, clockwise) and the per-mark hover readout. Both
      // omitted-when-None on the wire; both taken as-authored — the projection
      // re-rounds neither, so a decoded drawing carries exactly the numbers the
      // emitter wrote.
      rotation: try optFloat(path, f, "rotation"),
      tip: try optTextSource(path, f, "tip"))
  }

  static func styleOrDefault(_ path: String, _ f: [String: JSON]) throws -> DrawStyle {
    guard let v = f["style"] else { return .empty }
    return try drawStyle("\(path).style", v)
  }

  static func curveCommand(_ path: String, _ j: JSON) throws -> CurveCommand {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "MoveTo": return .moveTo(try reqPoint(path, f, "to"))
    case "LineTo": return .lineTo(try reqPoint(path, f, "to"))
    case "CubicTo":
      return .cubicTo(
        control1: try reqPoint(path, f, "control1"),
        control2: try reqPoint(path, f, "control2"), to: try reqPoint(path, f, "to"))
    case "QuadraticTo":
      return .quadraticTo(
        control: try reqPoint(path, f, "control"), to: try reqPoint(path, f, "to"))
    case "Close": return .close
    case let o: throw unknownCase(path, o, "MoveTo | LineTo | CubicTo | QuadraticTo | Close")
    }
  }

  static func shape(_ path: String, _ j: JSON) throws -> Shape {
    let f = try object(path, j)
    let style = try styleOrDefault(path, f)
    switch try disc(path, f) {
    case "Group":
      let children = try array("\(path).children", try req(path, f, "children")).enumerated()
        .map { try shape("\(path).children[\($0.0)]", $0.1) }
      return .group(children: children, style: style)
    case "Rectangle":
      return .rectangle(
        x: try reqFloat(path, f, "x"), y: try reqFloat(path, f, "y"),
        width: try reqFloat(path, f, "width"), height: try reqFloat(path, f, "height"),
        cornerRadius: try optFloat(path, f, "cornerRadius"), style: style)
    case "Line":
      return .line(
        x1: try reqFloat(path, f, "x1"), y1: try reqFloat(path, f, "y1"),
        x2: try reqFloat(path, f, "x2"), y2: try reqFloat(path, f, "y2"), style: style)
    case "Polyline": return .polyline(points: try pointList(path, f), style: style)
    case "Polygon": return .polygon(points: try pointList(path, f), style: style)
    case "Curve":
      let commands = try array("\(path).commands", try req(path, f, "commands")).enumerated()
        .map { try curveCommand("\(path).commands[\($0.0)]", $0.1) }
      return .curve(commands: commands, style: style)
    case "Circle":
      return .circle(
        cx: try reqFloat(path, f, "cx"), cy: try reqFloat(path, f, "cy"),
        r: try reqFloat(path, f, "r"), style: style)
    case "Ellipse":
      return .ellipse(
        cx: try reqFloat(path, f, "cx"), cy: try reqFloat(path, f, "cy"),
        rx: try reqFloat(path, f, "rx"), ry: try reqFloat(path, f, "ry"), style: style)
    case "Label":
      return .label(
        x: try reqFloat(path, f, "x"), y: try reqFloat(path, f, "y"),
        text: try reqTextSource(path, f, "text"), style: style)
    case let o:
      throw unknownCase(
        path, o, "Group | Rectangle | Line | Polyline | Polygon | Curve | Circle | Ellipse | Label")
    }
  }

  static func drawingSpec(_ path: String, _ j: JSON) throws -> DrawingSpec {
    let f = try object(path, j)
    let shapes = try array("\(path).shapes", try req(path, f, "shapes")).enumerated()
      .map { try shape("\(path).shapes[\($0.0)]", $0.1) }
    return DrawingSpec(
      viewBox: try viewBox("\(path).viewBox", try req(path, f, "viewBox")),
      shapes: shapes,
      style: try styleOrDefault(path, f),
      title: try optTextSource(path, f, "title"),
      description: try optTextSource(path, f, "description"))
  }

  // ── Input specs ────────────────────────────────────────────────────────────

  /// Phase 596 — the auto-bind context for a control's ABSENT `value` slot. One
  /// rule across the whole control vocabulary: every control may omit `value`;
  /// a filter chip auto-binds `Filter(name)` (0.2.0) and a form field
  /// auto-binds `State(field id)` with the slot's typed placeholder as the
  /// State default (0.2.1).
  enum ControlAutoBind {
    case filterChip(String)
    case formFieldId(String)

    func autoBinding(_ placeholder: StaticValue) -> Binding {
      switch self {
      case .filterChip(let name): return .filter(name: name, defaultValue: nil)
      case .formFieldId(let id): return .state(key: id, defaultValue: placeholder)
      }
    }
  }

  /// The typed placeholders for the 0.2.1 form-field auto-bind, pinned by the
  /// reference implementations: empty string / `0` / `false` / null-choice /
  /// `{min 0, max 0}` / ISO-empty date.
  enum ControlValueDefaults {
    static let text = StaticValue.ast(.string(""))
    static let number = StaticValue.ast(.number(0))
    static let checkbox = StaticValue.ast(.bool(false))
    static let choice = StaticValue.stringOpt(nil)
    static let range = StaticValue.floatPair(0.0, 0.0)
    static let date = StaticValue.ast(.string(""))
    /// ISO-empty both ends — the pair analogue of `date`'s "" placeholder.
    static let dateRange = StaticValue.stringPair("", "")
    /// Phase 1121 — the EMPTY LIST. The token list is ordered and the order is
    /// the reader's, so an auto-bound token field starts with no chips rather
    /// than with a placeholder one.
    static let tokens = StaticValue.stringList([])
    /// Phase 1130 — `Rating` shares `Number`'s zero placeholder: an auto-bound
    /// rating starts unrated.
    static let rating = StaticValue.ast(.number(0))
    /// Phase 1130 — the unset swatch. A native colour input substitutes its own
    /// default when handed nothing, and `#000000` is that default's wire
    /// spelling — the one `#rrggbb` form the control can hold.
    static let color = StaticValue.ast(.string("#000000"))
  }

  static func formFieldKind(
    _ autoBind: ControlAutoBind, _ path: String, _ j: JSON
  ) throws -> FormFieldKind {
    let f = try object(path, j)
    let onChange = optClosure(f, "onChange")
    let onToggle = optClosure(f, "onToggle")
    // Value slot: present ⇒ typed decode; absent ⇒ the context's auto-binding —
    // Filter(name) on a chip, State(field id, typed placeholder) on a form
    // field (Phase 596).
    func valueOr(_ slot: StaticSlot, _ placeholder: StaticValue) throws -> Binding {
      guard let v = f["value"] else { return autoBind.autoBinding(placeholder) }
      return try bindingSlot("\(path).value", v, slot)
    }
    switch try disc(path, f) {
    case "Text":
      return .text(value: try valueOr(.str, ControlValueDefaults.text), onChange: onChange)
    case "Number":
      return .number(value: try valueOr(.float, ControlValueDefaults.number), onChange: onChange)
    case "Checkbox":
      return .checkbox(
        value: try valueOr(.bool, ControlValueDefaults.checkbox), onToggle: onToggle)
    // The switch affordance beside a Checkbox: the same boolean slot, a different control.
    case "Toggle":
      return .toggle(
        value: try valueOr(.bool, ControlValueDefaults.checkbox), onToggle: onToggle)
    case "Choice":
      return .choice(
        options: try reqBindingSlot(path, f, "options", .options),
        value: try valueOr(.stringOpt, ControlValueDefaults.choice), onChange: onChange)
    // §3.6.9 (Phase 1113) — the searchable form of `Choice`, and its value
    // contract is `Choice`'s BY THE SPECIFICATION rather than by convenience:
    // `valueOr(.stringOpt, …)` is the same call one arm up, so a document
    // migrating between the two changes its `$type` and nothing else.
    case "Combobox":
      return .combobox(
        // The case's ONLY required member — a combobox with no option source is
        // not a control. A `Query` binding here IS the async suggestion feed;
        // the slot reader is the ordinary one and needs no async vocabulary.
        options: try reqBindingSlot(path, f, "options", .options),
        value: try valueOr(.stringOpt, ControlValueDefaults.choice),
        // Omitted at `false`, and read through the STRICT bool reader:
        // `reject-combobox-allowfreetext-nonbool` refuses a string rather than
        // coercing it, because the slot decides whether off-list values are
        // admitted and a truthiness rule would widen the field on `"no"` and
        // `"false"` alike.
        allowFreeText: try optBool(path, f, "allowFreeText") ?? false,
        onChange: onChange)
    // 0.2.0 — the dual-thumb numeric range (absorbed the retired RangeFilter).
    // The canonical Static pair rides as the BARE `{min, max}` object (no
    // `$type`) — accept it before the generic binding dispatch.
    case "Range":
      let value: Binding
      if case .object(let pf)? = f["value"], pf["$type"] == nil, pf["min"] != nil,
        pf["max"] != nil
      {
        value = .staticValue(try StaticSlot.floatPair.parse("\(path).value", .object(pf)))
      } else {
        value = try valueOr(.floatPair, ControlValueDefaults.range)
      }
      return .range(
        value: value, min: try optFloat(path, f, "min"), max: try optFloat(path, f, "max"),
        step: try optFloat(path, f, "step"), onChange: onChange)
    case "RangedNumber":
      return .rangedNumber(
        value: try valueOr(.float, ControlValueDefaults.number),
        min: try optFloat(path, f, "min"),
        max: try optFloat(path, f, "max"), step: try optFloat(path, f, "step"),
        onChange: onChange)
    case "SegmentedChoice":
      // Lenient omitted-when-default (§3.6): absent restores the language
      // default `Horizontal` (decode-optional).
      let orient: Orientation
      if let v = f["orientation"] {
        orient = try orientation("\(path).orientation", v)
      } else {
        orient = .horizontal
      }
      return .segmentedChoice(
        options: try reqBindingSlot(path, f, "options", .options),
        orientation: orient,
        value: try valueOr(.stringOpt, ControlValueDefaults.choice), onChange: onChange)
    case "TextArea":
      return .textArea(
        rows: try reqInt(path, f, "rows"),
        value: try valueOr(.str, ControlValueDefaults.text),
        onChange: onChange)
    case "Date":
      return .date(
        value: try valueOr(.str, ControlValueDefaults.date),
        variant: try bareEnum("\(path).variant", try req(path, f, "variant"), "DateVariant"),
        min: try optString(path, f, "min"), max: try optString(path, f, "max"),
        step: try optFloat(path, f, "step"), onChange: onChange)
    case "DateRange":
      // The canonical Static pair rides as the BARE `{from, to}` object (no
      // `$type`) — accept it before the generic binding dispatch, exactly as
      // `Range` does above. The `valueOr` fallback carries both lenient forms
      // (bare two-element array, and the explicit `Static` envelope).
      let value: Binding
      if case .object(let pf)? = f["value"], pf["$type"] == nil, pf["from"] != nil,
        pf["to"] != nil
      {
        value = .staticValue(try StaticSlot.stringPair.parse("\(path).value", .object(pf)))
      } else {
        value = try valueOr(.stringPair, ControlValueDefaults.dateRange)
      }
      return .dateRange(
        value: value,
        variant: try bareEnum("\(path).variant", try req(path, f, "variant"), "DateVariant"),
        min: try optString(path, f, "min"), max: try optString(path, f, "max"),
        step: try optFloat(path, f, "step"), onChange: onChange)
    // Phase 1121 — every member OPTIONAL, and `allowFreeText` omits at TRUE.
    // The one decode refusal is the control that CANNOT EXIST: free text denied
    // and no suggestion source, so no gesture could ever put a token in. It is
    // refused at `allowFreeText` rather than at `suggestions`, because the
    // member that was WRITTEN is the one naming the impossible state — an
    // absent `suggestions` is the ordinary open token box.
    case "Tokens":
      let suggestions = try optBindingSlot(path, f, "suggestions", .options)
      let allowFreeText = try optBool(path, f, "allowFreeText") ?? true
      if !allowFreeText && suggestions == nil {
        throw wrongType(
          "\(path).allowFreeText",
          "a Tokens field admitting no free text to declare a suggestion source — with neither, "
            + "no gesture could ever put a token into it")
      }
      return .tokens(
        value: try valueOr(.stringList, ControlValueDefaults.tokens),
        suggestions: suggestions, allowFreeText: allowFreeText, onChange: onChange)
    // Phase 1130 — `max` IS the scale, so it is required and a value below 1 is
    // refused rather than clamped. Note the asymmetry the corpus pins: the
    // SCALE is refused here and the VALUE is not, because a bound value is
    // invisible to a decoder and a rule enforced only on literals would be two
    // rules wearing one name.
    case "Rating":
      let scale = try reqInt(path, f, "max")
      if scale < 1 {
        throw wrongType(
          "\(path).max",
          "a rating scale of at least 1 — a scale with no positions has nothing to draw and no "
            + "keystroke that could change anything")
      }
      return .rating(
        value: try valueOr(.float, ControlValueDefaults.rating), max: scale,
        // Governs ENTRY granularity, never display: a host must not quantise a
        // resolved value to it.
        allowHalf: try optBool(path, f, "allowHalf") ?? false, onChange: onChange)
    // Phase 1130 — only the STATIC case is judged here, and the split is
    // recorded rather than hidden: a state / query / selection binding carries
    // its text from outside the document, where a decoder cannot see it.
    case "Color":
      let value = try valueOr(.str, ControlValueDefaults.color)
      if case .staticValue(.ast(.string(let literal))) = value, !isHexColour(literal) {
        throw wrongType(
          "\(path).value",
          "a `#rrggbb` colour — the one shape a native colour input can hold, so a literal "
            + "outside it names a colour this control could never carry")
      }
      return .color(value: value, onChange: onChange)
    case let o:
      throw unknownCase(
        path, o,
        "Text | Number | Checkbox | Choice | Combobox | Range | RangedNumber | SegmentedChoice "
          + "| TextArea | Date | DateRange | Tokens | Rating | Color"
      )
    }
  }

  /// `#rrggbb` — six hexadecimal digits after a `#`, either case (§3.6.17).
  /// Deliberately narrower than CSS: it is the one shape a native colour input
  /// can hold or return, so `#fff`, `rebeccapurple`, `rgb(0 0 0)` and an alpha
  /// channel all name a colour this control could never carry.
  static func isHexColour(_ s: String) -> Bool {
    let u = Array(s.utf8)
    return u.count == 7 && u[0] == UInt8(ascii: "#")
      && u[1...].allSatisfy {
        ($0 >= 48 && $0 <= 57) || ($0 >= 65 && $0 <= 70) || ($0 >= 97 && $0 <= 102)
      }
  }

  /// The cross-field operand: an operator plus a `Binding` to compare against.
  static func compareRule(_ path: String, _ j: JSON) throws -> CompareRule {
    let f = try object(path, j)
    return CompareRule(
      op: try bareEnum("\(path).op", try req(path, f, "op"), "CompareOp"),
      against: try reqBinding(path, f, "against"))
  }

  /// A field's declared constraint. Every slot is optional structurally, and
  /// two shapes are refused here as POLICY (mirroring the reference host):
  ///
  /// - a rule with every constraint slot absent. A rule that constrains nothing
  ///   is a defect, not a no-op: it decodes, validates and renders while
  ///   declaring nothing — the fake-affordance shape the near-miss set also
  ///   forecloses, arriving through an empty object instead of a wrong key.
  ///   `message` alone does not rescue it: the message is the prose shown when
  ///   some OTHER slot is unmet.
  /// - `minLength` above `maxLength`. An inverted bound admits no value at all,
  ///   so the field could never be submitted and the form is dead on arrival.
  ///
  /// Neither is a shape — both are relations BETWEEN slots — which is why they
  /// live here rather than in the structural layer.
  static func fieldRule(_ path: String, _ j: JSON) throws -> FieldRule {
    let f = try object(path, j)
    var format: TextFormat? = nil
    if let v = f["format"] { format = try bareEnum("\(path).format", v, "TextFormat") }
    let pattern = try optString(path, f, "pattern")
    let minLength = try optInt(path, f, "minLength")
    let maxLength = try optInt(path, f, "maxLength")
    var compare: CompareRule? = nil
    if let v = f["compare"] { compare = try compareRule("\(path).compare", v) }
    let message = try optTextSource(path, f, "message")

    if format == nil && pattern == nil && minLength == nil && maxLength == nil && compare == nil {
      throw err(
        .wrongType, path,
        "a rule that constrains nothing is a defect, not a no-op — declare at least one of "
          + "format / pattern / minLength / maxLength / compare, or omit 'rule' entirely")
    }
    if let lo = minLength, let hi = maxLength, lo > hi {
      throw err(
        .wrongType, path,
        "minLength \(lo) is above maxLength \(hi) — an inverted length bound admits no value "
          + "at all, so the field could never be submitted")
    }
    return FieldRule(
      format: format, pattern: pattern, minLength: minLength, maxLength: maxLength,
      compare: compare, message: message)
  }

  static func formField(_ path: String, _ j: JSON) throws -> FormField {
    let f = try object(path, j)
    // The near-miss check runs BEFORE the rule decode, so a field carrying both
    // `validation` and a well-formed `rule` still names the ignored key rather
    // than passing silently.
    try refuseNearMiss(
      path, f,
      [("validation", "rule"), ("constraints", "rule"), ("validate", "rule")])
    // Field alias: name → id. Id decodes first so the form context's auto-bind
    // can use it (Phase 596).
    let id = try reqStringAliased(path, f, "id", ["name"])
    var rule: FieldRule? = nil
    if let v = f["rule"] { rule = try fieldRule("\(path).rule", v) }
    return FormField(
      id: id,
      kind: try formFieldKind(.formFieldId(id), "\(path).kind", try req(path, f, "kind")),
      label: try reqTextSource(path, f, "label"),
      required: try reqBool(path, f, "required"),
      help: try optTextSource(path, f, "help"),
      rule: rule)
  }

  static func formSpec(_ path: String, _ j: JSON) throws -> FormSpec {
    let f = try object(path, j)
    let fields = try array("\(path).fields", try req(path, f, "fields")).enumerated()
      .map { try formField("\(path).fields[\($0.0)]", $0.1) }
    return FormSpec(
      fields: fields,
      onSubmit: try reqAction(path, f, "onSubmit"),
      submitLabel: try reqTextSource(path, f, "submitLabel"),
      disabled: try optBindingSlot(path, f, "disabled", .bool))
  }

  static func filterSpec(_ path: String, _ j: JSON) throws -> FilterSpec {
    let f = try object(path, j)
    // 0.2.0 filters-unification: the chip's control is an ordinary
    // FormFieldKind; its absent `value` auto-binds Filter(name). Name decodes
    // first so the synthesis can use it.
    let name = try reqString(path, f, "name")
    return FilterSpec(
      kind: try formFieldKind(.filterChip(name), "\(path).kind", try req(path, f, "kind")),
      label: try reqTextSource(path, f, "label"),
      name: name)
  }

  static func buttonSpec(_ path: String, _ j: JSON) throws -> ButtonSpec {
    let f = try object(path, j)
    return ButtonSpec(
      label: try reqTextSource(path, f, "label"),
      onClick: try reqAction(path, f, "onClick"),
      variant: try buttonVariant("\(path).variant", try req(path, f, "variant")),
      icon: try optString(path, f, "icon"),
      disabled: try optBindingSlot(path, f, "disabled", .bool))
  }

  static func selectSpec(_ path: String, _ j: JSON) throws -> SelectSpec {
    let f = try object(path, j)
    var values: Binding? = nil
    if let v = f["values"] { values = try bindingSlot("\(path).values", v, .stringList) }
    return SelectSpec(
      label: try reqTextSource(path, f, "label"),
      // Field aliases: options / data → source.
      source: try reqBindingSlotAliased(path, f, "source", ["options", "data"], .options),
      value: try reqBindingSlot(path, f, "value", .stringOpt),
      onChange: optClosure(f, "onChange"),
      placeholder: try optTextSource(path, f, "placeholder"),
      disabled: try optBindingSlot(path, f, "disabled", .bool),
      multiple: (try optBool(path, f, "multiple")) == true,
      values: values,
      onChangeMulti: optClosure(f, "onChangeMulti"))
  }

  static func fileUploadSpec(_ path: String, _ j: JSON) throws -> FileUploadSpec {
    let f = try object(path, j)
    let accept = try array("\(path).accept", try req(path, f, "accept")).enumerated()
      .map { try string("\(path).accept[\($0.0)]", $0.1) }
    // Phase 1116 — OPTIONAL, not omit-at-default: an absent member asks for the
    // ordinary picker, which is not one of the two devices wearing a default,
    // and an unrecognised value MUST NOT fall back to either device.
    var captureV: CaptureSource? = nil
    if let c = f["capture"] {
      captureV = try bareEnum("\(path).capture", c, "CaptureSource")
    }
    // Phase 1117 — the empty string is a name no host registers, so a document
    // carrying it describes an upload that can never stream. Refused rather
    // than read as absence: that coercion silently turns an upload the author
    // meant to stream into a client-only one, while every visible thing about
    // the control still works.
    let destinationV = try optString(path, f, "destination")
    if destinationV == "" {
      throw wrongType(
        "\(path).destination",
        "a registered destination name — an absent member is already the spelling for an upload "
          + "that streams nowhere")
    }
    return FileUploadSpec(
      accept: accept,
      label: try reqTextSource(path, f, "label"),
      multiple: try reqBool(path, f, "multiple"),
      disabled: try optBindingSlot(path, f, "disabled", .bool),
      // Phase 1115 — read through the STRICT bool reader: each slot decides
      // whether a whole ingress route exists, and a truthiness read would open
      // a drop target on `"no"` and `"false"` alike.
      dropTarget: try optBool(path, f, "dropTarget") ?? false,
      acceptPaste: try optBool(path, f, "acceptPaste") ?? false,
      capture: captureV,
      destination: destinationV,
      // Phase 1548 — the two declared ceilings. `maxFiles` is NOT cross-checked
      // against `multiple`: beside `"multiple":false` the member is INERT by
      // specification, and a host refusing it would reject documents every
      // other host accepts, which is the divergence a declared ceiling exists
      // to remove.
      maxBytes: try optPositive(
        path, f, "maxBytes",
        "a positive per-file byte ceiling — a ceiling of zero is not a small ceiling but an "
          + "upload that can accept no file at all, and an absent member is already the spelling "
          + "for no ceiling"),
      maxFiles: try optPositive(
        path, f, "maxFiles",
        "a positive selection-count ceiling — a multiple upload admitting zero files has no "
          + "reachable selection, and an absent member is already the spelling for no ceiling"))
  }

  /// §3.6.23 — one OPTIONAL, POSITIVE integer ceiling, read at decode.
  ///
  /// The floor is a DECODE RULE rather than a type because this format has no
  /// refined-integer type; it is the same rule `SrcSetEntry.width` and
  /// `Switch.autoAdvanceMs` already stand on, and it is mirrored by
  /// `minimum: 1` in the published JSON Schema so the two expressions of the
  /// contract agree. The strict integer reader runs FIRST and refuses a
  /// fraction, a §7 sentinel string and anything outside §7.1's signed 32-bit
  /// slot, so what is left for this guard is the sign alone.
  static func optPositive(
    _ path: String, _ f: [String: JSON], _ key: String, _ expectation: String
  ) throws -> Int? {
    guard let v = f[key] else { return nil }
    let n = try int("\(path).\(key)", v)
    guard n >= 1 else { throw wrongType("\(path).\(key)", expectation) }
    return n
  }

  // ── Visualisation specs ────────────────────────────────────────────────────

  /// The tone-map field names a `TonedPill` cell accepts, canonical first. `map` is
  /// the shortest honest name for a value→tone dictionary and the least descriptive.
  static let toneMapKeys = ["map", "toneMap", "tones"]

  /// Phase 750 — a `TonedPill`'s `map`: a string-keyed object whose VALUES are
  /// `ToneVariant`s. Routed through `toneVariant` per entry, so the §3.6 tone aliases
  /// work inside the map exactly as they do at a `tone` field; a second, private tone
  /// reader here is precisely how this position would come to accept a vocabulary the
  /// `tone` field does not.
  ///
  /// The refusal is RE-ISSUED rather than passed through, for the MESSAGE rather than
  /// the path. `unknownEnumCase` now reports at the entry's own path (Phase 1073), so
  /// the location is already right; what the raw error still says is "unknown
  /// discriminator", and a map value is neither a discriminator nor a `ToneVariant`
  /// slot by name. The re-issue keeps the code and the seven legal names, names the
  /// offending KEY and says what it should have been, because "one of your tones is
  /// wrong" is not an actionable report when the map has nine entries. A non-string
  /// value is a `wrongType` and already reports correctly, so it passes through
  /// untouched.
  static func toneMap(_ path: String, _ j: JSON) throws -> [String: ToneVariant] {
    let f = try object(path, j)
    var out: [String: ToneVariant] = [:]
    out.reserveCapacity(f.count)
    for (key, v) in f {
      let entryPath = "\(path).\(key)"
      do {
        out[key] = try toneVariant(entryPath, v)
      } catch let e as FuaranDecodeError where e.code == .unknownDuCase {
        let got: String
        if case .string(let s) = v { got = s } else { got = "" }
        throw err(
          .unknownDuCase, entryPath,
          "tone-map value '\(got)' for '\(key)' is not a ToneVariant; expected "
            + ToneVariant.allCases.map { $0.rawValue }.joined(separator: " | "))
      }
    }
    return out
  }

  /// The shared body of the canonical `TonedPill` case and the `Pill`-tagged §16
  /// shorthand — ONE reader, so the two spellings cannot drift apart in what they
  /// accept.
  static func tonedPill(_ path: String, _ f: [String: JSON]) throws -> CellKindErased {
    let field = try reqString(path, f, "field")
    let map = try toneMap(
      "\(path).map", try reqAliased(path, f, toneMapKeys[0], Array(toneMapKeys.dropFirst())))
    // `default` is omitted-when-`.default` (Phase 460); an absent key restores the
    // identity, and an aliased `Neutral` normalises to `.default` — two rules
    // composing, in that order.
    let defaultTone = try optToneDefault(path, f, "default")
    return .tonedPill(field: field, map: map, defaultTone: defaultTone)
  }

  static func cellKindErased(_ path: String, _ j: JSON) throws -> CellKindErased {
    let f = try object(path, j)
    switch try disc(path, f) {
    // Lenient-ingest (WIRE_FORMAT.md §16, Phase 750): "pill" is the WORD for the
    // thing, so a declarative tone rule arrives tagged `Pill` more often than tagged
    // `TonedPill`. Before this phase those keys were accepted and DISCARDED — the
    // author's whole intent gone, silently, with no error to notice. Presence of a
    // tone map is the unambiguous tell: a closure `Pill` carries only
    // `labelFn`/`toneFn` and can never carry one.
    case "Pill" where toneMapKeys.contains(where: { f[$0] != nil }):
      return try tonedPill(path, f)
    case "TonedPill": return try tonedPill(path, f)
    case "Text": return .text
    case "Numeric": return .numeric
    case "Date": return .date
    case "Editable": return .editable
    case "Checkbox": return .checkbox
    case "Button": return .button(label: try reqTextSource(path, f, "label"))
    case "ButtonGroup":
      let labels = try array("\(path).buttons", try req(path, f, "buttons")).enumerated()
        .map { (i, item) -> TextSource in
          let bf = try object("\(path).buttons[\(i)]", item)
          return try reqTextSource("\(path).buttons[\(i)]", bf, "label")
        }
      return .buttonGroup(labels: labels)
    case "Link": return .link
    case "Pill": return .pill
    case "Progress": return .progress
    case "Custom": return .custom
    case let o:
      throw unknownCase(
        path, o,
        "Text | Numeric | Date | Editable | Checkbox | Button | ButtonGroup | Link | Pill | TonedPill | Progress | Custom"
      )
    }
  }

  static func columnErased(_ path: String, _ j: JSON) throws -> ColumnErased {
    let f = try object(path, j)
    // Phase 460 — format/width omitted-when-default. Field aliases: type →
    // kind, header/title → label.
    try refuseNearMiss(
      path, f, [("readOnly", "editable: false (readOnly is its inverse)")])
    return ColumnErased(
      format: try optCellFormatDefault(path, f, "format"),
      kind: try cellKindErased("\(path).kind", try reqAliased(path, f, "kind", ["type"])),
      label: try reqStringAliased(path, f, "label", ["header", "title"]),
      width: try optColumnWidthDefault(path, f, "width"),
      value: optClosure(f, "value"),
      field: try optString(path, f, "field"))
  }

  /// The ENUMERATED near-miss refusal (WIRE_FORMAT 3.2 "Near-miss names are refused,
  /// not ignored").
  ///
  /// Rule 2 tolerates an unknown key, which is right for a field a future profile may
  /// add. It is wrong for a name that is a near miss of one that EXISTS: the tree then
  /// decodes, validates and renders while the declaration does nothing, so the emitter
  /// cannot tell a spelling mistake from a declaration that worked - a fake affordance
  /// arriving through a typo. `schema.json` forbids each with `not: { required: [...] }`,
  /// so the two artefacts agree.
  ///
  /// Refused rather than ALIASED, deliberately: these are not synonyms. `currentPage`
  /// carries a literal page number the vocabulary cannot express at all, and `readOnly`
  /// is the INVERSE of `editable` - an alias that inverts a boolean makes a read-only
  /// column editable when it guesses wrong.
  static func refuseNearMiss(
    _ path: String, _ f: [String: JSON], _ canonical: [(String, String)]
  ) throws {
    for (name, replacement) in canonical where f[name] != nil {
      throw wrongType(
        "\(path).\(name)",
        "the canonical form instead - '\(name)' is a near miss; use \(replacement)")
    }
  }

  /// An integer slot with a schema-pinned lower bound (`minimum`). Below it is WRONG_TYPE.
  static func intAtLeast(_ path: String, _ j: JSON, _ min: Int) throws -> Int {
    let n = try int(path, j)
    if n < min { throw wrongType(path, "an integer >= \(min), got \(n)") }
    return n
  }

  /// An initial sort. Both members are closed: `column` is a zero-based header INDEX
  /// (`minimum: 0`) and `direction` is the `asc | desc` pair, which default-denies.
  static func defaultSort(_ path: String, _ j: JSON) throws -> DefaultSort {
    let f = try object(path, j)
    return DefaultSort(
      column: try intAtLeast("\(path).column", try req(path, f, "column"), 0),
      direction: try bareEnum(
        "\(path).direction", try req(path, f, "direction"), "SortDirection"))
  }

  /// A standalone glyph. `size` and `tone` are omitted-when-default (§3.6), so an absent
  /// slot restores the language default rather than failing.
  static func iconSpec(_ path: String, _ j: JSON) throws -> IconSpec {
    let f = try object(path, j)
    var size: IconSize = .medium
    if let v = f["size"] { size = try bareEnum("\(path).size", v, "IconSize") }
    var tone: ToneVariant = .default
    if let v = f["tone"] { tone = try toneVariant("\(path).tone", v) }
    return IconSpec(
      icon: try reqString(path, f, "icon"), label: try optString(path, f, "label"),
      size: size, tone: tone)
  }

  static func staticRows(_ path: String, _ j: JSON) throws -> StaticRows {
    let f = try object(path, j)
    let headers = try array("\(path).headers", try req(path, f, "headers")).enumerated()
      .map { try textSource("\(path).headers[\($0.0)]", $0.1) }
    let rows = try array("\(path).rows", try req(path, f, "rows")).enumerated()
      .map { (i, rowJ) -> [TextSource] in
        try array("\(path).rows[\(i)]", rowJ).enumerated()
          .map { try textSource("\(path).rows[\(i)][\($0.0)]", $0.1) }
      }
    var sortV: DefaultSort? = nil
    if let v = f["defaultSort"] { sortV = try defaultSort("\(path).defaultSort", v) }
    return StaticRows(
      headers: headers, rows: rows, defaultSort: sortV,
      sortable: try optBool(path, f, "sortable"))
  }

  static func gridSpec(_ path: String, _ j: JSON) throws -> GridSpec {
    let f = try object(path, j)
    let pageCanonical = "pageStateKey (the position lives in State as a {\"page\": N} slot)"
    try refuseNearMiss(
      path, f,
      [
        ("currentPage", pageCanonical),
        ("page", pageCanonical),
        ("pageIndex", pageCanonical),
        (
          "sortable",
          "sortStateKey + a per-column `sortable` (grid-wide `sortable` is the staticRows spelling)"
        ),
        ("onEdit", "editStateKey"),
        ("behaviour", "the sibling behaviour fields; grid behaviour is not a nested record"),
        ("behavior", "the sibling behaviour fields; grid behaviour is not a nested record"),
      ])
    let columns = try array("\(path).columns", try req(path, f, "columns")).enumerated()
      .map { try columnErased("\(path).columns[\($0.0)]", $0.1) }
    var staticRowsV: StaticRows? = nil
    if let v = f["staticRows"] { staticRowsV = try staticRows("\(path).staticRows", v) }
    var gridSortV: DefaultSort? = nil
    if let v = f["defaultSort"] { gridSortV = try defaultSort("\(path).defaultSort", v) }
    var pageSizeV: Int? = nil
    // `minimum: 1` - a page size of zero paginates nothing, so it is malformed rather
    // than a degenerate configuration the renderer should try to honour.
    if let v = f["pageSize"] { pageSizeV = try intAtLeast("\(path).pageSize", v, 1) }
    return GridSpec(
      columns: columns,
      // 0.2.0 — omitted-when-default (false).
      editable: try optBool(path, f, "editable") ?? false,
      // Field aliases: data / rows → source.
      source: try reqBindingAliased(path, f, "source", ["data", "rows"]),
      onRowClick: optClosure(f, "onRowClick"),
      rowKey: optClosure(f, "rowKey"),
      rowKeyField: try optString(path, f, "rowKeyField"),
      staticRows: staticRowsV,
      sortStateKey: try optString(path, f, "sortStateKey"),
      pageStateKey: try optString(path, f, "pageStateKey"),
      editStateKey: try optString(path, f, "editStateKey"),
      pageSize: pageSizeV,
      defaultSort: gridSortV,
      // Phase 1473 — the paginated-media pair, on Box's terms.
      keepRowsTogether: try optBool(path, f, "keepRowsTogether") ?? false,
      repeatHeader: try optBool(path, f, "repeatHeader") ?? false,
      // Phase 1123 — a bool, omitted at `false`, never truthiness-coerced: the
      // slot decides whether a whole affordance exists.
      exportable: try optBool(path, f, "exportable") ?? false,
      // Phase 1125 — separate decoder arms, so a wrong type on either is
      // reported at its own path.
      transferInKey: try optString(path, f, "transferInKey"),
      transferOutKey: try optString(path, f, "transferOutKey"))
  }

  /// `true` when `text` is a canonical ISO-8601 date the temporal axis can
  /// place — `YYYY-MM-DD`, optionally followed by `T…` whose time-of-day is
  /// discarded.
  ///
  /// STRICT by shape AND by calendar: four digits, two, two, both hyphens, a
  /// month in 1–12 and a day the month actually has. A locale spelling
  /// (`15/01/2026`) and an impossible day (`2026-13-05`) are both refused,
  /// because an unreadable date is not a date drawn slightly wrong — it is one
  /// drawn at the epoch, dragging the axis back with it.
  static func isCanonicalIsoDay(_ text: String) -> Bool {
    let u = Array(text.utf8)
    guard u.count >= 10 else { return false }
    if u.count > 10 && u[10] != UInt8(ascii: "T") { return false }
    guard u[4] == UInt8(ascii: "-"), u[7] == UInt8(ascii: "-") else { return false }
    func digits(_ lo: Int, _ hi: Int) -> Int? {
      var n = 0
      for k in lo..<hi {
        let c = u[k]
        guard c >= 48, c <= 57 else { return nil }
        n = n * 10 + Int(c - 48)
      }
      return n
    }
    guard let year = digits(0, 4), let month = digits(5, 7), let day = digits(8, 10) else {
      return false
    }
    guard month >= 1, month <= 12, day >= 1 else { return false }
    let leap = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0
    let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
    return day <= lengths[month - 1]
  }

  /// Phase 1491 (§4l) — an annotation's x address.
  static func chartAnnotationX(_ path: String, _ j: JSON) throws -> ChartAnnotationX {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Category": return .category(key: try reqString(path, f, "key"))
    case "Date":
      let iso = try reqString(path, f, "iso")
      guard isCanonicalIsoDay(iso) else {
        throw wrongType(
          "\(path).iso",
          "a canonical ISO-8601 date (YYYY-MM-DD, optionally followed by a time) naming a real "
            + "calendar day — an event marker's date is the address it is drawn at, and an "
            + "unreadable one would place the marker at 1970-01-01 and drag the axis back with it")
      }
      return .date(iso: iso)
    case let o: throw unknownCase(path, o, "Category, Date")
    }
  }

  /// Phase 1492 (§4l) — a range band's PAIR.
  ///
  /// TWO REFUSALS, and they are the pair rules the WIRE can decide by itself. A
  /// non-finite endpoint is the reference line's narrowing at two slots instead
  /// of one, for its reason exactly: §4l rule 3 has both ends enter the value
  /// domain, so a NaN takes the nice-domain, every gridline and every mark with
  /// it. An UNORDERED pair is refused at the PAIR's own slot — the defect is the
  /// pair's, not either end's — rather than silently swapped, because a band
  /// written backwards is an author's mistake about their own data and swapping
  /// the ends would draw a picture they did not describe.
  ///
  /// A CATEGORY pair's order is NOT decided here: the order of two band keys is
  /// the ROWS' order, a cross-reference rather than a local property of the
  /// address.
  static func chartAnnotationRange(_ path: String, _ j: JSON) throws -> ChartAnnotationRange {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "ValueRange":
      let from = try reqFloat(path, f, "from")
      let to = try reqFloat(path, f, "to")
      for (slot, v) in [("from", from), ("to", to)] where !v.isFinite {
        throw wrongType(
          "\(path).\(slot)",
          "a FINITE JSON number — a range band's end names a place on the value axis, and NaN / "
            + "Infinity names none; give the value in the axis's own units, or drop the annotation")
      }
      if from > to {
        throw wrongType(
          path,
          "an ORDERED pair — a range band runs from its lower value to its upper one, and this "
            + "pair runs backwards; swapping the ends silently would draw a band the author did "
            + "not describe")
      }
      return .valueRange(from: from, to: to)
    case "XRange":
      let from = try chartAnnotationX("\(path).from", try req(path, f, "from"))
      let to = try chartAnnotationX("\(path).to", try req(path, f, "to"))
      // Both dates are already known canonical and calendar-valid (the address
      // decoder refused anything else), and a canonical `YYYY-MM-DD` sorts
      // lexicographically exactly as it sorts chronologically — so no calendar
      // arithmetic is needed here.
      if case .date(let a) = from, case .date(let b) = to, a > b {
        throw wrongType(
          path,
          "an ORDERED pair — a range band runs from its earlier date to its later one, and this "
            + "pair runs backwards; swapping the ends silently would draw a band the author did "
            + "not describe")
      }
      return .xRange(from: from, to: to)
    case let o: throw unknownCase(path, o, "ValueRange, XRange")
    }
  }

  /// Phase 1490 (§4l) — a chart's data-addressed annotation.
  ///
  /// THE REFERENCE LINE'S VALUE MUST BE FINITE, and that is a slot-specific
  /// NARROWING of §7 rather than a disagreement with it. §7 admits the quoted
  /// `"NaN"` / `"Infinity"` / `"-Infinity"` sentinels at every float slot and
  /// the float reader honours them — that widening is deliberate and stays. But
  /// a reference line addresses a place on the VALUE AXIS, and a non-finite
  /// value names no such place: it would enter the domain computation and put
  /// every gridline, tick and mark at a NaN coordinate. The picture is not
  /// merely wrong at the annotation, it is wrong everywhere.
  static func chartAnnotation(_ path: String, _ j: JSON) throws -> ChartAnnotation {
    let f = try object(path, j)
    let label = try optTextSource(path, f, "label")
    switch try disc(path, f) {
    case "ReferenceLine":
      let value = try reqFloat(path, f, "value")
      guard value.isFinite else {
        throw wrongType(
          "\(path).value",
          "a FINITE JSON number — a reference line names a place on the value axis, and NaN / "
            + "Infinity names none; give the value in the axis's own units, or drop the annotation")
      }
      return .referenceLine(value: value, label: label)
    case "EventMarker":
      return .eventMarker(
        at: try chartAnnotationX("\(path).at", try req(path, f, "at")), label: label)
    case "RangeBand":
      return .rangeBand(
        range: try chartAnnotationRange("\(path).range", try req(path, f, "range")), label: label)
    case let o: throw unknownCase(path, o, "ReferenceLine, EventMarker, RangeBand")
    }
  }

  static func chartSpec(_ path: String, _ j: JSON) throws -> ChartSpec {
    let f = try object(path, j)
    let yFields = try array("\(path).yFields", try req(path, f, "yFields")).enumerated()
      .map { try string("\(path).yFields[\($0.0)]", $0.1) }
    var annotationsV: [ChartAnnotation]? = nil
    if let v = f["annotations"] {
      annotationsV = try array("\(path).annotations", v).enumerated()
        .map { try chartAnnotation("\(path).annotations[\($0.0)]", $0.1) }
    }
    return ChartSpec(
      kind: try bareEnum("\(path).kind", try req(path, f, "kind"), "ChartKind"),
      // Field alias: data → source.
      source: try reqBindingAliased(path, f, "source", ["data"]),
      stacked: (try optBool(path, f, "stacked")) ?? false,
      xField: try reqString(path, f, "xField"),
      yFields: yFields,
      title: try optTextSource(path, f, "title"),
      onPointClick: optClosure(f, "onPointClick"),
      annotations: annotationsV)
  }

  static func mapSpec(_ path: String, _ j: JSON) throws -> MapSpec {
    let f = try object(path, j)
    return MapSpec(
      centreLatitude: try reqFloat(path, f, "centreLatitude"),
      centreLongitude: try reqFloat(path, f, "centreLongitude"),
      // Field aliases: data / markers → source.
      source: try reqBindingSlotAliased(path, f, "source", ["data", "markers"], .markers),
      zoom: try reqInt(path, f, "zoom"),
      onMarkerClick: optClosure(f, "onMarkerClick"))
  }

  // ── Layout specs ───────────────────────────────────────────────────────────

  static func children(_ path: String, _ f: [String: JSON], _ walk: WireWalkState) throws -> [Node] {
    try array("\(path).children", try req(path, f, "children")).enumerated()
      .map { try node("\(path).children[\($0.0)]", $0.1, walk) }
  }

  static func boxLayout(_ path: String, _ j: JSON) throws -> BoxLayout {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Flex":
      return .flex(
        direction: try orientation("\(path).direction", try req(path, f, "direction")),
        gap: try optInt(path, f, "gap"), wrap: try reqBool(path, f, "wrap"))
    case "Grid":
      // Field alias: columns → cols. Lenient (§3.6): absent `cols` with no
      // `templateColumns` reads as `Auto`; absent `cols` WITH a template reads
      // `cols: 1` (the template carries the real shape).
      let colsJ = getAliased(f, "cols", ["columns"])
      let templateColumns = try optString(path, f, "templateColumns")
      if colsJ == nil, templateColumns == nil { return .auto }
      let cols: Int
      if let v = colsJ { cols = try int("\(path).cols", v) } else { cols = 1 }
      return .grid(
        cols: cols, gap: try optInt(path, f, "gap"), templateColumns: templateColumns)
    case "Masonry":
      // WIRE_FORMAT §3.6.7 — column-fill. `cols` is REQUIRED and POSITIVE, on
      // the §3.6.4 srcSet width-floor pattern: `column-count: 0` is invalid
      // CSS, so a container declaring it would fall back to whatever the host
      // stylesheet last said and the wire would be carrying a host-defined
      // layout.
      //
      // No auto-column leniency here, unlike `Grid` above, and the asymmetry is
      // deliberate rather than an omission: `Grid` canonicalises a column-less
      // spec to `Auto` because the language already owns that concept, whereas
      // `Auto` is a ROW-fill mode — rewriting a masonry into it would discard
      // the author's intent rather than recover it.
      guard let colsJ = getAliased(f, "cols", ["columns"]) else {
        throw Decode.missing(path, "cols")
      }
      let masonryCols = try int("\(path).cols", colsJ)
      guard masonryCols > 0 else {
        throw Decode.wrongType(
          "\(path).cols", "JSON number (positive integer column count)")
      }
      return .masonry(cols: masonryCols, gap: try optInt(path, f, "gap"))
    case "Auto": return .auto
    case let o: throw unknownCase(path, o, "Flex | Grid | Masonry | Auto")
    }
  }

  static func boxSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> BoxSpec {
    let f = try object(path, j)
    let roleStr = try string("\(path).role", try req(path, f, "role"))
    guard let role = BoxRole(rawValue: roleStr) else {
      throw unknownEnumCase("\(path).role", roleStr, "Group | Card | Dashboard | Separator")
    }
    return BoxSpec(
      children: try children(path, f, walk),
      // Field alias: title → heading (Box is in the scoped set).
      heading: try optTextSourceAliased(path, f, "heading", ["title"]),
      layout: try boxLayout("\(path).layout", try req(path, f, "layout")),
      role: role,
      // Phase 1473 — the print-break pair, omitted at `false` and never
      // truthiness-coerced.
      breakBefore: try optBool(path, f, "breakBefore") ?? false,
      keepTogether: try optBool(path, f, "keepTogether") ?? false)
  }

  static func legacyDashboard(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> BoxSpec {
    let f = try object(path, j)
    // A LEGACY tag carries none of the print-break declarations by construction.
    return BoxSpec(
      children: try children(path, f, walk), heading: nil, layout: .auto, role: .dashboard,
      breakBefore: false, keepTogether: false)
  }

  static func legacyStack(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> BoxSpec {
    let f = try object(path, j)
    let direction: Orientation = try orientation(
      "\(path).orientation", try req(path, f, "orientation"))
    return BoxSpec(
      children: try children(path, f, walk), heading: nil,
      layout: .flex(direction: direction, gap: nil, wrap: try reqBool(path, f, "wrap")),
      role: .group, breakBefore: false, keepTogether: false)
  }

  static func legacyGridLayout(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> BoxSpec {
    let f = try object(path, j)
    return BoxSpec(
      children: try children(path, f, walk), heading: nil,
      layout: .grid(
        cols: try reqInt(path, f, "cols"), gap: nil,
        templateColumns: try optString(path, f, "templateColumns")),
      role: .group, breakBefore: false, keepTogether: false)
  }

  static func legacyCard(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> BoxSpec {
    let f = try object(path, j)
    return BoxSpec(
      children: try children(path, f, walk), heading: try optTextSource(path, f, "heading"),
      layout: .flex(direction: .vertical, gap: nil, wrap: false), role: .card,
      breakBefore: false, keepTogether: false)
  }

  static func splitPanelSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> SplitPanelSpec {
    let f = try object(path, j)
    return SplitPanelSpec(children: try children(path, f, walk), weight: try reqFloat(path, f, "weight"))
  }

  static func tabHeader(_ path: String, _ j: JSON) throws -> TabHeader {
    let f = try object(path, j)
    return TabHeader(
      label: try reqTextSource(path, f, "label"),
      icon: try optString(path, f, "icon"),
      disabled: try optBindingSlot(path, f, "disabled", .bool))
  }

  static func tabsSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> TabsSpec {
    let f = try object(path, j)
    var tabHeaders: [TabHeader]? = nil
    if let v = f["tabHeaders"] {
      tabHeaders = try array("\(path).tabHeaders", v).enumerated()
        .map { try tabHeader("\(path).tabHeaders[\($0.0)]", $0.1) }
    }
    var tabTags: [String]? = nil
    if let v = f["tabTags"] {
      tabTags = try array("\(path).tabTags", v).enumerated()
        .map { try string("\(path).tabTags[\($0.0)]", $0.1) }
    }
    let activeIndex: Binding
    if let v = f["activeIndex"] {
      activeIndex = try bindingSlot("\(path).activeIndex", v, .int)
    } else {
      activeIndex = .staticValue(.ast(.number(0)))
    }
    // 0.2.0 — omitted-when-default (Horizontal), encoder-symmetric.
    let orient: Orientation
    if let v = f["orientation"] {
      orient = try orientation("\(path).orientation", v)
    } else {
      orient = .horizontal
    }
    return TabsSpec(
      children: try children(path, f, walk),
      orientation: orient,
      activeIndex: activeIndex,
      onSelect: optClosure(f, "onSelect"),
      tabHeaders: tabHeaders,
      tabTags: tabTags,
      activeTag: try optBindingSlot(path, f, "activeTag", .str),
      onSelectTag: optClosure(f, "onSelectTag"))
  }

  static func stepperSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> StepperSpec {
    let f = try object(path, j)
    return StepperSpec(
      activeStep: try reqBindingSlot(path, f, "activeStep", .int),
      children: try children(path, f, walk))
  }

  static func summaryListSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> SummaryListSpec {
    let f = try object(path, j)
    return SummaryListSpec(
      children: try children(path, f, walk),
      // Field alias: title → heading.
      heading: try optTextSourceAliased(path, f, "heading", ["title"]))
  }

  static func disclosureSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> DisclosureSpec {
    let f = try object(path, j)
    return DisclosureSpec(
      children: try children(path, f, walk),
      defaultOpen: try reqBool(path, f, "defaultOpen"),
      // Field alias: title → heading.
      heading: try reqTextSourceAliased(path, f, "heading", ["title"]),
      open: try reqBindingSlot(path, f, "open", .bool),
      onToggle: optClosure(f, "onToggle"))
  }

  static func modalSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> ModalSpec {
    let f = try object(path, j)
    var onDismiss: Action? = nil
    if let v = f["onDismiss"] { onDismiss = try action("\(path).onDismiss", v) }
    return ModalSpec(
      children: try children(path, f, walk),
      dismissable: try reqBool(path, f, "dismissable"),
      open: try reqBindingSlot(path, f, "open", .bool),
      onDismiss: onDismiss,
      // Field alias: title → heading.
      heading: try optTextSourceAliased(path, f, "heading", ["title"]),
      // §3.6.11 — omitted at `Modal`, the blocking modality every pre-modality
      // document meant. Neither a non-string nor an unrecognised token falls
      // back: a document asking for a popover and getting a blocking modal has
      // been answered with a different affordance.
      modality: try f["modality"].map {
        try bareEnum("\(path).modality", $0, "ModalityKind")
      } ?? .modal)
  }

  static func scrollAreaSpec(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> ScrollAreaSpec {
    let f = try object(path, j)
    return ScrollAreaSpec(
      children: try children(path, f, walk),
      orientation: try bareEnum(
        "\(path).orientation", try req(path, f, "orientation"), "ScrollOrientation"),
      maxHeight: try optInt(path, f, "maxHeight"),
      maxWidth: try optInt(path, f, "maxWidth"))
  }

  // ── Structural ─────────────────────────────────────────────────────────────

  static func contentHash(_ path: String, _ j: JSON) throws -> ContentHash {
    let f = try object(path, j)
    let strictnessStr = try reqString(path, f, "strictness")
    guard let strictness = HashStrictness(rawValue: strictnessStr) else {
      throw unknownEnumCase(
        "\(path).strictness", strictnessStr, "StrictReplay | AdvisoryWarning | Enforced")
    }
    return ContentHash(
      algorithm: try reqString(path, f, "algorithm"), hash: try reqString(path, f, "hash"),
      strictness: strictness)
  }

  static func holeValueSpace(_ path: String, _ j: JSON) throws -> HoleValueSpace {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "IntRange":
      return .intRange(min: try reqInt(path, f, "min"), max: try reqInt(path, f, "max"))
    case "FloatRange":
      return .floatRange(min: try reqFloat(path, f, "min"), max: try reqFloat(path, f, "max"))
    case "StringLen":
      return .stringLen(
        minLen: try reqInt(path, f, "minLen"), maxLen: try reqInt(path, f, "maxLen"))
    case "Enum":
      let choices = try array("\(path).choices", try req(path, f, "choices")).enumerated()
        .map { try string("\(path).choices[\($0.0)]", $0.1) }
      return .enumChoices(choices: choices)
    case "AnyString": return .anyString
    case let o:
      throw unknownCase(path, o, "IntRange | FloatRange | StringLen | Enum | AnyString")
    }
  }

  static func fragmentScalar(_ path: String, _ j: JSON) throws -> FragmentScalar {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Int": return .int(try reqInt(path, f, "value"))
    case "Float": return .float(try reqFloat(path, f, "value"))
    case "Bool": return .bool(try reqBool(path, f, "value"))
    case "Str": return .str(try reqString(path, f, "value"))
    case let o: throw unknownCase(path, o, "Int | Float | Bool | Str")
    }
  }

  static func holeDecl(_ path: String, _ j: JSON) throws -> HoleDecl {
    let f = try object(path, j)
    switch try disc(path, f) {
    case "Value":
      var def: FragmentScalar? = nil
      if let v = f["default"] { def = try fragmentScalar("\(path).default", v) }
      return .value(
        name: try reqString(path, f, "name"),
        space: try holeValueSpace("\(path).space", try req(path, f, "space")),
        default: def)
    case "Slot":
      return .slot(
        name: try reqString(path, f, "name"),
        kindConstraint: try optString(path, f, "kindConstraint"))
    case "Repeat":
      return .repeatHole(
        name: try reqString(path, f, "name"),
        countSpace: try holeValueSpace("\(path).countSpace", try req(path, f, "countSpace")))
    case let o: throw unknownCase(path, o, "Value | Slot | Repeat")
    }
  }

  static func effectClass(_ path: String, _ j: JSON) throws -> EffectClass {
    let f = try object(path, j)
    let hostStr = try reqString(path, f, "hostEffect")
    guard let host = HostEffect(rawValue: hostStr) else {
      throw unknownEnumCase("\(path).hostEffect", hostStr, "Pure | ReadsHost | WritesHost")
    }
    let detStr = try reqString(path, f, "determinism")
    guard let det = DeterminismSource(rawValue: detStr) else {
      throw unknownEnumCase(
        "\(path).determinism", detStr, "Deterministic | Clock | Random | Network")
    }
    return EffectClass(hostEffect: host, determinism: det)
  }

  static func fragmentArg(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> FragmentArg {
    let f = try object(path, j)
    if try disc(path, f) == "SlotArg" {
      return .slot(tree: try node("\(path).tree", try req(path, f, "tree"), walk))
    }
    return .value(try fragmentScalar(path, j))
  }

  static func fragmentArgs(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> [FragmentArgEntry] {
    let f = try object(path, j)
    // Sorted by name — see the `I18n.args` arm and `jvalMap`: dictionary iteration
    // order is not a property of the document, and this slot (`FragmentRef.args`,
    // `Mount.inputs`) decoded in a different order, and refused at a different
    // entry when two were invalid, on every call before it was sorted.
    return try f.sorted(by: { $0.key < $1.key }).map {
      FragmentArgEntry(name: $0.key, arg: try fragmentArg("\(path).\($0.key)", $0.value, walk))
    }
  }

  // ── NodeKind dispatch ──────────────────────────────────────────────────────

  static func nodeKind(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> NodeKind {
    let f = try object(path, j)
    switch try disc(path, f) {
    // Layout (+ the four legacy decode-upgrade tags).
    case "Box": return .box(try boxSpec(path, j, walk))
    case "Dashboard": return .box(try legacyDashboard(path, j, walk))
    case "Stack": return .box(try legacyStack(path, j, walk))
    case "GridLayout": return .box(try legacyGridLayout(path, j, walk))
    case "Card": return .box(try legacyCard(path, j, walk))
    case "SplitPanel": return .splitPanel(try splitPanelSpec(path, j, walk))
    case "Tabs": return .tabs(try tabsSpec(path, j, walk))
    case "Stepper": return .stepper(try stepperSpec(path, j, walk))
    case "SummaryList": return .summaryList(try summaryListSpec(path, j, walk))
    case "Disclosure": return .disclosure(try disclosureSpec(path, j, walk))
    case "Modal": return .modal(try modalSpec(path, j, walk))
    case "ScrollArea": return .scrollArea(try scrollAreaSpec(path, j, walk))
    // Display.
    case "Heading": return .heading(try headingSpec(path, j))
    case "Markdown": return .markdown(try markdownSpec(path, j))
    case "Metric": return .metric(try metricSpec(path, j))
    case "Badge": return .badge(try badgeSpec(path, j))
    case "Sparkline": return .sparkline(try sparklineSpec(path, j))
    case "Callout": return .callout(try calloutSpec(path, j))
    case "Progress": return .progress(try progressSpec(path, j))
    case "Skeleton": return .skeleton(try skeletonSpec(path, j))
    case "Fact": return .fact(try factSpec(path, j))
    case "LabelValueRow": return .labelValueRow(try labelValueRowSpec(path, j))
    case "Icon": return .icon(try iconSpec(path, j))
    case "Link": return .link(try linkSpec(path, j))
    case "Image": return .image(try imageSpec(path, j))
    case "Media": return .media(try mediaSpec(path, j))
    case "Embed": return .embed(try embedSpec(path, j))
    case "Tree": return .tree(try treeSpec(path, j, walk))
    case "List": return .list(try listSpec(path, j))
    case "Toast": return .toast(try toastSpec(path, j))
    case "CodeBlock": return .codeBlock(try codeBlockSpec(path, j))
    case "Math": return .math(try mathSpec(path, j))
    case "Drawing": return .drawing(try drawingSpec(path, j))
    // Input.
    case "Form": return .form(try formSpec(path, j))
    case "Filters":
      let specs = try array("\(path).items", try req(path, f, "items")).enumerated()
        .map { try filterSpec("\(path).items[\($0.0)]", $0.1) }
      return .filters(specs)
    case "Button": return .button(try buttonSpec(path, j))
    case "FileUpload": return .fileUpload(try fileUploadSpec(path, j))
    case "Select": return .select(try selectSpec(path, j))
    // Visualisation.
    case "DataGrid": return .dataGrid(try gridSpec(path, j))
    case "Chart": return .chart(try chartSpec(path, j))
    case "Table":
      // Legacy: a `Table` tag folds into a read-only static-rows grid.
      let rows = try staticRows(path, j)
      return .dataGrid(
        GridSpec(
          columns: [], editable: false, source: .staticValue(.ast(.string(OPAQUE))),
          onRowClick: nil, rowKey: nil, rowKeyField: nil, staticRows: rows,
          sortStateKey: nil, pageStateKey: nil, editStateKey: nil, pageSize: nil,
          defaultSort: nil, keepRowsTogether: false, repeatHeader: false, exportable: false,
          transferInKey: nil, transferOutKey: nil))
    case "Map": return .map(try mapSpec(path, j))
    // Structural.
    case "Custom":
      var contentHashV: ContentHash? = nil
      if let v = f["contentHash"] { contentHashV = try contentHash("\(path).contentHash", v) }
      var exposed: [String] = []
      if let v = f["exposedNodeIds"] {
        exposed = try array("\(path).exposedNodeIds", v).enumerated()
          .map { try string("\(path).exposedNodeIds[\($0.0)]", $0.1) }
      }
      return .custom(
        CustomSpec(
          moduleId: try reqString(path, f, "moduleId"),
          componentId: try reqString(path, f, "componentId"),
          props: try jvalMap("\(path).props", try req(path, f, "props")),
          contentHash: contentHashV,
          exposedNodeIds: exposed))
    case "ErrorBoundary":
      return .errorBoundary(
        ErrorBoundarySpec(
          child: try node("\(path).child", try req(path, f, "child"), walk),
          fallback: try node("\(path).fallback", try req(path, f, "fallback"), walk)))
    case "Switch":
      let cases = try array("\(path).cases", try req(path, f, "cases")).enumerated()
        .map { (i, item) -> SwitchCase in
          let cp = "\(path).cases[\(i)]"
          let cf = try object(cp, item)
          // Phase 1535 — EXACTLY ONE of `match` and `when`. "Both" is refused
          // rather than resolved by precedence (a precedence rule would have to
          // be specified, agreed on every host and remembered by every author,
          // for a document nobody meant to write); "neither" keeps the pre-1535
          // MISSING_FIELD at `.match`, which is what the corpus pins — a case
          // naming no condition is not one that never matches, and skipping it
          // silently is the class of silence the predicate form was added to
          // remove.
          let condition: SwitchCondition
          if cf["match"] != nil && cf["when"] != nil {
            throw wrongType(
              "\(cp).when",
              "exactly one of 'match' and 'when' — a precedence rule between them would have to "
                + "be agreed on every host for a document nobody meant to write")
          } else if let w = cf["when"] {
            condition = .when(try bindingSlot("\(cp).when", w, .bool))
          } else {
            condition = .match(try reqString(cp, cf, "match"))
          }
          return SwitchCase(
            condition: condition,
            child: try node("\(cp).child", try req(cp, cf, "child"), walk))
        }
      // The selector widened: `on` takes any Binding (a `Selection` makes the branch
      // follow the clicked row), so `stateKey` is no longer required on its own. The
      // schema states it as `anyOf: [required stateKey, required on]` - at least one, and
      // the refusal below is what makes a Switch carrying NEITHER a decode error rather
      // than a node that silently always renders its default.
      let switchKey = try optString(path, f, "stateKey")
      var switchOn: Binding? = nil
      if let v = f["on"] { switchOn = try binding("\(path).on", v) }
      if switchKey == nil && switchOn == nil { throw missing(path, "stateKey") }
      // Phase 1122 — a POSITIVE INTEGER count of milliseconds. Non-positive is
      // refused rather than canonicalised: `0` is what an emitter reaches for
      // to mean "off" and absence is already that spelling, so rewriting it
      // would make two document shapes mean one thing and tell the emitter
      // nothing about its misreading. Fractional is refused separately — the
      // slot is an integer count, and a decoder truncating where another
      // rounded would leave two hosts disagreeing about a document neither
      // refused. Both fall out of the strict integer reader plus the bound.
      var advanceV: Int? = nil
      if let v = f["autoAdvanceMs"] {
        let ms = try int("\(path).autoAdvanceMs", v)
        if ms < 1 {
          throw wrongType(
            "\(path).autoAdvanceMs",
            "a positive millisecond interval — an absent key is already the spelling for off")
        }
        advanceV = ms
      }
      return .switchKind(
        SwitchSpec(
          stateKey: switchKey,
          cases: cases,
          defaultChild: try node("\(path).default", try req(path, f, "default"), walk),
          on: switchOn,
          autoAdvanceMs: advanceV))
    case "FragmentDecl":
      var holes: [HoleDecl] = []
      if let v = f["holes"] {
        holes = try array("\(path).holes", v).enumerated()
          .map { try holeDecl("\(path).holes[\($0.0)]", $0.1) }
      }
      let effect: EffectClass =
        try f["effect"].map { try effectClass("\(path).effect", $0) } ?? .pureDeterministic
      return .fragmentDecl(
        FragmentDeclSpec(
          name: try reqString(path, f, "name"),
          body: try node("\(path).body", try req(path, f, "body"), walk),
          holes: holes, effect: effect))
    case "FragmentRef":
      let args: [FragmentArgEntry] =
        try f["args"].map { try fragmentArgs("\(path).args", $0, walk) } ?? []
      return .fragmentRef(FragmentRefSpec(name: try reqString(path, f, "name"), args: args))
    case "Mount":
      let channelObj = try object("\(path).channel", try req(path, f, "channel"))
      let dirStr = try reqString("\(path).channel", channelObj, "direction")
      guard let direction = ChannelDirection(rawValue: dirStr) else {
        throw unknownEnumCase("\(path).channel.direction", dirStr, "OutOnly | TwoWay")
      }
      let caps = try array("\(path).capabilities", try req(path, f, "capabilities")).enumerated()
        .map { try string("\(path).capabilities[\($0.0)]", $0.1) }
      let inputs: [FragmentArgEntry] =
        try f["inputs"].map { try fragmentArgs("\(path).inputs", $0, walk) } ?? []
      return .mount(
        MountSpec(
          scopeId: try reqString(path, f, "scopeId"),
          inputs: inputs,
          channel: MountChannel(
            direction: direction,
            messageShape: try optString("\(path).channel", channelObj, "messageShape")),
          capabilities: caps))
    case let o:
      throw err(.wrongNodeKind, "\(path).$type", "unknown NodeKind discriminator '\(o)'")
    }
  }

  // ── Node envelope ──────────────────────────────────────────────────────────

  static func stateBehaviour(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> StateBehaviour {
    let f = try object(path, j)
    var onLoading: NodeRef? = nil
    if let v = f["onLoading"] { onLoading = NodeRef(try node("\(path).onLoading", v, walk)) }
    var onEmpty: NodeRef? = nil
    if let v = f["onEmpty"] { onEmpty = NodeRef(try node("\(path).onEmpty", v, walk)) }
    return StateBehaviour(onLoading: onLoading, onEmpty: onEmpty, onError: optClosure(f, "onError"))
  }

  static func semanticStyle(_ path: String, _ j: JSON) throws -> SemanticStyle {
    let f = try object(path, j)
    let role: StyleRole =
      try f["role"].map { try bareEnum("\(path).role", $0, "StyleRole") } ?? .none
    let voice: FontVoice =
      try f["voice"].map { try bareEnum("\(path).voice", $0, "FontVoice") } ?? .default
    // Phase 460 — tone/weight/emphasis omitted-when-default (as role/voice).
    // Phase 1472 — omitted at `auto`, the inherited direction. Neither a
    // non-string nor an unrecognised token falls back to `auto`: a document
    // declaring a direction the host cannot read must not be rendered in the
    // opposite one in silence.
    let direction: TextDirection =
      try f["direction"].map { try bareEnum("\(path).direction", $0, "TextDirection") } ?? .auto
    return SemanticStyle(
      emphasis: try optEmphasisDefault(path, f, "emphasis"),
      tone: try optToneDefault(path, f, "tone"),
      weight: try optWeightDefault(path, f, "weight"),
      role: role, voice: voice, direction: direction)
  }

  /// The `Accessibility` trait's near-miss set (WIRE_FORMAT 3.1 "Near-miss slot names
  /// are refused, not ignored") — the 3.2 grid narrowing at the position where its cost
  /// is highest.
  ///
  /// This trait has NO VISIBLE OUTPUT. A mislabelled column is on screen; an ignored
  /// `ariaLabel` looks identical to an honoured one from every side, so the refusal is
  /// the only feedback that can ever arrive.
  ///
  /// Refused rather than ALIASED, and note the argument differs from the grid's. There
  /// the names were not synonyms; here `ariaLabel` IS one, so admission turns on the
  /// other half of the lenient profile's rule - a shorthand earns its place by being a
  /// genuine assist to the emitting model, and a six-character key rename is not one.
  /// `live` settles it: the HTML idiom it comes from also spells a BOOLEAN, so an alias
  /// would bind a possibly-boolean prior onto a closed three-token set.
  ///
  /// Three families, grouped by the slot each points at: the ARIA attribute name, its
  /// camelCase spelling, and the un-prefixed or un-cased slot name. Declaration order is
  /// identical in every host, so which defect surfaces first is deterministic.
  static let accessibilityNearMisses: [(String, String)] = [
    ("aria-label", "label"),
    ("ariaLabel", "label"),
    ("aria-labelledby", "labelledBy"),
    ("ariaLabelledBy", "labelledBy"),
    ("labelledby", "labelledBy"),
    ("aria-describedby", "describedBy"),
    ("ariaDescribedBy", "describedBy"),
    ("describedby", "describedBy"),
    ("aria-role", "role"),
    ("ariaRole", "role"),
    ("aria-live", "liveRegion"),
    ("ariaLive", "liveRegion"),
    ("live", "liveRegion"),
    ("liveregion", "liveRegion"),
    ("aria-hidden", "hidden"),
    ("ariaHidden", "hidden"),
  ]

  static func accessibility(_ path: String, _ j: JSON) throws -> Accessibility {
    let f = try object(path, j)
    // The near-miss check runs BEFORE the slot reads, matching the FormField
    // ordering, so a trait carrying both `ariaLabel` and a well-formed `label`
    // still names the ignored key rather than decoding half the intent silently.
    try refuseNearMiss(path, f, accessibilityNearMisses)
    let liveRegion: LiveRegionKind? =
      try f["liveRegion"].map { try bareEnum("\(path).liveRegion", $0, "LiveRegionKind") }
    return Accessibility(
      label: try optBindingSlot(path, f, "label", .str),
      labelledBy: try optString(path, f, "labelledBy"),
      describedBy: try optString(path, f, "describedBy"),
      role: try optString(path, f, "role"),
      liveRegion: liveRegion,
      hidden: try optBindingSlot(path, f, "hidden", .bool))
  }

  /// The single funnel for NODE recursion — every child, every nested slot and the root
  /// all arrive here, which is what makes one `enterNode` call bound the whole node axis.
  /// The counter is entered BEFORE the shape check below, so a document past the limit is
  /// refused for being too deep rather than for whatever the over-deep value happens to
  /// look like.
  static func node(_ path: String, _ j: JSON, _ walk: WireWalkState) throws -> Node {
    try walk.enterNode(path)
    defer { walk.exitNode() }
    let f = try object(path, j)
    let id = try string("\(path).id", try req(path, f, "id"))
    if id.isEmpty {
      throw err(.emptyNodeId, "\(path).id", "Node id is empty")
    }
    let kind = try nodeKind("\(path).kind", try req(path, f, "kind"), walk)
    let state: StateBehaviour =
      try f["state"].map { try stateBehaviour("\(path).state", $0, walk) } ?? .empty
    let style: SemanticStyle =
      try f["style"].map { try semanticStyle("\(path).style", $0) } ?? .default
    let accessibilityV: Accessibility? =
      try f["accessibility"].map { try accessibility("\(path).accessibility", $0) }
    // §3.1 (Phase 1112) — the tooltip trait, on the ENVELOPE beside
    // `accessibility` rather than inside any `kind`. A `TextSource`, so the
    // bare-string shorthand and the `I18n` form both land, and a non-text value
    // is `WRONG_TYPE` at `$.tooltip` (`reject-tooltip-nonstring`). Until this
    // change the slot was an unknown key: rule 2 tolerated it, three node
    // fixtures round-tripped with the hint silently on the floor, and the reject
    // vector decoded — the quiet half of the same defect.
    let tooltipV: TextSource? = try optTextSource(path, f, "tooltip")
    return Node(
      id: id, kind: kind, state: state, style: style, accessibility: accessibilityV,
      tooltip: tooltipV)
  }
}
