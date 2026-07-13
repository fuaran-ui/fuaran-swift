# CLAUDE.md — fuaran-swift (native Swift surface)

This repo is the **native Swift surface** of the Fuaran UI wire format — a render/authoring surface
**over the Rust reference core**, not a standalone conformant host. Its identity: the Rust core owns
truth + mutation via a C-ABI; the Swift side holds a **render projection** — a consumer-grade decoder
into native sealed types, held to a "decodes every corpus node fixture" bar, never a byte-parity bar
(it never canonically encodes).

This repo sits under the Fuaran-UI sub-estate at `../`, alongside the other reference-implementation
tiers. Cross-repo conventions (the formatting mandate, the language-baseline pinning, the OSS
publication boundary, Sync All, port allocation) live in the workspace `CLAUDE.md`
(`../../../CLAUDE.md`) and the Fuaran-UI sub-estate `CLAUDE.md` (`../CLAUDE.md`). Read those first.

## Posture

- **Apache 2.0 from day one** — same posture as the other public reference tiers.
- **Surface over the Rust reference core, not a transpile and not a sixth host.** Public docs say
  "native Swift surface … over the Rust reference core", never "conformant host". The Swift side is a
  render projection: it decodes the canonical tree JSON the core hands back and models it as native
  sealed types for rendering; it does not canonically encode, so there is **no §11 byte-parity leg**.
- **Wire-format fidelity is the decode contract.** The decoder parses every node fixture in the
  shared `../wire-format-fixtures/` corpus into the sealed model with a compile-time-exhaustive
  `switch`; a new wire kind that misses an arm is a **build error**, not a silent fallback.

## Language baseline

Swift 6 (`swift-tools-version:6.0`, Swift 6 language mode / strict concurrency). Model the closed
wire DUs (`NodeKind`, the `Spec` families, `Binding`, `Action`, `TextSource`, …) as native `enum`s
with associated values — one case per wire `$type` — and lean on the compiler: the exhaustive
`NodeKind.typeName` / `NodeKind.category` switches (no `default` arm) are the guard that a new kind
cannot slip in unhandled.

## Layout

```
fuaran-swift/
├── Sources/FuaranUI/
│   ├── Vocabulary.swift          # bare-string wire enums (String-raw, rawValue == wire spelling)
│   ├── JSON.swift                # portable JSON value + hand parser + FuaranDecodeError
│   ├── Bindings.swift            # TextSource / Binding / Action / dataframe compute layer
│   ├── Specs.swift               # per-kind spec records + Drawing vector-graphics vocabulary
│   ├── Node.swift                # Node envelope + closed NodeKind (+ exhaustive typeName/category)
│   └── RenderProjection*.swift   # the render-projection decoder (canonical tree JSON → sealed model)
├── Tests/FuaranUITests/
│   ├── CorpusTests.swift         # corpus render-coverage harness (per-kind coverage report)
│   └── ModelTests.swift          # focused decode checks (corpus-independent)
├── Package.swift
├── run.ps1                       # Stage-0 entry point
├── LICENSE / README.md / CLAUDE.md
```

## Build / verify pipeline

```powershell
.\run.ps1                 # swift build + swift test
.\run.ps1 -SkipTests      # switches: -SkipFormat-equivalent is deferred (see Formatting); -SkipBuild / -SkipTests
```

Or drive SwiftPM directly: `swift build`, `swift test`.

**Windows toolchain note.** Swift-on-Windows links through the MSVC toolchain, so `swift build` /
`swift test` need `link.exe` (Visual Studio Build Tools) on `PATH` and `SDKROOT` pointing at the
Swift Windows SDK. `run.ps1` imports both best-effort (from the VS `vcvars64` environment and the
`SDKROOT` user variable) and **skips cleanly** when the Swift toolchain or the MSVC linker is absent,
so a machine without them stays green. The reference target is macOS.

## Formatting

`swift-format` ships with the Swift 6 toolchain. Formatting-as-a-gate is **deferred** for the
bootstrap (not yet wired into `run.ps1`); when adopted it maps the workspace formatting mandate
(Fantomas for F#, rustfmt for Rust, …) to `swift-format` over the changed `.swift` files.

## Wire format

The canonical wire format is owned by the F# tier (`../fuaran/docs/WIRE_FORMAT.md`) with the
workspace-level `../wire-format-fixtures/` corpus as the executable conformance suite. `fuaran-swift`
is a **decode-only render projection** of that format: `RenderProjection.decodeNode` parses a
canonical `Node` document into the sealed Swift model. The **forward-coupling rule** (`WIRE_FORMAT.md`
§11) means a new `NodeKind` / `Spec` / `Binding` / `Action` case moves every host — the Swift model +
decoder + the corpus render-coverage harness are updated in the same change here.

### Corpus render-coverage

`Tests/FuaranUITests/CorpusTests.swift` locates `../wire-format-fixtures/` via `manifest.json` and
decodes every `node`-decoder fixture (node-round-trip + lenient-accept shorthand) into the sealed
model; a decode throw is a hard failure (that is the "zero fallback-arm hits" bar). Coverage is
reported per `NodeKind`. The harness skips cleanly when the corpus is absent (standalone checkout).

## Native C-ABI session binding (FuaranCore + FuaranSession)

The certified Rust reference core is wired under the Swift surface through a C-ABI:

- **`Sources/FuaranCore/`** — a C target that is a **header shim** over the vendored `fuaran.h` (a
  byte-copy of the Rust host's hand-written header, synced on change). It exposes the C surface to
  Swift as an importable `FuaranCore` module; the concrete symbols resolve at link time from the Rust
  reference core's native **staticlib** (`fuaran_rs.lib` / `libfuaran_rs.a`) — or, on Apple platforms,
  the `FuaranCore.xcframework` binary target.
- **`Sources/FuaranUI/Session.swift`** — the **`FuaranSession` Swift `actor`**. The C header declares
  a session **single-owner**: confine the handle and every call taking it to one executor for its
  lifetime. The actor expresses that by construction — every method is actor-isolated, so no two
  calls touch the raw pointer concurrently, and the pointer never escapes. The raw pointer is stored
  as its `UInt` bit pattern (a `Sendable` value) so the nonisolated `deinit` can free it exactly once
  under Swift 6 strict concurrency. Each method is a single synchronous C-call sequence with no
  internal suspension, so `fuaran_last_error` (a per-thread slot) is read on the same call that saw
  the failing `fuaran_session_new`. (A dedicated pinned serial executor is the stricter option if
  thread-affinity is ever required; the actor's serialization is the contract's load-bearing
  guarantee.)
- **Buffer ownership** follows the header exactly: input buffers are passed straight from a Swift byte
  array (`withUnsafeBufferPointer`, valid for the borrowed call — Rust never frees an input); output
  `FuaranBuf`s are copied into a Swift `String` honouring `len` (no trailing NUL) then freed with
  `fuaran_dealloc`, exactly once. Errors surface as a thrown **`FuaranError`** carrying the canonical
  code + message (+ `class`/`path`/`batchIndex`) — from the `fuaran_last_error` envelope on an open
  failure, or the `{"error":{…}}` operation envelope on an apply/decode failure; no silent-nil paths.

**Package wiring (conditional).** `Package.swift` detects the staticlib (an explicit
`FUARAN_RS_STATICLIB_DIR`, else the sibling `../fuaran-rs/target/debug`). When present it adds the
`FuaranCore` target, makes `FuaranUI` depend on it, sets the `FUARAN_CORE_AVAILABLE` compile flag, and
adds the link flags (`-L<dir> -lfuaran_rs` + the Windows system libs `kernel32 ntdll userenv ws2_32
dbghelp`). When absent the package is the pure-Swift Phase-538 projection: `Session.swift` compiles to
nothing (its body is under `#if FUARAN_CORE_AVAILABLE`) and `SessionTests` skips. `run.ps1`
best-effort builds the staticlib from `../fuaran-rs` before the Swift build.

**XCFramework packaging is a macOS-only leg.** Assembling `FuaranCore.xcframework` from the Apple
build legs (`aarch64-apple-ios{,-sim}`, `aarch64-apple-darwin`) requires **`xcodebuild`** and is
macOS-only; `run.ps1 -Package` **skips cleanly** with a named message on any other platform (mirroring
how the sibling Rust host skips its Apple build legs). On Windows/Linux the **same C surface links the
staticlib directly**, which is how the Swift↔C-ABI binding is exercised end-to-end off an Apple box
(`SessionTests` seeds a session → applies a `TreeOp` → reads `tree_json` → re-projects with the
Phase-538 decoder).

## Cross-repo dependencies

The pure-Swift `FuaranUI` render projection has no upstream dependency on any other sibling. At test
time it reads the workspace-relative corpus at `../wire-format-fixtures/` (skipped when absent, so the
repo is standalone-testable). The C-ABI session leg links the Rust reference core's native staticlib
built from the sibling `../fuaran-rs/` (skipped when that staticlib is absent).

## Public vocabulary discipline

`fuaran-swift` is OSS-public (Apache 2.0). Per the workspace OSS publication boundary, **shipped
artefacts** (source, README, package metadata, comments) reference only "the Fuaran UI wire format"
generically — never a private sibling / package name, a commercial product name, or a
strategic-command name. This `CLAUDE.md` lives in the public repo, so it observes the same boundary.
