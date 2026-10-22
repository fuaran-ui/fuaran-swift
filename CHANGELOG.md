# Changelog

Changes to the public surface of `fuaran-swift`, newest first. The library is pre-1.0; each
entry says whether it is additive, a behaviour change, or a break.

## Unreleased

### Changed (Phase 2411: the corpus pin moves to `8b71a3e`, past Phases 1962, 2300 rule 1, 2206 and 2286)

- **Break (source):** `SelectSpec.value` is `Binding?`. A single-select carries `value` and a
  multi-select carries `values` and no `value` (Phase 1962): a single-select without `value` is
  refused (`MISSING_FIELD` at `$.kind.value`), and a `value` on a multi-select is read and dropped.
  A consumer that read `value` as non-null handles `nil`.
- **Behaviour (accept set widens):** sixteen members are omitted at their declared default and the
  decoder restores the default when absent (Phase 2300, rule 1): `Flex.wrap` (and the legacy
  `Stack.wrap`), `Link.download`, `List.ordered`, `CodeBlock.lineNumbers`, `FormField.required`,
  `FileUpload.multiple` (`false`); `CodeBlock.copyable`, `Modal.dismissable` (`true`);
  `CodeBlock.highlightLines` (empty); `Heading.variant` (`Standard`), `Image.variant`
  (`Default`), `Badge.variant` (`Neutral`), `Button.variant` (`Secondary`); `Stepper.activeStep`
  (`Static 0`). The explicit forms are still read. The generated model is regenerated from the
  corpus IDL.
- **Additive:** `ColumnType` gains `timestampMs`, `timestampUs` and `timestampNs`
  (`timestamp_ms` / `_us` / `_ns`, WIRE_FORMAT §3.6.25, Phase 2206) and a `timestampDigits`
  accessor. A timestamp cell of any unit is read only as canonical instant text no finer than the
  unit, or as a whole epoch number below 9e15 in magnitude read in the column's unit; anything
  else, and an instant outside the years 0000-9999, is `WRONG_TYPE` at the Transform's source.
  Fractional text in a `timestamp` column, previously held as written, is now refused.
- **Behaviour (accept set narrows):** the JSON reader refuses, as `INVALID_JSON`, an overflowing
  exponent (`1e999`) and an integer token past 2^53 that is not the canonical float layout of the
  double it reads as (`9007199254740993`) — WIRE_FORMAT §20.2 row 7 and §2 rule 5, amended
  (Phase 2286). `1e999` in an integer slot was `WRONG_TYPE` at the slot; it is now refused by the
  parse. Phase 2286's depth-breach path moves only the repair family's answer, which this
  decode-only surface does not run.

### Added (additive)

- Phase 2331: every field of every node kind and record in the wire IDL is now carried by the
  model. New optional stored properties (each defaults to `nil`, or `false` for `reorderable`,
  in the memberwise initialiser, so existing construction compiles unchanged):
  - `ChartSpec`: `valueFormat: Format?`, `xTitle`, `yTitle`, `subtitle: TextSource?`,
    `legendPosition: ChartLegendPosition?`, `dataLabels: ChartDataLabels?`,
    `xScale: ChartXScale?`.
  - `GridSpec`: `reorderable: Bool`, `windowStateKey: String?`, `rowTotal: Binding?`.
  - `ColumnErased`: `sortable: Bool?`, `editable: Bool?`.
  - `FileUploadSpec.onSelect`, `StepperSpec.onSelect`, `MountSpec.onBubble`: `Closure?`.
  - `ModalSpec.anchor: String?`.
  - New public enums `ChartLegendPosition`, `ChartDataLabels` and `ChartXScale`.

  What the SwiftUI floor does not yet paint is listed under "Carried but not rendered" in
  `docs/RENDER-PROJECTION.md`.

### Changed (mechanism, same verdicts)

- Phase 2331: each union decoder dispatches over the union's generated tag set with an
  exhaustive `switch`, so a case the wire IDL gains is a build error rather than a run-time
  refusal. An unknown `$type` is still refused with `UNKNOWN_DU_CASE` at `<path>.$type`; the
  message's list of expected tags is now the generated set.
- Phase 2331: the test suites locate the corpus through one shared locator,
  `FUARAN_WIRE_FIXTURES` first.
