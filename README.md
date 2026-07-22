# fuaran-swift

The **native Swift surface** of the [Fuaran UI wire format](../fuaran/docs/WIRE_FORMAT.md) — a
render/authoring surface over the Rust reference core. Apache-2.0.

`fuaran-swift` is **not** a standalone conformant host. The Rust reference core owns truth and
mutation (decode, apply tree-ops, render) behind a C-ABI; the Swift side holds a **render
projection** — a consumer-grade decoder that parses the core's canonical tree JSON into native
sealed Swift types (`NodeKind`, `Spec` families, `Binding`, `Action`, … as `enum`s with associated
values) for rendering. It never canonically *encodes*, so there is no byte-parity contract; the bar
is that it decodes every node fixture in the shared conformance corpus into the sealed model with a
compile-time-exhaustive `switch` — a new wire kind is a build error, never a silent fallback.

## Layout

```
fuaran-swift/
├── Sources/FuaranUI/          # sealed tree model + the render-projection decoder (pure Swift)
│   ├── Vocabulary.swift        #   the bare-string wire enums
│   ├── JSON.swift              #   a small portable JSON value + parser + decode-error type
│   ├── Bindings.swift          #   TextSource / Binding / Action / the dataframe compute layer
│   ├── Specs.swift             #   the per-kind spec records (display / input / vis / layout / drawing / structural)
│   ├── Node.swift              #   the Node envelope + the closed NodeKind vocabulary
│   └── RenderProjection*.swift #   the decoder (canonical tree JSON → sealed model)
├── Tests/FuaranUITests/        # corpus render-coverage harness + focused model tests
├── Package.swift
├── run.ps1                     # Stage-0 entry point (swift build + swift test)
└── LICENSE                     # Apache-2.0
```

## Build & test

```powershell
pwsh ./run.ps1                 # swift build + swift test
pwsh ./run.ps1 -SkipBuild      # switches: -SkipBuild / -SkipTests
```

Or drive SwiftPM directly: `swift build`, `swift test`. The reference toolchain is Swift 6 on macOS;
the build is portable to a correctly-configured Swift-on-Windows toolchain.

## Status

- **Sealed tree model + render-projection decoder** — the full current node vocabulary on the 0.2.x
  canonical wire (bare-string literals, the `Metric`/`LabelValueRow` `value` rename, the `Fact`
  kind, the unified filter chips over `FormFieldKind` incl. the dual-thumb `Range`,
  omit-when-default stylistic fields, `Selection.defaultValue`/`.field`, keyed `DrawStyle.markId`,
  and the lenient-ingest coercions — field/enum aliases, bare scalars in binding slots, schemaless
  embedded frames, epoch timestamps, flat compute spellings). Certified by a corpus
  render-coverage harness: every node fixture (node-round-trip + lenient-accept) decodes into the
  sealed model, coverage reported per kind.
- **C-ABI session binding** — the `FuaranSession` Swift actor over the Rust reference core's native
  staticlib (or the `FuaranCore.xcframework` on Apple platforms); session tests drive
  seed → apply-op → re-project end-to-end when the core is linked.
- **SwiftUI renderer floor + interaction round-trip + server-driven driver** — the exhaustive
  `FuaranNode` dispatch spine, the tone bridge, the `FuaranHost` interaction loop, and the
  transport-agnostic driver (SwiftUI legs compile on Apple platforms; the pure layers build
  everywhere).

## Licence

Apache-2.0. See [LICENSE](LICENSE).
