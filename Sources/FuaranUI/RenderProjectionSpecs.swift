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
      value: try reqBindingAliased(path, f, "value", ["data"]),
      // Phase 460 — the stylistic fields are omitted-when-default on the wire.
      format: try optCellFormatDefault(path, f, "format"),
      tone: try optToneDefault(path, f, "tone"),
      weight: try optWeightDefault(path, f, "weight"),
      emphasis: try optEmphasisDefault(path, f, "emphasis"),
      trend: try optBinding(path, f, "trend"),
      trendFormat: trendFormat,
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
    if let v = f["emphasis"] { emphasis = try emphasisFlag("\(path).emphasis", v) } else {
      emphasis = false
    }
    return LabelValueRowSpec(
      label: try reqTextSource(path, f, "label"),
      // 0.2.0 rename law — scalar displayed value ⇒ `value` (`data` alias kept).
      value: try reqBindingAliased(path, f, "value", ["data"]),
      format: try optCellFormatDefault(path, f, "format"),
      emphasis: emphasis,
      help: try optTextSource(path, f, "help"))
  }

  static func factSpec(_ path: String, _ j: JSON) throws -> FactSpec {
    let f = try object(path, j)
    let emphasis: Bool
    if let v = f["emphasis"] { emphasis = try emphasisFlag("\(path).emphasis", v) } else {
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
    return LinkSpec(
      href: try reqBinding(path, f, "href"),
      label: try reqTextSource(path, f, "label"),
      download: try reqBool(path, f, "download"),
      rel: try optString(path, f, "rel"),
      target: try optString(path, f, "target"))
  }

  static func imageSpec(_ path: String, _ j: JSON) throws -> ImageSpec {
    let f = try object(path, j)
    return ImageSpec(
      alt: try reqTextSource(path, f, "alt"),
      src: try reqBinding(path, f, "src"),
      variant: try bareEnum("\(path).variant", try req(path, f, "variant"), "ImageVariant"))
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
      open: try reqBinding(path, f, "open"),
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
      fraction: try reqBinding(path, f, "fraction"),
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
      fill: try optBinding(path, f, "fill"),
      stroke: try optBinding(path, f, "stroke"),
      strokeWidth: try optBinding(path, f, "strokeWidth"),
      opacity: try optBinding(path, f, "opacity"),
      textAnchor: textAnchor,
      fontSize: try optFloat(path, f, "fontSize"),
      emphasis: emphasis,
      fontFamily: try optString(path, f, "fontFamily"),
      // Phase 642 — keyed mark identity; omitted-when-None.
      markId: try optString(path, f, "markId"))
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
      return .text(value: try valueOr(.untyped, ControlValueDefaults.text), onChange: onChange)
    case "Number":
      return .number(value: try valueOr(.untyped, ControlValueDefaults.number), onChange: onChange)
    case "Checkbox":
      return .checkbox(
        value: try valueOr(.untyped, ControlValueDefaults.checkbox), onToggle: onToggle)
    case "Choice":
      return .choice(
        options: try reqBindingSlot(path, f, "options", .options),
        value: try valueOr(.stringOpt, ControlValueDefaults.choice), onChange: onChange)
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
        value: try valueOr(.untyped, ControlValueDefaults.number),
        min: try optFloat(path, f, "min"),
        max: try optFloat(path, f, "max"), step: try optFloat(path, f, "step"),
        onChange: onChange)
    case "SegmentedChoice":
      // Lenient omitted-when-default (§3.6): absent restores the language
      // default `Horizontal` (decode-optional).
      let orient: Orientation
      if let v = f["orientation"] { orient = try orientation("\(path).orientation", v) } else {
        orient = .horizontal
      }
      return .segmentedChoice(
        options: try reqBindingSlot(path, f, "options", .options),
        orientation: orient,
        value: try valueOr(.stringOpt, ControlValueDefaults.choice), onChange: onChange)
    case "TextArea":
      return .textArea(
        rows: try reqInt(path, f, "rows"),
        value: try valueOr(.untyped, ControlValueDefaults.text),
        onChange: onChange)
    case "Date":
      return .date(
        value: try valueOr(.untyped, ControlValueDefaults.date),
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
    case let o:
      throw unknownCase(
        path, o,
        "Text | Number | Checkbox | Choice | Range | RangedNumber | SegmentedChoice | TextArea "
          + "| Date | DateRange"
      )
    }
  }

  static func formField(_ path: String, _ j: JSON) throws -> FormField {
    let f = try object(path, j)
    // Field alias: name → id. Id decodes first so the form context's auto-bind
    // can use it (Phase 596).
    let id = try reqStringAliased(path, f, "id", ["name"])
    return FormField(
      id: id,
      kind: try formFieldKind(.formFieldId(id), "\(path).kind", try req(path, f, "kind")),
      label: try reqTextSource(path, f, "label"),
      required: try reqBool(path, f, "required"),
      help: try optTextSource(path, f, "help"))
  }

  static func formSpec(_ path: String, _ j: JSON) throws -> FormSpec {
    let f = try object(path, j)
    let fields = try array("\(path).fields", try req(path, f, "fields")).enumerated()
      .map { try formField("\(path).fields[\($0.0)]", $0.1) }
    return FormSpec(
      fields: fields,
      onSubmit: try reqAction(path, f, "onSubmit"),
      submitLabel: try reqTextSource(path, f, "submitLabel"),
      disabled: try optBinding(path, f, "disabled"))
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
      disabled: try optBinding(path, f, "disabled"))
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
      disabled: try optBinding(path, f, "disabled"),
      multiple: (try optBool(path, f, "multiple")) == true,
      values: values,
      onChangeMulti: optClosure(f, "onChangeMulti"))
  }

  static func fileUploadSpec(_ path: String, _ j: JSON) throws -> FileUploadSpec {
    let f = try object(path, j)
    let accept = try array("\(path).accept", try req(path, f, "accept")).enumerated()
      .map { try string("\(path).accept[\($0.0)]", $0.1) }
    return FileUploadSpec(
      accept: accept,
      label: try reqTextSource(path, f, "label"),
      multiple: try reqBool(path, f, "multiple"),
      disabled: try optBinding(path, f, "disabled"))
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
  /// The refusal is RE-ISSUED rather than passed through. `unknownCase` reports at
  /// `<path>.$type` with "unknown discriminator", and a map value is neither a
  /// discriminator nor at a `$type` key — so the raw error names a path the document
  /// does not contain, which is actively misleading. The re-issue keeps the code and
  /// the seven legal names and points at the offending KEY, because "one of your
  /// tones is wrong" is not an actionable report when the map has nine entries. A
  /// non-string value is a `wrongType` and already reports at the right path, so it
  /// passes through untouched.
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
    return ColumnErased(
      format: try optCellFormatDefault(path, f, "format"),
      kind: try cellKindErased("\(path).kind", try reqAliased(path, f, "kind", ["type"])),
      label: try reqStringAliased(path, f, "label", ["header", "title"]),
      width: try optColumnWidthDefault(path, f, "width"),
      value: optClosure(f, "value"),
      field: try optString(path, f, "field"))
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
    return StaticRows(headers: headers, rows: rows)
  }

  static func gridSpec(_ path: String, _ j: JSON) throws -> GridSpec {
    let f = try object(path, j)
    let columns = try array("\(path).columns", try req(path, f, "columns")).enumerated()
      .map { try columnErased("\(path).columns[\($0.0)]", $0.1) }
    var staticRowsV: StaticRows? = nil
    if let v = f["staticRows"] { staticRowsV = try staticRows("\(path).staticRows", v) }
    return GridSpec(
      columns: columns,
      // 0.2.0 — omitted-when-default (false).
      editable: try optBool(path, f, "editable") ?? false,
      // Field aliases: data / rows → source.
      source: try reqBindingAliased(path, f, "source", ["data", "rows"]),
      onRowClick: optClosure(f, "onRowClick"),
      rowKey: optClosure(f, "rowKey"),
      rowKeyField: try optString(path, f, "rowKeyField"),
      staticRows: staticRowsV)
  }

  static func chartSpec(_ path: String, _ j: JSON) throws -> ChartSpec {
    let f = try object(path, j)
    let yFields = try array("\(path).yFields", try req(path, f, "yFields")).enumerated()
      .map { try string("\(path).yFields[\($0.0)]", $0.1) }
    return ChartSpec(
      kind: try bareEnum("\(path).kind", try req(path, f, "kind"), "ChartKind"),
      // Field alias: data → source.
      source: try reqBindingAliased(path, f, "source", ["data"]),
      stacked: (try optBool(path, f, "stacked")) ?? false,
      xField: try reqString(path, f, "xField"),
      yFields: yFields,
      title: try optTextSource(path, f, "title"),
      onPointClick: optClosure(f, "onPointClick"))
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

  static func children(_ path: String, _ f: [String: JSON]) throws -> [Node] {
    try array("\(path).children", try req(path, f, "children")).enumerated()
      .map { try node("\(path).children[\($0.0)]", $0.1) }
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
    case "Auto": return .auto
    case let o: throw unknownCase(path, o, "Flex | Grid | Auto")
    }
  }

  static func boxSpec(_ path: String, _ j: JSON) throws -> BoxSpec {
    let f = try object(path, j)
    let roleStr = try string("\(path).role", try req(path, f, "role"))
    guard let role = BoxRole(rawValue: roleStr) else {
      throw unknownCase("\(path).role", roleStr, "Group | Card | Dashboard | Separator")
    }
    return BoxSpec(
      children: try children(path, f),
      // Field alias: title → heading (Box is in the scoped set).
      heading: try optTextSourceAliased(path, f, "heading", ["title"]),
      layout: try boxLayout("\(path).layout", try req(path, f, "layout")),
      role: role)
  }

  static func legacyDashboard(_ path: String, _ j: JSON) throws -> BoxSpec {
    let f = try object(path, j)
    return BoxSpec(children: try children(path, f), heading: nil, layout: .auto, role: .dashboard)
  }

  static func legacyStack(_ path: String, _ j: JSON) throws -> BoxSpec {
    let f = try object(path, j)
    let direction: Orientation = try orientation(
      "\(path).orientation", try req(path, f, "orientation"))
    return BoxSpec(
      children: try children(path, f), heading: nil,
      layout: .flex(direction: direction, gap: nil, wrap: try reqBool(path, f, "wrap")),
      role: .group)
  }

  static func legacyGridLayout(_ path: String, _ j: JSON) throws -> BoxSpec {
    let f = try object(path, j)
    return BoxSpec(
      children: try children(path, f), heading: nil,
      layout: .grid(
        cols: try reqInt(path, f, "cols"), gap: nil,
        templateColumns: try optString(path, f, "templateColumns")),
      role: .group)
  }

  static func legacyCard(_ path: String, _ j: JSON) throws -> BoxSpec {
    let f = try object(path, j)
    return BoxSpec(
      children: try children(path, f), heading: try optTextSource(path, f, "heading"),
      layout: .flex(direction: .vertical, gap: nil, wrap: false), role: .card)
  }

  static func splitPanelSpec(_ path: String, _ j: JSON) throws -> SplitPanelSpec {
    let f = try object(path, j)
    return SplitPanelSpec(children: try children(path, f), weight: try reqFloat(path, f, "weight"))
  }

  static func tabHeader(_ path: String, _ j: JSON) throws -> TabHeader {
    let f = try object(path, j)
    return TabHeader(
      label: try reqTextSource(path, f, "label"),
      icon: try optString(path, f, "icon"),
      disabled: try optBinding(path, f, "disabled"))
  }

  static func tabsSpec(_ path: String, _ j: JSON) throws -> TabsSpec {
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
      activeIndex = try binding("\(path).activeIndex", v)
    } else {
      activeIndex = .staticValue(.ast(.number(0)))
    }
    // 0.2.0 — omitted-when-default (Horizontal), encoder-symmetric.
    let orient: Orientation
    if let v = f["orientation"] { orient = try orientation("\(path).orientation", v) } else {
      orient = .horizontal
    }
    return TabsSpec(
      children: try children(path, f),
      orientation: orient,
      activeIndex: activeIndex,
      onSelect: optClosure(f, "onSelect"),
      tabHeaders: tabHeaders,
      tabTags: tabTags,
      activeTag: try optBinding(path, f, "activeTag"),
      onSelectTag: optClosure(f, "onSelectTag"))
  }

  static func stepperSpec(_ path: String, _ j: JSON) throws -> StepperSpec {
    let f = try object(path, j)
    return StepperSpec(
      activeStep: try reqBinding(path, f, "activeStep"), children: try children(path, f))
  }

  static func summaryListSpec(_ path: String, _ j: JSON) throws -> SummaryListSpec {
    let f = try object(path, j)
    return SummaryListSpec(
      children: try children(path, f),
      // Field alias: title → heading.
      heading: try optTextSourceAliased(path, f, "heading", ["title"]))
  }

  static func disclosureSpec(_ path: String, _ j: JSON) throws -> DisclosureSpec {
    let f = try object(path, j)
    return DisclosureSpec(
      children: try children(path, f),
      defaultOpen: try reqBool(path, f, "defaultOpen"),
      // Field alias: title → heading.
      heading: try reqTextSourceAliased(path, f, "heading", ["title"]),
      open: try reqBinding(path, f, "open"),
      onToggle: optClosure(f, "onToggle"))
  }

  static func modalSpec(_ path: String, _ j: JSON) throws -> ModalSpec {
    let f = try object(path, j)
    var onDismiss: Action? = nil
    if let v = f["onDismiss"] { onDismiss = try action("\(path).onDismiss", v) }
    return ModalSpec(
      children: try children(path, f),
      dismissable: try reqBool(path, f, "dismissable"),
      open: try reqBinding(path, f, "open"),
      onDismiss: onDismiss,
      // Field alias: title → heading.
      heading: try optTextSourceAliased(path, f, "heading", ["title"]))
  }

  static func scrollAreaSpec(_ path: String, _ j: JSON) throws -> ScrollAreaSpec {
    let f = try object(path, j)
    return ScrollAreaSpec(
      children: try children(path, f),
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
      throw unknownCase(
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
      throw unknownCase("\(path).hostEffect", hostStr, "Pure | ReadsHost | WritesHost")
    }
    let detStr = try reqString(path, f, "determinism")
    guard let det = DeterminismSource(rawValue: detStr) else {
      throw unknownCase(
        "\(path).determinism", detStr, "Deterministic | Clock | Random | Network")
    }
    return EffectClass(hostEffect: host, determinism: det)
  }

  static func fragmentArg(_ path: String, _ j: JSON) throws -> FragmentArg {
    let f = try object(path, j)
    if try disc(path, f) == "SlotArg" {
      return .slot(tree: try node("\(path).tree", try req(path, f, "tree")))
    }
    return .value(try fragmentScalar(path, j))
  }

  static func fragmentArgs(_ path: String, _ j: JSON) throws -> [FragmentArgEntry] {
    let f = try object(path, j)
    return try f.map {
      FragmentArgEntry(name: $0.key, arg: try fragmentArg("\(path).\($0.key)", $0.value))
    }
  }

  // ── NodeKind dispatch ──────────────────────────────────────────────────────

  static func nodeKind(_ path: String, _ j: JSON) throws -> NodeKind {
    let f = try object(path, j)
    switch try disc(path, f) {
    // Layout (+ the four legacy decode-upgrade tags).
    case "Box": return .box(try boxSpec(path, j))
    case "Dashboard": return .box(try legacyDashboard(path, j))
    case "Stack": return .box(try legacyStack(path, j))
    case "GridLayout": return .box(try legacyGridLayout(path, j))
    case "Card": return .box(try legacyCard(path, j))
    case "SplitPanel": return .splitPanel(try splitPanelSpec(path, j))
    case "Tabs": return .tabs(try tabsSpec(path, j))
    case "Stepper": return .stepper(try stepperSpec(path, j))
    case "SummaryList": return .summaryList(try summaryListSpec(path, j))
    case "Disclosure": return .disclosure(try disclosureSpec(path, j))
    case "Modal": return .modal(try modalSpec(path, j))
    case "ScrollArea": return .scrollArea(try scrollAreaSpec(path, j))
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
    case "Link": return .link(try linkSpec(path, j))
    case "Image": return .image(try imageSpec(path, j))
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
          onRowClick: nil, rowKey: nil, rowKeyField: nil, staticRows: rows))
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
          child: try node("\(path).child", try req(path, f, "child")),
          fallback: try node("\(path).fallback", try req(path, f, "fallback"))))
    case "Switch":
      let cases = try array("\(path).cases", try req(path, f, "cases")).enumerated()
        .map { (i, item) -> SwitchCase in
          let cf = try object("\(path).cases[\(i)]", item)
          return SwitchCase(
            matchValue: try reqString("\(path).cases[\(i)]", cf, "match"),
            child: try node(
              "\(path).cases[\(i)].child", try req("\(path).cases[\(i)]", cf, "child")))
        }
      return .switchKind(
        SwitchSpec(
          stateKey: try reqString(path, f, "stateKey"),
          cases: cases,
          defaultChild: try node("\(path).default", try req(path, f, "default"))))
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
          body: try node("\(path).body", try req(path, f, "body")),
          holes: holes, effect: effect))
    case "FragmentRef":
      let args: [FragmentArgEntry] =
        try f["args"].map { try fragmentArgs("\(path).args", $0) } ?? []
      return .fragmentRef(FragmentRefSpec(name: try reqString(path, f, "name"), args: args))
    case "Mount":
      let channelObj = try object("\(path).channel", try req(path, f, "channel"))
      let dirStr = try reqString("\(path).channel", channelObj, "direction")
      guard let direction = ChannelDirection(rawValue: dirStr) else {
        throw unknownCase("\(path).channel.direction", dirStr, "OutOnly | TwoWay")
      }
      let caps = try array("\(path).capabilities", try req(path, f, "capabilities")).enumerated()
        .map { try string("\(path).capabilities[\($0.0)]", $0.1) }
      let inputs: [FragmentArgEntry] =
        try f["inputs"].map { try fragmentArgs("\(path).inputs", $0) } ?? []
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

  static func stateBehaviour(_ path: String, _ j: JSON) throws -> StateBehaviour {
    let f = try object(path, j)
    var onLoading: NodeRef? = nil
    if let v = f["onLoading"] { onLoading = NodeRef(try node("\(path).onLoading", v)) }
    var onEmpty: NodeRef? = nil
    if let v = f["onEmpty"] { onEmpty = NodeRef(try node("\(path).onEmpty", v)) }
    return StateBehaviour(onLoading: onLoading, onEmpty: onEmpty, onError: optClosure(f, "onError"))
  }

  static func semanticStyle(_ path: String, _ j: JSON) throws -> SemanticStyle {
    let f = try object(path, j)
    let role: StyleRole =
      try f["role"].map { try bareEnum("\(path).role", $0, "StyleRole") } ?? .none
    let voice: FontVoice =
      try f["voice"].map { try bareEnum("\(path).voice", $0, "FontVoice") } ?? .default
    // Phase 460 — tone/weight/emphasis omitted-when-default (as role/voice).
    return SemanticStyle(
      emphasis: try optEmphasisDefault(path, f, "emphasis"),
      tone: try optToneDefault(path, f, "tone"),
      weight: try optWeightDefault(path, f, "weight"),
      role: role, voice: voice)
  }

  static func accessibility(_ path: String, _ j: JSON) throws -> Accessibility {
    let f = try object(path, j)
    let liveRegion: LiveRegionKind? =
      try f["liveRegion"].map { try bareEnum("\(path).liveRegion", $0, "LiveRegionKind") }
    return Accessibility(
      label: try optBinding(path, f, "label"),
      labelledBy: try optString(path, f, "labelledBy"),
      describedBy: try optString(path, f, "describedBy"),
      role: try optString(path, f, "role"),
      liveRegion: liveRegion,
      hidden: try optBinding(path, f, "hidden"))
  }

  static func node(_ path: String, _ j: JSON) throws -> Node {
    let f = try object(path, j)
    let id = try string("\(path).id", try req(path, f, "id"))
    if id.isEmpty {
      throw err(.emptyNodeId, "\(path).id", "Node id is empty")
    }
    let kind = try nodeKind("\(path).kind", try req(path, f, "kind"))
    let state: StateBehaviour =
      try f["state"].map { try stateBehaviour("\(path).state", $0) } ?? .empty
    let style: SemanticStyle =
      try f["style"].map { try semanticStyle("\(path).style", $0) } ?? .default
    let accessibilityV: Accessibility? =
      try f["accessibility"].map { try accessibility("\(path).accessibility", $0) }
    return Node(id: id, kind: kind, state: state, style: style, accessibility: accessibilityV)
  }
}
