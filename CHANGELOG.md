# Changelog

Changes to the public surface of `fuaran-swift`, newest first. The library is pre-1.0; each
entry says whether it is additive, a behaviour change, or a break.

## Unreleased

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
