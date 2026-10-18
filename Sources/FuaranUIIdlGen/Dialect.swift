// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// This surface's DIALECT over the IDL (Phase 2299): every place the Swift model
// is not what the uniform mapping rules in `Codegen.swift` produce, one entry
// each, with the reason.
//
// The rules derive everything else. An entry here is a statement that this
// surface models one IDL position differently ON PURPOSE, and every entry is
// ORPHAN-REFUSING: the generator fails, rather than emitting, when an entry
// names a kind, record, union, case or field `idl.json` no longer has, or when
// the rules would now produce exactly what the entry says. A table that can
// outlive its subject is a table nobody can trust to be complete.
//
// Never fix a Swift representation choice by changing the IDL. The IDL states
// the wire vocabulary; this file states how one surface spells it.
//
// Addresses: `kind <Tag>`, `record <Name>`, `union <Name>`, `enum <Name>`;
// a field is `<owner>.<field>` (`kind Switch.default`, `record TrackEntry.default`)
// and a union case is `union <Name>.<Case>`, its field `union <Name>.<Case>.<field>`.

/// One dialect entry.
struct DialectEntry {
  enum Subject {
    /// The Swift type name of a kind spec, record, union or enum.
    case typeName(String, String)
    /// The Swift case identifier of a node kind, union case or enum case.
    case caseName(String, String)
    /// The Swift identifier of a field (a stored property, or a case payload label).
    case fieldName(String, String)
    /// The complete Swift type of a field, `?` included.
    case fieldType(String, String)
    /// The Swift default of a field, where the rules state none or another.
    case fieldDefault(String, String)
    /// A field this projection does not model at all.
    case omit(String)
    /// The declaration order of a type's or case's modelled fields, by IDL name.
    case order(String, [String])
    /// A union case whose payload is positional although the rules would label it.
    case unlabeled(String)
    /// A node kind whose `NodeKind` payload is one field of the kind, not a spec record.
    case kindPayload(String, field: String)
    /// A type kept hand-written: the rules do not emit it.
    case handWritten(String)
    /// The Swift case name of an IDL node category.
    case category(String, String)
  }

  let subject: Subject
  let reason: String
}

private func entry(_ s: DialectEntry.Subject, _ reason: String) -> DialectEntry {
  DialectEntry(subject: s, reason: reason)
}

/// The types that offer a PUBLIC memberwise initialiser. Construction surface,
/// not a mapping difference: everything else is constructed only by the decoder
/// (inside this module). The initialiser takes the type's declared order and
/// the rules' defaults, so it is the same initialiser these types always had.
/// An address the IDL does not have, or a hand-written type, is refused.
let publicInitialisers: [(String, String)] = [
  ("record Accessibility", "authored by renderer code and tests as a node trait"),
  ("record DrawPoint", "built by the sparkline → Drawing lowering"),
  (
    "record DrawStyle",
    "rebuilt field by field by the style cascade (a new field must be a compile error there)"
  ),
  ("kind Drawing", "a Drawing is something the sparkline lowering PRODUCES as well as decodes"),
  ("kind Embed", "built by renderer code and tests"),
  ("record InvokeArg", "built by host code that composes an Invoke"),
  ("record MapMarker", "built by host code that resolves a marker source"),
  ("kind Media", "built by renderer code and tests"),
  ("record SelectOption", "built by host code that resolves an option source"),
  ("record SrcSetEntry", "built by renderer code and tests"),
  ("record TrackEntry", "built by renderer code and tests"),
  ("record TransformParam", "built by host code that composes a Transform"),
  ("record TreeItem", "built by renderer code and tests"),
  ("kind Tree", "built by renderer code and tests"),
  ("record ViewBox", "built by the sparkline → Drawing lowering"),
]

let dialect: [DialectEntry] =
  [
    // ── Names ────────────────────────────────────────────────────────────────
    entry(
      .typeName("kind DataGrid", "GridSpec"),
      "the public spec type has always been `GridSpec`; the wire kind is `DataGrid`"),
    entry(
      .typeName("record GuestChannel", "MountChannel"),
      "the public type is named for the kind that carries it"),
    entry(
      .typeName("union Scalar", "FragmentScalar"),
      "`Scalar` alone is too generic a public name in this module; it is the fragment-hole scalar"),
    entry(
      .caseName("kind Switch", "switchKind"),
      "`switch` is a keyword, and the public case has always been `switchKind`"),
    entry(
      .caseName("enum NavigateTarget.Self", "selfWindow"),
      "`self` cannot name a case; the public case has always been `selfWindow`"),
    entry(
      .caseName("union Binding.Static", "staticValue"),
      "`static` is a keyword, and the public case has always been `staticValue`"),
    entry(
      .caseName("union HoleDecl.Repeat", "repeatHole"),
      "`repeat` is a keyword, and the public case has always been `repeatHole`"),
    entry(
      .caseName("union HoleValueSpace.Enum", "enumChoices"),
      "`enum` is a keyword, and the public case has always been `enumChoices`"),
    entry(.category("Meta", "structural"), "the public category has always been `structural`"),
    entry(
      .fieldName("kind Switch.default", "defaultChild"),
      "`default` is a keyword; the public property has always been `defaultChild`"),
    entry(
      .fieldName("record TrackEntry.default", "isDefault"),
      "`default` is a keyword; the public property has always been `isDefault`"),
    entry(
      .fieldName("union CellKindErased.TonedPill.default", "defaultTone"),
      "the public payload label has always been `defaultTone`"),
    entry(
      .fieldName("union FormFieldKind.Checkbox.onChange", "onToggle"),
      "the wire handler was renamed `onChange` (one name per form field); the public payload label is kept"
    ),
    entry(
      .fieldName("union FormFieldKind.Toggle.onChange", "onToggle"),
      "the wire handler was renamed `onChange` (one name per form field); the public payload label is kept"
    ),
    entry(
      .fieldName("union CellKindErased.ButtonGroup.buttons", "labels"),
      "the button records are inlined to their labels (their click handlers are closures)"),

    // ── The node envelope and the kinds folded by hand ───────────────────────
    entry(
      .kindPayload("kind Filters", field: "items"),
      "`NodeKind.filters` has always held the filter list directly; there is no `FiltersSpec`"),
    entry(
      .handWritten("record StateBehaviour"),
      "an inline field of the hand-written `Node`; its node slots are boxed in `NodeRef` so the value graph stays finite"
    ),
    entry(
      .handWritten("record SwitchCase"),
      "`match` and `when` are exactly-one-of, folded into one `SwitchCondition` so a case cannot carry both"
    ),
    entry(
      .handWritten("union FragmentArg"),
      "the four scalar cases fold into `value(FragmentScalar)`, the wire's one slot case stays `slot(tree:)`"
    ),

    // ── Types ────────────────────────────────────────────────────────────────
    entry(
      .fieldType("record Accessibility.role", "String?"),
      "the role token is carried as its string; the projection maps known tokens and reports the rest"
    ),
    entry(
      .fieldType("record SelectOption.label", "TextSource"),
      "an option's label decodes through the bare-string `TextSource` canonical form"),
    entry(
      .fieldType("record MapMarker.label", "TextSource"),
      "a marker's label decodes through the bare-string `TextSource` canonical form"),
    entry(
      .fieldType("kind Custom.exposedNodeIds", "[String]"),
      "total: an absent list and an empty one denote the same document"),
    entry(
      .fieldType("kind Select.multiple", "Bool"),
      "total: absent means a single select, so `false` is a default, not a third state"),
    entry(
      .fieldType("kind FragmentRef.args", "[FragmentArgEntry]"),
      "the map is held as entries in key order, so decode order and refusal order are the document's"
    ),
    entry(
      .fieldType("kind Mount.inputs", "[FragmentArgEntry]"),
      "the map is held as entries in key order, so decode order and refusal order are the document's"
    ),
    entry(
      .fieldType("union CellKindErased.ButtonGroup.buttons", "[TextSource]"),
      "the button records are inlined to their labels (their click handlers are closures)"),
    entry(
      .fieldType("union Binding.Static.value", "StaticValue"),
      "total: an absent static payload decodes to the typed placeholder the slot's type implies"),
    entry(
      .fieldType("union Binding.State.defaultValue", "StaticValue"),
      "total: an absent default decodes to the typed placeholder the slot's type implies"),
    entry(
      .fieldType("union Binding.I18n.args", "[NamedBinding]?"),
      "the argument map is held as named entries in key order"),
    entry(
      .fieldType("union Binding.Transform.source", "DataSource"),
      "the host-declared transform source is decoded into the compute layer's `DataSource`"),
    entry(
      .fieldType("union Binding.Transform.pipeline", "[TransformStep]"),
      "the host-declared pipeline is decoded into the compute layer's `TransformStep`s"),
    entry(
      .fieldType("union Binding.Expr.expr", "ColExpr"),
      "the host-declared expression is decoded into the compute layer's `ColExpr`"),
  ] + formFieldValueTotal + [
    // ── Defaults ─────────────────────────────────────────────────────────────
    entry(
      .fieldDefault("kind Drawing.style", ".empty"),
      "the empty style is the public initialiser's default, so a lowering need not spell it"),

    // ── Positional payloads ──────────────────────────────────────────────────
    entry(
      .unlabeled("union TextSource.Literal"), "the public case has always been `literal(String)`"),
    entry(.unlabeled("union TextSource.Bound"), "the public case has always been `bound(Binding)`"),
    entry(
      .unlabeled("union CurveCommand.MoveTo"), "the public case has always been `moveTo(DrawPoint)`"
    ),
    entry(
      .unlabeled("union CurveCommand.LineTo"), "the public case has always been `lineTo(DrawPoint)`"
    ),
    entry(.unlabeled("union Action.Chain"), "the public case has always been `chain([Action])`"),

    // ── Union-case payload members left out ──────────────────────────────────
    // A kind's or a record's field is never omitted (the generator refuses it,
    // Phase 2331): it is carried, and one this projection does not render is a
    // documented render absence. What remains are closure slots inside a union
    // case's payload, whose wire form is the presence-only `"<closure>"`
    // sentinel, and which an unknown-key-tolerant decode reads past. Adding a
    // member to a public enum case's payload breaks every pattern and every
    // construction of that case, so each waits for a breaking release.
    entry(
      .omit("union Action.ReadFileBody.onRead"),
      "a presence-only closure slot; adding it to the public case's payload is a source break"),
    entry(
      .omit("union CellKindErased.Editable.onEdit"),
      "a presence-only closure slot; adding it to the public case's payload is a source break"),
    entry(
      .omit("union CellKindErased.Checkbox.onToggle"),
      "a presence-only closure slot; adding it to the public case's payload is a source break"),
    entry(
      .omit("union CellKindErased.Button.onClick"),
      "a presence-only closure slot; adding it to the public case's payload is a source break"),
    entry(
      .omit("union CellKindErased.Progress.labelFn"),
      "a presence-only closure slot; adding it to the public case's payload is a source break"),

    // ── Public payload order (an enum case's associated values are positional API) ──
    entry(
      .order("union Action.Call", ["endpoint", "into", "onResult"]),
      "the public case order"),
    entry(
      .order("union Binding.Local", ["codec", "commitTo", "flushOn", "initialFrom", "onCommit"]),
      "the public case order"),
    entry(.order("union Binding.Format", ["format", "locale", "source"]), "the public case order"),
    entry(
      .order("union Binding.Transform", ["params", "pipeline", "source"]), "the public case order"),
    entry(.order("union BoxLayout.Flex", ["direction", "gap", "wrap"]), "the public case order"),
    entry(
      .order("union BoxLayout.Grid", ["cols", "gap", "templateColumns"]), "the public case order"),
    entry(
      .order("union FormFieldKind.TextArea", ["rows", "value", "onChange"]), "the public case order"
    ),
    entry(
      .order("union FormFieldKind.RangedNumber", ["value", "min", "max", "step", "onChange"]),
      "the public case order"),
    entry(
      .order("union FormFieldKind.Range", ["value", "min", "max", "step", "onChange"]),
      "the public case order"),
    entry(
      .order(
        "union FormFieldKind.SegmentedChoice", ["options", "orientation", "value", "onChange"]),
      "the public case order"),
    entry(
      .order(
        "union FormFieldKind.DateTime", ["value", "variant", "min", "max", "step", "onChange"]),
      "the public case order"),
    entry(
      .order(
        "union FormFieldKind.DateTimeRange", ["value", "variant", "min", "max", "step", "onChange"]),
      "the public case order"),
    entry(
      .order("union FormFieldKind.Combobox", ["options", "value", "allowFreeText", "onChange"]),
      "the public case order"),
    entry(
      .order("union FormFieldKind.Rating", ["value", "max", "allowHalf", "onChange"]),
      "the public case order"),
    entry(.order("union FormFieldKind.Color", ["value", "onChange"]), "the public case order"),
    entry(
      .order("union FormFieldKind.Tokens", ["value", "suggestions", "allowFreeText", "onChange"]),
      "the public case order"),

    // ── Public initialiser order (a public initialiser's parameter order is API) ──
    entry(
      .order(
        "record Accessibility",
        ["label", "labelledBy", "describedBy", "role", "liveRegion", "hidden", "speak"]),
      "the public initialiser's order"),
    entry(
      .order(
        "record DrawStyle",
        [
          "fill", "stroke", "strokeWidth", "opacity", "textAnchor", "fontSize", "emphasis",
          "fontFamily", "markId", "rotation", "tip",
        ]),
      "the public initialiser's order"),
    entry(
      .order("kind Drawing", ["viewBox", "shapes", "style", "title", "description"]),
      "the public initialiser's order"),
    entry(
      .order("kind Embed", ["src", "title", "permissions", "aspectRatio"]),
      "the public initialiser's order"),
    entry(
      .order("kind Media", ["kind", "label", "src", "controls", "loop", "tracks", "transcript"]),
      "the public initialiser's order"),
    entry(.order("record SelectOption", ["value", "label"]), "the public initialiser's order"),
    entry(
      .order("record TrackEntry", ["kind", "src", "srcLang", "label", "default"]),
      "the public initialiser's order"),
    entry(.order("record TransformParam", ["name", "from"]), "the public initialiser's order"),
    entry(
      .order("record TreeItem", ["id", "label", "icon", "children"]),
      "the public initialiser's order"),
    entry(
      .order("kind Tree", ["items", "expandedStateKey", "selectionStateKey", "onSelect"]),
      "the public initialiser's order"),
    entry(
      .order("record ViewBox", ["minX", "minY", "width", "height"]),
      "the public initialiser's order"),
  ]

/// Every form-field case's `value`: the IDL types it as an optional host-declared
/// binding; this projection holds it TOTAL, because an absent value decodes to
/// the context's auto-binding (a filter chip's `Filter`, a form field's `State`
/// over the control's typed placeholder) — a control always has a value to show.
private let formFieldValueTotal: [DialectEntry] = [
  "Text", "Number", "Checkbox", "Toggle", "Choice", "TextArea", "RangedNumber", "Range",
  "SegmentedChoice", "DateTime", "DateTimeRange", "Combobox", "Rating", "Color", "Tokens",
].map {
  entry(
    .fieldType("union FormFieldKind.\($0).value", "Binding"),
    "total: an absent value decodes to the context's auto-binding")
}
