// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The documentation the generated model carries, by IDL address (Phase 2299) —
// the rationale each declaration states for a reader of this surface. Orphan-
// refusing like the dialect: an entry whose subject the generated model does not
// have fails the generation, so a note cannot outlive the field it explains.

let modelDocs: [String: String] = [
  "enum CaptureSource": #"""
  Phase 1116 — the recording device a `FileUpload` asks the platform for
  (§3.6.18). There is deliberately no display-capture case and there will not
  be one by widening this member: a screen capture reaches every window the
  reader has open rather than one device behind the picker.
  """#,
  "enum CompareOp": #"""
  `CompareRule.op` — the cross-field comparison operator.
  """#,
  "enum DateTimeVariant": #"""
  Phase 1811 — `DateTimeVariant` (was `DateVariant`): the temporal breadth of a
  `dateTime` / `dateTimeRange` field. The three cases did not move.
  """#,
  "enum DurationStyle": #"""
  How a `Duration` renders: `1h 5m` / `01:05:00` / `1 hour 5 minutes`.
  """#,
  "enum EmbedPermission": #"""
  `EmbedSpec.permissions` — the closed list of sandbox relaxations an embed may
  request (WIRE_FORMAT.md §3.6.8, Phase 1111). Bare strings on the wire, and
  the list is OMITTED at empty — which means TOTAL DENIAL, so the wire-cheapest
  document is also the most locked-down one.

  **Declaration order here IS the render order.** §3.6.8 obligation 2 fixes the
  emitted token order at the vocabulary's declaration order rather than the
  document's, so two documents naming the same set render identically; the
  `CaseIterable` order below is that order, and the projection reads it rather
  than carrying a second list.

  **Two relaxations are excluded rather than defaulted off, and are not
  reserved either**: a top-level-navigation relaxation would let a framed
  document navigate the page that framed it, and a downloads relaxation would
  put a file-save prompt in a third party's hands. Neither is admitted and
  neither is a name a later phase should take — which is why
  `"allow-top-navigation"`, the token an author reaches for from memory, is
  refused as `UNKNOWN_DU_CASE` rather than aliased.
  """#,
  "enum IconSize": #"""
  The rendered size of a standalone `Icon`. Omitted on the wire at `Medium`.
  """#,
  "enum ImageAspect": #"""
  The box the element reserves BEFORE the image arrives (§3.6.2). Omitted on
  the wire at `Natural`.

  A LAYOUT reservation, not a crop — what happens to pixels that do not match
  the box is `ImageFit`'s statement, and neither is derived from the other.
  Four named ratios, never a number, a pair, or the stylesheet spelling
  (`"16 / 9"`, `"16:9"`, `1.7778`); the corpus's `reject-unknown-image-aspect`
  fixture pins that refusal at the bare slot.
  """#,
  "enum ImageFit": #"""
  How the decoded pixels fill the box the layout gives the element (§3.6.2).
  Omitted on the wire at `Natural`.

  A TOKEN, never a CSS value — the vocabulary is closed at three, so an
  author-supplied `object-fit` string has nowhere to land. That is the point:
  admitting one would put a free-form style value on the wire, which is the
  escape this format does not have.
  """#,
  "enum ImageLoading": #"""
  Whether a fetching host loads the image during initial load or defers it
  (§3.6.2). Omitted on the wire at `Eager`.

  `Eager` is the default deliberately, and it is not the "unoptimised" value:
  deferring an above-the-fold image delays the largest contentful paint rather
  than helping it, and only the author knows where the image sits. A host MUST
  NOT infer laziness from position, viewport, or anything else the tree does
  not say.
  """#,
  "enum LinkProtection": #"""
  Anti-scraper render strategy for a `Link` — `email` marks a `mailto:` link
  whose address must not appear in plaintext in emitted markup (the emission
  strategy is renderer-owned; a render projection may treat it as advisory).
  Lower-case on the wire.
  """#,
  "enum ModalityKind": #"""
  §3.6.11 — the modality a `Modal` declares. Omitted at `modal`, which is the
  blocking modality every pre-modality document meant.
  """#,
  "enum NavigateTarget": #"""
  Phase 1536 — `Action.navigate`'s destination window (§3.6.21). A CLOSED
  enum of two, deliberately not HTML's `target` attribute: that vocabulary
  also carries `_parent` and `_top`, which are frame-busting gestures a hosted
  tree must not be able to ask for, so `_blank` is refused rather than aliased
  — accepting any of it would teach an emitter the wrong vocabulary.
  """#,
  "enum SortDirection": #"""
  A sort direction. Lower-case on the wire, like `LinkProtection`.
  """#,
  "enum TextDirection": #"""
  Phase 1472 — the node-level declared text direction (§3.1). Lower-case on
  the wire, like `LiveRegionKind` and `SortDirection`, because these are the
  HTML `dir` tokens themselves. Omitted at `auto`, which leaves the inherited
  direction in place — the pre-1472 rendering.
  """#,
  "enum TextFormat": #"""
  `FieldRule.format` — the closed named-format set a text field's value is held to.
  """#,
  "enum TimeGrain": #"""
  The unit a `Duration` cell format's raw value counts in.
  Phase 1533 — the resolution a `Binding.now` declares for the host-furnished
  instant. FOUR members and not `RelativeTimeUnit`'s seven, deliberately: this
  is a TRUNCATION of a calendar instant, and a week, a month or a year has no
  truncation every host agrees on (which weekday starts a week; which
  calendar). The four here truncate the canonical ISO-8601 form by prefix.
  """#,
  "enum TimeStyle": #"""
  Phase 1810 — the time-of-day half of `Format.dateTime`'s `dateStyle` /
  `timeStyle` pair. The same four cases as `DateStyle`, deliberately a SEPARATE
  enum: the two name breadths of different things.
  """#,
  "enum TrackKind": #"""
  `TrackEntry.kind` — a media element's timed-text track class
  (WIRE_FORMAT.md §3.6.6, Phase 1110). Bare strings on the wire.

  **The set is CLOSED at four, and `Metadata` is deliberately not a case.** Its
  cues are rendered by no user agent and read only by script, so a declarative
  document naming it would state an intent no conformant host could honour
  without leaving the vocabulary. A fifth is an ADDITION, never a spelling a
  decoder may guess at — which is why no alias arm is registered for the HTML
  lower-case spellings either: those are the emitted tokens, not accepted
  input.
  """#,
  "enum TrendPolarity": #"""
  `Metric.trendPolarity` — which way the measured quantity IMPROVES
  (WIRE_FORMAT.md §3.6.1). Distinct from `tone`, which says how the reading
  STANDS: a host derives neither from the other, and nothing here ever writes
  back to `tone`.

  **`Neutral` is reserved by the specification and is deliberately NOT a case
  here.** The case set IS the accepted wire set, so omitting it means
  `"Neutral"` fails `UNKNOWN_DU_CASE` naming the two legal spellings, rather
  than this surface quietly deciding a question the reservation holds open.
  That is the same modelling choice the Rust reference core made for the same
  slot, and it is why the wire slot is an enum rather than an `inverted` bool:
  admitting the third case later is one added case plus a compiler error at
  every site that must then decide what it means.

  No alias arm is registered, and that omission is deliberate: the obvious
  candidates are precisely the spellings that must not be accepted — `Neutral`
  would pre-empt the reservation, and `Inverted` / `Descending` would reinstate
  the boolean spelling §3.6.1 refuses.
  """#,
  "kind Box.breakBefore": #"""
  Phase 1473 — the print-break controls. Both omit at `false`, and both are
  declarations about PAGINATED media alone: a screen host reads them and
  emits nothing.
  """#,
  "kind Chart.annotations": #"""
  Phase 1490 — omitted when the chart declares none.
  """#,
  "kind DataGrid.exportable": #"""
  Phase 1123 — this grid's rows may be taken out of the page as a file.
  Omitted at `false`.
  """#,
  "kind DataGrid.keepRowsTogether": #"""
  Phase 1473 — the paginated-media pair, on `Box`'s terms.
  """#,
  "kind DataGrid.pageSize": #"""
  Rows per page. The schema pins `minimum: 1` - a zero page size paginates nothing.
  """#,
  "kind DataGrid.sortStateKey": #"""
  The sort / page / edit POSITIONS are addressed through state keys rather than
  literal values, so a control can move them; `defaultSort` and `pageSize` are the
  initial configuration. Decoded faithfully because this is a view of the wire -
  dropping a declaration would misreport the tree. Acting on them is the renderer's
  business, not the decoder's.
  """#,
  "kind DataGrid.transferInKey": #"""
  Phase 1125 — the two sides of ONE shared State key. A grid declaring
  `transferOutKey` K may RELEASE rows onto K; one declaring `transferInKey`
  K ACCEPTS rows arriving on it. Separate decoder arms, and the corpus
  vectors them separately for that reason.
  """#,
  "kind Drawing": #"""
  The initialiser is public because a `Drawing` is something a render
  projection PRODUCES as well as decodes: the Phase 1099 sparkline lowering
  builds one from a resolved series so the picture goes through the drawing
  canvas the surface already has, rather than through a second hand-written
  vector path. This is not an encode leg — the value never becomes wire bytes
  here — so the decode-only posture is unchanged.
  """#,
  "kind Embed": #"""
  The sandboxed third-party embed (§3.6.8, Phase 1111).

  **A KIND, not a `Mount` variant and not a `Media` variant.** `Mount` composes
  a COOPERATING guest — a scope id, a declared message channel, a capability
  request list — and a third-party page has none of those and cannot acquire
  them. `Media` fetches an asset and DISPLAYS it, decoded into no scripting
  context, where an embed fetches a document and lets it EXECUTE. That last
  difference is why the source takes its own, narrower egress class (§19.1)
  rather than reusing `Media`'s.
  """#,
  "kind Embed.aspectRatio": #"""
  REUSES `ImageAspect` rather than minting a parallel enum with identical
  cases: the cases are pure layout ratios with nothing image-specific in
  them, and the wire carries bare strings, so the type name reaches no
  document. Two closed sets that must be kept in step is the defect a
  separate type would introduce, not avoid. Total, omitted at `Natural`.
  """#,
  "kind Embed.permissions": #"""
  Omitted at the EMPTY list, and empty means TOTAL DENIAL. That polarity is
  the design rather than a consequence of the omit rule: the wire-cheapest
  document is also the most locked-down one, so the default a careless
  emitter produces is the safe one.

  AUTHORED order is preserved here (a JSON array is ordered data); the
  vocabulary's declaration order is imposed at RENDER time, which is where
  the determinism the markup needs actually belongs.
  """#,
  "kind Embed.title": #"""
  REQUIRED, on `MediaSpec.label`'s argument one kind over. A frame is a focus
  container a reader tabs INTO, so there is no decorative embed the way there
  is a decorative image; a frame with no accessible name is announced as
  "frame" and nothing else. A document omitting it is refused rather than
  defaulted, because an invented title is a claim about somebody else's
  document.
  """#,
  "kind Fact": #"""
  The labeled text-fact kind (0.2.x — `Fact`).
  """#,
  "kind FileUpload.capture": #"""
  Phase 1116 (§3.6.18) — WHICH of the reader's own recording devices the
  platform should open in place of the file browser. OPTIONAL rather than
  omit-at-default: "say nothing" is a state of its own, because an upload
  naming no device is asking for the file browser, which is not one of the
  two devices wearing a default.
  """#,
  "kind FileUpload.destination": #"""
  Phase 1117 (§3.6.20) — the host-registered destination an upload streams
  to. A NAME, and a name because it must never be an ADDRESS: a wire
  document comes from an arbitrary emitter, and a URL here would let that
  emitter choose where a reader's file goes. The empty string is REFUSED
  rather than read as absence, which would silently turn an upload the
  author meant to stream into a client-only one.
  """#,
  "kind FileUpload.dropTarget": #"""
  Phase 1115 — two ADDITIONAL ingress routes, never replacements for the
  picker. Both omit at `false`, and the polarity is load-bearing: the
  shortest upload document is the plain picker, which is what every document
  written before that revision says.
  """#,
  "kind FileUpload.maxBytes": #"""
  Phase 1548 (§3.6.23) — the declared ceilings: how large a file, and how
  many of them, this control accepts.

  `maxBytes` is PER FILE rather than per selection. That is what makes it
  meaningful on a single-file upload and what makes it the quantity a body
  read can be measured against; a control bounding a whole multiple
  selection states both members and the total it declares is
  `maxBytes × maxFiles`. A per-selection sum would be a different quantity
  wearing the same name.

  `maxFiles` is meaningful only alongside `multiple`, and beside
  `"multiple":false` it is INERT — carried, not refused, because the bytes
  describe a control every host renders identically with or without it, so
  there is nothing for a decoder to be right about.

  Both are OPTIONAL and POSITIVE. Absent declares no ceiling, which is every
  pre-1548 document exactly; `0` and below are refused at decode, because a
  ceiling of zero is not a small ceiling but a control that can accept
  nothing. `Int` here is §7.1's 32-bit slot, bounded by the strict integer
  reader rather than by this type.
  """#,
  "kind Icon": #"""
  A standalone glyph. `icon` is a NAME; the embedding app owns the name -> glyph
  mapping, so this projection carries the name rather than resolving it.
  """#,
  "kind Icon.label": #"""
  Absent => decorative (the a11y layer hides it); present => a labelled image role.
  """#,
  "kind Image.caption": #"""
  §3.6.3 — CONTENT, not a presentation token, so it takes the ordinary
  optional posture (there is no default caption the way there is a default
  fit) and is a `TextSource` rather than a `String`: a caption is
  i18n-capable on exactly the terms `alt` is. Narrowing this slot to a
  string is the rule a second surface is most likely to break, because it
  costs nothing until somebody needs a locale.
  """#,
  "kind Image.expandable": #"""
  §3.6.5 — the only slot on this record that declares an INTERACTION.
  `false` by default and omitted at that default. What it declares is that
  the full asset is REACHABLE from the rendered image, not that a lightbox
  appears; nothing crosses the dispatch gate (§4), which is why it is a
  bool and not an `Action`.
  """#,
  "kind Image.fit": #"""
  §3.6.2 — the three presentation slots, each omitted on the wire at its
  identity default. TOTAL, not `Optional`: "absent means `Natural`" is a
  DEFAULT rather than a third state, so modelling absence as `nil` would
  push the decision back out to every reader (the `trendPolarity`
  precedent, §3.6.1).
  """#,
  "kind Image.srcSet": #"""
  §3.6.4 — absent MEANS the empty list, never `nil`. An absent slot and an
  empty one denote the SAME document, so this is `[SrcSetEntry]` and not
  `[SrcSetEntry]?`; a surface answering `nil` for an absent `srcSet` has
  produced a value the format's own encoder cannot round-trip. AUTHORED
  ORDER is preserved — a codec MUST NOT re-sort, because canonicalisation
  sorts object keys and never array elements. (Ascending-by-width is a
  RENDER-time ordering; see `orderedForPresentation` in the renderer.)
  """#,
  "kind LabelValueRow.emphasis": #"""
  The behavioural bool (is this row emphasised?) — 0.2.2 omitted-when-false;
  distinct from the `Emphasis` style enum.
  """#,
  "kind LabelValueRow.value": #"""
  0.2.0 rename law — scalar displayed value ⇒ `value` (`data` alias kept).
  """#,
  "kind Link.protection": #"""
  Omitted on the wire when `nil`.
  """#,
  "kind Media.controls": #"""
  Omitted on the wire at TRUE — the second such slot in the vocabulary
  (`Toast.dismissable` is the first). The polarity is deliberate: a media
  element without a transport cannot be paused, seeked or muted by a
  keyboard user at all, so the accessible setting is what a document gets
  for free and taking it away is the deviation that costs a key.
  """#,
  "kind Media.label": #"""
  REQUIRED — the one place the media contract differs from `Image`'s. An
  image can honestly be decorative and say so with an empty `alt`; a media
  element is a TRANSPORT a reader focuses, plays, pauses and seeks, so it is
  never decorative. A document omitting it is refused rather than defaulted,
  because there is no value to default to that would not be a fabricated
  name for someone else's recording.
  """#,
  "kind Media.loop": #"""
  The ordinary polarity — omitted at `false`.
  """#,
  "kind Media.tracks": #"""
  §3.6.6 (Phase 1110) — the element's timed-text tracks, on the SPEC rather
  than on `MediaKind.video`, because captions and a transcript are not
  video-only affordances.

  Absent MEANS the empty list, never `nil` — an absent slot and an empty one
  denote the same document, so this is `[TrackEntry]` and not
  `[TrackEntry]?`, exactly as `ImageSpec.srcSet` is. AUTHORED ORDER is
  preserved and never re-sorted: this is the OPPOSITE of `srcSet`'s rule, and
  the difference is not an inconsistency — a browser picks ONE candidate from
  a srcset by an algorithm, so ordering it is canonicalisation, while a
  reader picks a track from a menu the user agent builds in DOCUMENT order,
  so ordering it would be rewriting someone else's menu.
  """#,
  "kind Media.transcript": #"""
  §3.6.6 (Phase 1110) — the element's text alternative.

  An ORDINARY optional, and the contrast with `tracks` is deliberate: absent
  means the document offers no transcript, which is a different statement
  from offering an empty one. It lives on the spec rather than on the video
  variant because a transcript is the affordance an AUDIO surface needs most
  — a recording with no visual channel has nowhere else to put its words.
  """#,
  "kind Metric.trendPolarity": #"""
  §3.6.1 — which way the quantity IMPROVES. TOTAL, not an `Optional`, and
  decoded independently of `trend`: the wire's "absent means
  `HigherIsBetter`" is a DEFAULT rather than a third state, so modelling it
  as `nil` would push the decision back out to every reader. A polarity
  declared with no `trend` is inert (legal per clause 4) and is kept rather
  than dropped — dropping it would silently rewrite the author's document
  because this surface judged the declaration pointless.
  """#,
  "kind Metric.value": #"""
  0.2.0 rename law — the scalar displayed value is `value` on the wire (the
  retired `source` spelling is a hard error; the `data` alias is lenient).
  """#,
  "kind Modal.modality": #"""
  §3.6.11 — omitted at `modal`, which is the blocking modality every
  pre-modality document meant. A present value outside the two is
  `UNKNOWN_DU_CASE` and a non-string is `WRONG_TYPE`; neither falls back,
  because a document asking for a popover and getting a blocking modal has
  been answered with a different affordance.
  """#,
  "kind Switch": #"""
  The declarative selector. The branch follows a state key or - since the widening -
  any `Binding`, so a `Selection` makes it follow the clicked row. The schema requires
  at least one of the two (`anyOf`); `on` is the more specific declaration and wins.
  """#,
  "kind Switch.autoAdvanceMs": #"""
  Phase 1122 — the timed carousel: advance to the next case every
  this-many milliseconds, omitted at absence. It declares the one fact a
  host cannot recover from the tree — every other half of a carousel was
  already composable, and nothing in any arrangement of those says a timer
  exists.

  A DURATION, never a flag. Non-positive and fractional values are REFUSED
  rather than canonicalised: `0` is what an emitter reaches for to mean
  "off" and the language already has a spelling for off, an absent key.
  """#,
  "kind Tree": #"""
  Recursive disclosure with tree semantics (§3.6.12, Phase 1120).

  **This kind carries no `expandable` and no `selectable` boolean, and none is
  coming.** A behaviour the reader drives is declared as a named State key the
  host both writes and reads; a flag with no key behind it is a decorative
  control writing state nothing reads. The slot shapes are fixed by the
  specification so a host reading them does not have to guess:

  - `expandedStateKey` names a JSON **array of row ids** — the rows currently
    open. Absent, the tree renders FULLY EXPANDED and does not toggle.
  - `selectionStateKey` names a bare **row-id string**. Absent, the tree does
    not select and carries no selected state at all.

  A state value of any other shape reads as *empty* / *none* rather than as an
  error: this is a host's own state slot and not a wire document, so there is
  nothing here to refuse, and refusing would blank a tree over a value the
  reader never authored.
  """#,
  "record Accessibility.speak": #"""
  Phase 1812 — the node's SPOKEN rendering for a voice surface: an ordinary
  `TextSource` (bare-string canonical for a literal, as `tooltip`). Inert to
  every visual renderer: it MUST reach no attribute and no visible text.
  """#,
  "record CompareRule": #"""
  The cross-field operand. `against` is a `Binding`, and that IS the
  cross-field mechanism rather than an accident of typing: any read slot may
  take a Binding, and the auto-bind rule already puts every form field's value
  in State under the field's own id, so `{"$type":"State","key":"<sibling id>"}`
  reads the sibling with no coordination vocabulary at all.
  """#,
  "record DefaultSort": #"""
  An initial sort: a zero-based header INDEX (the schema pins `minimum: 0`, so a
  negative is malformed rather than a from-the-end convention) plus a direction.
  """#,
  "record DrawStyle": #"""
  The public memberwise initialiser exists deliberately: the style cascade
  (`inheritedDrawStyle`) rebuilds a style field by field rather than copying
  and patching, so that adding a field to this record is a COMPILE ERROR at
  the cascade until someone decides whether it inherits. A copy-and-patch
  would silently leave a new field un-inherited.
  """#,
  "record DrawStyle.markId": #"""
  Phase 642 — keyed mark identity (omitted-when-absent on the wire).
  """#,
  "record DrawStyle.rotation": #"""
  Label rotation in DEGREES, clockwise-positive about the label's own anchor
  point — the wire's `rotate(θ x y)` semantics, taken as-authored (no host
  re-rounds on decode). Applies only to `Shape.label`; ignored elsewhere,
  exactly like the rest of the text-only cluster above.
  """#,
  "record DrawStyle.tip": #"""
  The mark's hover-readable readout. The one `DrawStyle` field that applies
  to EVERY shape rather than only to `label` — the marks a reader reaches for
  are the bars, wedges and points. An explicitly EMPTY tip is a present value
  and a distinct wire shape from an absent one.
  """#,
  "record FieldRule": #"""
  A field's declared constraint — the ACCEPTED SET, where `FormFieldKind`
  names the control. Every slot is optional structurally; the two
  well-formedness refusals (a rule that constrains nothing; `minLength` above
  `maxLength`) are relations BETWEEN slots and so live in the decoder's policy
  layer rather than in this shape.
  """#,
  "record FilterSpec": #"""
  0.2.0 filters-unification: a chip's control is an ordinary `FormFieldKind`
  (the retired `*Filter` discriminators are hard errors); its absent `value`
  slot auto-binds `Filter(name)`.
  """#,
  "record SemanticStyle": #"""
  The semantic-style triple plus the Phase 147 role/voice (both omitted on the
  wire at their defaults).
  """#,
  "record SemanticStyle.direction": #"""
  Phase 1472 — the one member of this record that is not presentational: it
  declares the text DIRECTION, which is a fact about the content rather than
  a style choice. Omitted at `auto` on both boundaries, like its siblings.
  """#,
  "record SrcSetEntry": #"""
  One alternate rendition of the SAME picture at a declared intrinsic pixel
  width (§3.6.4). Both members are required *within* the entry.
  """#,
  "record SrcSetEntry.width": #"""
  The `w` descriptor a client selects on. A POSITIVE integer, and the floor
  is a DECODE rule rather than a render one: a `0w` candidate is not a small
  image, it is one a client can never select, so admitting it would let the
  wire state a rendition no host can render.
  """#,
  "record TrackEntry": #"""
  One timed-text track on a media element (§3.6.6, Phase 1110).

  **The strictest record on the wire: four of its five members are REQUIRED.**
  `default` is the one omitted-at-`false` slot; everything else must be stated,
  and each requirement buys something a default could not.

  `srcLang` is required on EVERY kind, where HTML makes `srclang` mandatory
  only on a subtitles track. The extra strictness costs an author one value and
  buys a menu a user agent can order, a speech engine can pronounce and a
  reader can tell apart; there is no value to default to that would not be an
  invented claim about someone else's recording. `label` is required for the
  reason `MediaSpec.label` is: it is the entry a user agent puts in its track
  menu and the only thing distinguishing one track from another there.
  """#,
  "record TrackEntry.default": #"""
  The ONE omitted-at-`false` slot. Note what it does NOT decide: §3.6.6
  obligation 3 says a document electing two defaults of one kind is legal
  bytes, so this slot records the ELECTION and the render projection
  resolves it (first election of a kind wins). A decoder that refused the
  second election would refuse a document every lenient host renders.
  """#,
  "record TreeItem": #"""
  One row of a `Tree` (§3.6.12, Phase 1120) — the format's first
  SELF-REFERENTIAL record.

  Rows are `TreeItem`s, not `Node`s, and `children` is a list of the same
  record. `id` and `label` are required; `children` omits at the EMPTY list and
  `icon` when absent, so a leaf carries two keys and nothing else — which is
  most of a real hierarchy.

  `id` is required because it is what the two State slots NAME. `label` is a
  `TextSource` because it is content — authored, translated, bindable.

  **Row ids MUST be unique within one tree, and that is an EMIT-side
  obligation, not a decode refusal** (§8.1's position for `NodeId`, transferred
  for §8.1's own reason): duplicate detection is a whole-tree property, a
  decoder streaming a document is not required to carry the id set, and there
  is no error code for it. This surface therefore accepts a duplicate and is
  still conformant.
  """#,
  "union Action": #"""
  A user-interaction action (§3.3), one case per wire `$type`.
  """#,
  "union Action.Confirm": #"""
  Phase 1537 — ask, then act. Confirmation is bounded at ONE question: a
  `confirm` reachable from either continuation is refused, and the check
  walks the DECODED continuation so a `chain` cannot hide the nesting.
  """#,
  "union Action.Focus": #"""
  Phase 1537 — a bare node id, the `commitLocal` shape. It addresses a node
  in THIS document, so there is nothing for a binding to compute.
  """#,
  "union Action.Navigate": #"""
  Phase 1536 — `route` is a `TextSource`, not a bare string, so a tree can
  name a destination it computes from what the reader is looking at. The
  bare JSON string IS `Literal`'s canonical form, so every document written
  before the widening decodes exactly as it did. `target` is the CLOSED
  `Self | Blank` enum, omitted at `Self`.
  """#,
  "union Action.Print": #"""
  Phase 1124 — the payload-free print, and the ONE action case strict about
  unrecognised members: page range, size, margins and copies are the host's
  page setup and the reader's dialogue, so accepting a member here would
  leave the emitter believing it had constrained a printing it had not.
  """#,
  "union Action.SetState": #"""
  Exactly ONE of `value` (a literal payload) and `valueFrom` (a binding resolved at
  dispatch time) is present - the schema states it as a `oneOf`, so both-present is a
  reject rather than a precedence question.
  """#,
  "union Action.WriteToClipboard": #"""
  Phase 1126 — the payload is a `TextSource`. A `text` that is neither a
  string nor a `$type`-tagged `TextSource` is `WRONG_TYPE` and is never
  coerced: a host reading the widening as "this member is now open" would
  put a JSON literal on the reader's clipboard, and a clipboard is a channel
  the reader later pastes somewhere with authority.
  """#,
  "union Binding": #"""
  A value binding (§3.3), one case per wire `$type`.
  """#,
  "union Binding.Expr": #"""
  Phase 1534 (§3.3.2) — ONE scalar expression evaluated to ONE value over
  the SAME `ColExpr` algebra a `transform` pipeline step carries. The case
  introduces no operator and no expression language of its own, so an
  expression means here exactly what it means inside a `derive`.

  Two DECODE refusals, both because an `expr` has no row: a `col` reference
  anywhere in the expression, and a `param` the binding's own list does not
  bind. Left admitted, each would decode to an expression whose evaluation
  could only ever fail, once per render, on every host.
  """#,
  "union Binding.Filter": #"""
  0.2.0 — optional `defaultValue` (the `State.defaultValue` convention).
  """#,
  "union Binding.Local": #"""
  Phase 1534 (§3.3.3) — `codec` declares the buffer's OWN codec and replaces
  the identity on both sides; `commitTo` declares the State key the flush
  writes to. `commitTo` and the `onCommit` closure are mutually exclusive,
  because the wire cannot carry the closure and two hosts would otherwise
  write to different places from identical bytes.
  """#,
  "union Binding.Now": #"""
  The host-furnished instant. Carries no payload: the value is supplied at resolve
  time by the host clock, which is why it is a `Clock`-determinism source, not wire data.

  Phase 1533 — the declared GRAIN truncates the instant BEFORE it is read.
  Absent is `second`, which is the identity; a present value outside the
  four is refused rather than silently read at a neighbouring resolution.
  """#,
  "union Binding.Selection": #"""
  0.2.9 — optional `defaultValue`; 0.2.10 — optional `field` (the
  declarative row-field projection).
  """#,
  "union BoxLayout.Masonry": #"""
  WIRE_FORMAT §3.6.7 (Phase 1082) — the column-fill mode. `cols` is
  REQUIRED and POSITIVE; there is deliberately no `templateColumns` twin,
  because the multi-column model realising masonry has no track list for
  one to name.
  """#,
  "union CallResultTarget": #"""
  The declarative result target of an `Action.Call` (Phase 428).
  """#,
  "union CellFormat.DateTime": #"""
  Phase 1811 — `dateTime` (was `date`): the pattern renders a date, a time or both.
  """#,
  "union CellFormat.RelativeTime": #"""
  A relative-time CELL format ("3 minutes ago"). Distinct from the `Format` DU's own
  `relativeTime`: the wire carries two format DUs and a case in one is not a case in
  the other.
  """#,
  "union CellKindErased.TonedPill": #"""
  Phase 750 — the declarative twin of `pill`, and the ONE cell kind holding no
  closure, which is exactly why it survives the wire. `field` names the row
  property that is both the pill's label and the map key; `map` carries value →
  tone; `defaultTone` covers a value the map does not mention and is omitted on
  the wire at `.default`.

  This is the first cell kind this projection carries any PAYLOAD for. Every
  other one is defined by a closure, which never rides the wire, so the case
  name was the whole of the information — a decode-only projection could
  faithfully represent it as a bare case. A declared tone rule is data, so it
  has to be carried.
  """#,
  "union ChartAnnotation": #"""
  Phase 1490 (§4l) — a chart's data-addressed annotation. An annotation names a
  place in the DATA's coordinates and, optionally, a label; it carries no
  geometry and no style at all, which is what makes it survive a data change, a
  theme flip, a restyle and a resize.
  """#,
  "union ChartAnnotation.EventMarker": #"""
  A VERTICAL line at an x address — the reference line mirrored across the
  axes.
  """#,
  "union ChartAnnotation.RangeBand": #"""
  A shaded interval on either axis, and the one member that draws BEHIND
  every series.
  """#,
  "union ChartAnnotation.ReferenceLine": #"""
  A horizontal line at `value` in the VALUE axis's own units.
  """#,
  "union ChartAnnotationRange": #"""
  Phase 1492 (§4l) — a `rangeBand`'s PAIR: two of the same address form, on one
  axis.

  THE AXIS IS THE CASE. §4l requires a band to declare which axis it sits on;
  carrying that as a separate flag beside an untyped pair would admit a
  document declaring the value axis and addressing it with two category keys.
  The union tag declares the axis AND types the pair with it, so that document
  cannot be written by any conformant emitter.
  """#,
  "union ChartAnnotationX": #"""
  Phase 1491 (§4l) — an annotation's x address: a CATEGORY key read under the
  categorical scale, and an ISO-8601 `Date` read under `Temporal`.

  Its own type rather than two inline fields, because a range band addresses an
  x-axis interval with a PAIR of these.
  """#,
  "union FormFieldKind.Color": #"""
  Phase 1130 (§3.6.17) — the platform's own colour picker. A CONTROL, not a
  `rule.format`: a swatch that opens the operating system's picker, which no
  format on a text field can produce.

  Both members optional. The value is `#rrggbb` and nothing else — the one
  form a native colour input can hold or return — and case is PRESERVED
  rather than normalised.
  """#,
  "union FormFieldKind.Combobox": #"""
  The searchable form of `choice` (§3.6.9, Phase 1113). **`options` is the
  case's only REQUIRED member** — a combobox with no option source is not a
  control — and `value` / `onChange` are `choice`'s, deliberately and
  normatively: the constrained combobox IS a searchable select, so a document
  migrating between the two changes its `$type` and nothing else, and a host
  implementing a different value contract here would break exactly that
  migration.

  `allowFreeText` omits at `false` and the polarity is load-bearing: the
  SHORTEST combobox document is the CONSTRAINED one, so admitting off-list
  values is the thing an emitter has to ask for. A present member of any
  other type is `WRONG_TYPE` and MUST NOT be coerced — a lenient truthiness
  read would widen the field on `"no"` and `"false"` alike.

  An asynchronous suggestion source needs no vocabulary of its own: a
  `Binding.query` in the ordinary `options` slot IS the async feed, resolved
  by the same machinery every other query-bound slot uses. Nothing in this
  case names a request, a debounce or a minimum query length.
  """#,
  "union FormFieldKind.DateTime": #"""
  Phase 1811 — `dateTime` (was `date`): the field already took a date, a time
  of day or both via `variant`; the name now says so.
  """#,
  "union FormFieldKind.DateTimeRange": #"""
  0.7.0 — the single-control date range (`dateTimeRange` since Phase 1811):
  `range`'s pair mechanics with `dateTime`'s value conventions (an identical
  associated-value list to `dateTime`, reusing the existing `DateTimeVariant` —
  no new enum). In a filter context the pair binds ONE filter param, not two,
  which is the reason the case exists rather than two coordinated `dateTime`
  fields.
  """#,
  "union FormFieldKind.Range": #"""
  0.2.0 — the dual-thumb numeric range (absorbed the retired RangeFilter).
  """#,
  "union FormFieldKind.Rating": #"""
  Phase 1130 (§3.6.17) — a subjective score on a small ordinal scale. The
  line against `rangedNumber` is who the number belongs to: a rating is a
  judgement a person GIVES, a ranged number a measurement they REPORT.

  `max` is the case's only required member and is refused below 1 — a scale
  with no positions has nothing to draw and no keystroke that could change
  anything. `value` is a float even where nothing can type a fraction,
  because the commonest rating a reader sees is an AVERAGE arriving through
  a query. `allowHalf` governs ENTRY, never display.
  """#,
  "union FormFieldKind.Toggle": #"""
  The switch affordance: the same boolean slot as `checkbox`, a different control.
  """#,
  "union FormFieldKind.Tokens": #"""
  Phase 1121 (§3.6.19) — SEVERAL values accumulated as removable chips, over
  a suggestion set that may be open, searchable, asynchronous, or absent.

  Every member is optional, so `{"$type":"Tokens"}` is a complete document.
  `allowFreeText` omits at **`true`** — the OPPOSITE polarity to `combobox`,
  and the one thing about this case a host is most likely to get wrong:
  `combobox`'s option source is REQUIRED so "constrained" is its resting
  state, where `suggestions` is optional so "open" is this one's. The
  default follows the required-ness of the set.

  `value` is a `Binding<string list>` and the list is ORDERED — chips appear
  where the reader added them, so a host must not sort or de-duplicate it.
  """#,
  "union Format.DateTime": #"""
  Phase 1810 — `dateStyle` / `timeStyle` are BOTH optional: `timeStyle` alone
  is a time of day, both together a date-time. Phase 1811 — `dateTime` (was
  `date`): an honest name once it renders a time.
  """#,
  "union Format.Duration": #"""
  Phase 819 — the numeric source counts `unit`s, rendered per the bounded
  `style`.
  """#,
  "union Format.Since": #"""
  Phase 1533 — the elapsed-time rendition. Distinct from `relativeTime`:
  this one is a function of the HOST instant as well as of its source, so a
  host with no instant renders nothing rather than an invented delta.
  """#,
  "union MediaKind": #"""
  Which playback surface a `Media` node is — ONE kind, two variants, never two
  kinds. Everything a video surface and an audio surface SHARE is stated once
  on `MediaSpec`; only the slots that genuinely differ live here, and there
  are two of them, both on `Video`.

  **`Audio` has NO autoplay pathway — in the type, on the wire, or in the
  emission.** That is why this is an `enum` with associated values per case
  rather than a discriminator beside two optional fields: the case declares no
  such slot, so a renderer has nothing to branch on and cannot acquire one by
  a later edit. This is stronger than a default of `false` — a slot that
  defaults to off is one a document can switch on, and there is no document
  this format wants to be able to state in which a page begins making sound
  unbidden. A document carrying `{"$type":"Audio","autoplay":true}` decodes to
  an audio surface that does not autoplay, because the value has nowhere to
  land.
  """#,
  "union MediaKind.Audio": #"""
  The variant whose payload is the discriminator alone.
  """#,
  "union MediaKind.Video": #"""
  `autoplay` is a wire DECLARATION whose rendering is constrained: a host
  that honours it MUST pair it with muted playback. There is deliberately no
  separate `muted` slot on the wire — a second knob would be free to
  disagree with the first, and the only combination it would add is the one
  no host may render. `poster` is a second URL through the §19 floor, and a
  refused one is DROPPED rather than neutered (§3.6.6).
  """#,
  "union TextSource": #"""
  A text-producing position (§3.3). A bare wire string decodes to `.literal`
  (the §16 AI-ingest shorthand).
  """#,
]
