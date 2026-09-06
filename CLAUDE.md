# CLAUDE.md — fuaran-swift (native Swift surface)

This repo is the **native Swift surface** of the Fuaran UI wire format — a render/authoring surface
**over the Rust reference core**, not a standalone conformant host. Its identity: the Rust core owns
truth + mutation via a C-ABI; the Swift side holds a **render projection** — a consumer-grade decoder
into native sealed types, held to a "decodes every corpus node fixture" bar, never a byte-parity bar
(it never canonically encodes).

This repo sits alongside the other Fuaran reference-implementation tiers. Cross-repo development conventions (port allocation, formatting, language-baseline pinning) live at the maintainers' workspace level and are not shipped here.

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
├── Sources/FuaranUIRenderer/
│   ├── MediaPlayback.swift       # the media playback projection (the six §3.6.6 obligations)
│   ├── ImagePresentation.swift   # the image presentation projection (§3.6.2–§3.6.5)
│   ├── EmbedPresentation.swift   # the embed frame projection (§3.6.8 + the §19.1 egress class)
│   ├── TreeProjection.swift      # the tree row projection (the eight §3.6.12 obligations)
│   ├── TooltipProjection.swift   # the tooltip trait projection (§3.1)
│   ├── SparklineLowering.swift   # the sparkline → Drawing lowering (the shared goldens)
│   └── …                         # Accessibility / TrendSentiment / FuaranNode / Theme / Drawing*
├── Tests/FuaranUITests/
│   ├── CorpusTests.swift         # corpus render-coverage harness (per-kind coverage report)
│   ├── MediaVocabularyTests.swift  # the media-wave decode leg, corpus-independent
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

The canonical wire format is owned by the F# tier (`../fuaran-dotnet/docs/WIRE_FORMAT.md`) with the
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

### Corpus REJECT leg — the negative half of the same contract

The same file runs every `node`-decoder **reject** fixture and requires each to fail with the
corpus's canonical code and a `$`-rooted path carrying the expected **prefix** (a discriminator
refusal legitimately reports at `<path>.$type` where the corpus records `<path>`, so equality would
fail a correct message; the reference host's own reject leg matches by prefix for the same reason).
A decode that SUCCEEDS is the hard failure.

Two exclusions, both documented in the test and neither a filter over the family: `decoder == "op"`
fixtures have no decoder here at all (the core owns apply; a render projection never sees a
`TreeOp`), and the `envelope-reject` family asserts `FOREIGN_PROFILE` — versioning-envelope
negotiation, a codec-host obligation this decode-only surface does not carry.

**Forward-coupling rule.** A new host-opaque payload slot (`SetState.value`-shaped: held raw,
never interpreted) goes through `Decode.jval` / `Decode.jvalMap`, which refuse an explicit `null`.
The wire spells absence by omitting a key, so a `null` in a payload slot is malformed; reading it
raw would hand the embedding app a slot that claims to carry a value and does not.

### The URL safety floor (`Sources/FuaranUI/UrlPolicy.swift`)

`FuaranUrlPolicy` + the `sanitizedHref` / `sanitizedSrc` / `sanitizedNavigateRoute` accessors are
the surface's answer to "who checks the destination". **Chosen posture: a public accessor, not a
decode-time filter** — `href` / `src` are `Binding`s whose value may not exist until the core
resolves a `State` / `Query` / `Format` slot, so a decode-time allowlist would be checking a
placeholder, and filtering during decode would also stop the projection being a faithful view of
the wire. The consumer obligations are stated in the README's "Safety floor" section; keep them
there (they are what a consumer reads) rather than only here.

**Six positions, not one.** `Link.href`, `Image.src`, `Media.src`, the `Video` variant's `poster`,
every `Image.srcSet` candidate and every `Media.tracks` entry's `src` all reach the floor, and all
but the first are worth naming: they are fetched with **no user act at all**, so a slot of that
shape that skipped the floor would be a documented way around it. Accessors exist for each
(`sanitizedSrc` on `MediaSpec`, `SrcSetEntry` and `TrackEntry`, `sanitizedPoster` on `MediaSpec`),
and what a refusal *costs* differs per position — see "Image presentation" and "Media playback"
above.

**`Embed.src` is a SEVENTH position and does NOT ride that floor.** §19.1 gives it its own, narrower
class, because everything else here is fetch-and-display or navigate-on-a-click and an embed is
fetch-and-**execute**. `FuaranUrlPolicy.sanitizeEmbed` accepts `https` and nothing else — refusing
`http` (a document any intermediary can rewrite becomes that intermediary's script in a frame this
page created) and refusing a **schemeless** reference (a same-origin frame is exactly where a
document granted both `AllowSameOrigin` and `AllowScripts` can reach its own frame element and remove
the sandbox from it). `EmbedSpec.sanitizedSrc` is the accessor; naming the class matters beyond the
scheme set, because a composition that declared an origin for image egress has said nothing about
which DOCUMENTS it is willing to run.

A renderer arm that ever *does* resolve a URL onward — a real image loader, a tappable link — must
route it through `FuaranUrlPolicy.sanitize` in the same change that adds it. This is the same
shape as the Phase-667 write-back rule below, and for the same reason: the compiler forces the arm
to exist, it cannot force the arm to check.

## Native C-ABI session binding (FuaranCore + FuaranSession)

The certified Rust reference core is wired under the Swift surface through a C-ABI:

- **`Sources/FuaranCore/`** — a C target that is a **header shim** over `include/fuaran.h`, a
  **generated byte-copy** of the Rust host's hand-written header. It exposes the C surface to Swift
  as an importable `FuaranCore` module; the concrete symbols resolve at link time from the Rust
  reference core's native **staticlib** (`fuaran_rs.lib` / `libfuaran_rs.a`) on every platform.
  **The copy is GATED, not merely "synced on change"** — `run.ps1` and the `swift-core` CI job (the
  only one with both repositories checked out) byte-compare it against the reference and fail on
  drift, reporting NOT CHECKED when no sibling checkout is present. It had drifted 56 lines behind,
  missing a whole family of session verbs, with every gate green throughout — which is what a
  discipline with no check attached looks like from the outside.
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

**There is no XCFramework packaging, and the claim that there was is removed.** `run.ps1 -Package`
and a `workflow_dispatch` CI job of the same name both reported success while assembling nothing:
off macOS the switch skipped, and on macOS it printed a note saying the implementation lived
elsewhere. Three artefacts cited an xcframework and none produced one. Both the switch and the job
are gone rather than left green — a passing check for an absent capability is worse than no check,
because it is the thing everything downstream cites.

**What is true today:** the same C surface links the staticlib directly on every platform, which is
how the Swift↔C-ABI binding is exercised end-to-end on and off an Apple box (`SessionTests` seeds a
session → applies a `TreeOp` → reads `tree_json` → re-projects with the Phase-538 decoder). An SPM
consumer therefore reaches the pure-Swift projection and NOT `FuaranSession`. Closing that means a
`binaryTarget`, a real assembly step, and a CI job that FAILS unless an artefact is produced — all
three together, since any two of them leave the same gap.

## Control write-back — a forward-coupling rule (Phase 667)

A value-carrying control arm in `FuaranNode.swift` must, **in the same change that adds it**,
either commit through `stateKeyOf(value)` + `FuaranHost.writeBack`, or be `.disabled(true)` over
a `.constant` binding and be listed in the write-back audit comment on `RenderFormField`.

**Why this needs a written rule.** The renderer dispatches over a sealed tree, so the compiler
forces a new arm to EXIST but cannot force it to WRITE. Today `.text` / `.number` / `.checkbox`
are wired and the rest are inert by construction — `.combobox` included, which landed on `.choice`'s
own control because the two ARE the same value contract. That is a render floor, not a defect, because
a disabled control drops no input. The failure mode to avoid is a *live* control that quietly
fails to commit; the sibling Kotlin host shipped exactly that in five arms (Phase 667).

## Trend sentiment projection — `tone` and `trendPolarity` are not the same judgement

`Metric` carries two slots that both look like judgements about a number, and `WIRE_FORMAT.md`
§3.6.1 exists because they are not. **`tone` says how the reading STANDS and colours the TILE;
`trendPolarity` says which way the quantity IMPROVES and reaches the TREND element alone.** A host
derives neither from the other. The projection lives in
`Sources/FuaranUIRenderer/TrendSentiment.swift`; the decisions are here.

- **Sentiment is `sign(trend) × polarity`** — `HigherIsBetter` is `+1`, `LowerIsBetter` is `−1`. A
  falling −7.34% reads as an *improvement* under `LowerIsBetter`, and the numeric text — its sign
  included — is identical either way. Polarity changes how the number READS, never what it SAYS.
- **Nothing writes back to `tone`.** A surface that inferred "improving ⇒ tile is Success" would
  re-create in the render the exact conflation the wire slot exists to remove, and would override an
  emitter's deliberate `Critical` on a metric improving from a bad place. There is no path from
  `TrendSentiment.swift` to a `ToneVariant`, by construction rather than by discipline.
- **The structural intent transfers from the reference tiers; their CSS constraint does not.** Those
  tiers emit `fuaran-metric-trend-{improving,regressing,unchanged}` class modifiers plus a glyph
  carrying an `aria-label`. SwiftUI has no class vocabulary, so what crosses is the PAIR — a
  sentiment and a non-colour channel for it — projected into this platform's idiom: a
  `foregroundStyle` drawn from the tone palette *by sentiment* (never from the node's `tone`), and
  an `.accessibilityLabel` on the glyph. Colour alone fails WCAG 1.4.1, so the glyph is not
  decoration; §3.6.1 makes discharging that obligation non-optional while leaving HOW to the surface.
- **The label is on the GLYPH, not the trend view.** On the view it would OVERRIDE the element's
  text and assistive technology would hear "improving" and lose the number. The reference tiers
  place it the same way and record the same reason.
- **`Neutral` is reserved by the specification and is deliberately NOT a case** of `TrendPolarity`.
  The case set IS the accepted wire set, so `"Neutral"` fails `UNKNOWN_DU_CASE` naming the two legal
  spellings rather than this surface quietly deciding a question the reservation holds open — and no
  `switch` carries a dead arm waiting for a case the wire will not produce. No alias arm is
  registered: the obvious candidates (`Neutral`, `Inverted`, `Descending`) are precisely the
  spellings that must not be accepted.
- **An unparseable resolved trend yields NO sentiment**, matching the reference renderers' unresolved
  branch (an unclassed trend element, no glyph). Inventing one would be a claim about a number
  nobody has.

**Forward-coupling.** A change to the composition rule, the sentiment set, or the glyph vocabulary
updates this table, `TrendSentiment.swift`, and
`Tests/FuaranUIRendererTests/TrendSentimentTests.swift` in the same change. As with the
accessibility projection, the decisions sit **outside** `#if canImport(SwiftUI)` so they are
asserted on every platform — only the colour half is Apple-gated.

## Media playback — three obligations the wire states NORMATIVELY

`Media` (§3.6.6) is one kind with a `MediaKind` variant (`Video` carrying `autoplay` + an optional
`poster`, `Audio` carrying neither). Three of its rules are **normative render obligations**, not
defaults a surface may choose differently, and each is one a surface would get wrong while
round-tripping the bytes perfectly. The projection is
`Sources/FuaranUIRenderer/MediaPlayback.swift`; the decisions are here.

- **The accessible name, ALWAYS.** `label` is mandatory on the wire and a transport has no
  decorative case, so unlike `Image`'s `alt` there is no branch. **What there IS is a precedence:**
  a node-level `Accessibility.label` wins, because it is the author naming this instance something
  else. On this surface that falls out of the render spine — `fuaranNodeBody` applies the node
  projection *after* the kind arm, and a later `.accessibilityLabel` replaces an earlier one — so
  the arm applies the spec label unconditionally and the trait overrides it. The reference host
  reaches the same precedence by the *opposite* mechanism (it serialises attributes to text, where a
  duplicate resolves FIRST-wins, so it emits the spec label only when the node-level attributes
  carry none). **Do not port that host's conditional here**: suppressing the label when a trait is
  present would invert the precedence on SwiftUI rather than preserve it.
- **`autoplay` never without muted, in BOTH directions.** `MediaPlaybackPlan.muted` is a *computed*
  property returning `autoplay`, so the failing combination is unrepresentable rather than asserted
  — the same argument the wire makes for carrying no `muted` slot, applied to the type. Muting a
  video the reader pressed play on is the same defect in the other direction, which is why the
  property is derived rather than merely defaulted.
- **`Audio` has NO autoplay pathway**, and the guarantee is the CASE SET: `MediaKind.audio` carries
  no associated value, so a document's `{"$type":"Audio","autoplay":true}` decodes to an audio
  surface that does not autoplay because the value has nowhere to land — and the plan builder's
  `.audio` branch has nothing to read, so no later edit *there* can start honouring it. Note the
  document is not refused: the slot does not exist on that variant, its presence is not malformed.
  `MediaPlaybackPlan` has no public initialiser for the same reason — a memberwise init would let a
  caller hand `autoplay: true` to an audio plan, re-opening by an initialiser what the sealed enum
  closes by its cases.

### Text tracks and the transcript — three more, all about the element's CHILDREN

Phase 1110 added `tracks` and `transcript` to the same spec, and three obligations with them. All
three are ones a surface gets wrong while round-tripping the bytes perfectly, and all three are
discharged in `mediaPlaybackPlan` / `mediaTrackPlans`.

- **Authored order is PRESERVED, and it is the OPPOSITE of `srcSet`'s rule.** The two are not an
  inconsistency: a browser picks ONE candidate from a srcset by an algorithm, so ordering it is
  canonicalisation, while a reader picks a track from a menu the user agent builds in DOCUMENT
  order, so ordering it would be rewriting someone else's menu. They live in two files precisely so
  neither can be "fixed" into the other, and the checker asserts the neighbour still sorts — a
  change that unified them would otherwise satisfy both obligations while breaking one.
- **At most one `default` per KIND, first election wins — resolved at RENDER, not at decode.** A
  document electing two default captions tracks is legal bytes: the decoder does not refuse it,
  because a lenient host would render it anyway and HTML leaves the case undefined. So the wire keeps
  both elections and `MediaTrackPlan.isDefault` carries the resolved one. The later track is still
  emitted; only its claim on the menu is dropped. The election is per kind, so a captions default and
  a subtitles default coexist.
- **A refused track source DROPS the track**, taking the POSTER's disposition rather than the primary
  source's: an element must have a source, but it need not have this track. Flooring runs BEFORE the
  election, so a refused track never occupies a kind's default slot on its way out — the `srcSet`
  rule, at the one place where the consequence is visible.

**The transcript is a PEER field of the plan, never a member of `tracks`, and that is this surface's
whole statement of the beside-not-inside obligation.** `<video>` and `<audio>` admit only source-ish
children, so a transcript placed there would be fallback content a browser never shows — which is why
the reference emission gains a wrapper for it. On a surface with no document, "beside" is exactly two
sibling fields of one plan, so an arm that renders `tracks` as children cannot render the transcript
among them. It carries the MEDIA's resolved label as its own accessible name, because the wire gives
it no label of its own and a reader meeting the disclosure out of context must be told which
recording it transcribes. A transcript resolving to whitespace is NO transcript: advertising a
disclosure that opens onto nothing is the tooltip's obligation-5 shape one kind over.

**Forward-coupling.** A third `MediaKind` variant, a change to the pairing rule, a fifth `TrackKind`,
a change to the election or ordering rules, or a new `MediaSpec` slot updates this section,
`MediaPlayback.swift`, the render arm in `FuaranNode.swift`, and
`Tests/FuaranUIRendererTests/MediaPlaybackTests.swift` in the same change. The projection sits
**outside** `#if canImport(SwiftUI)` so the obligations are asserted on every platform; only the
view application is Apple-gated.

**The render-leg boundary, stated honestly.** The SwiftUI floor has **no player** — the arm is a
labelled transport placeholder reporting the declarations it would honour. That boundary is smaller
than it looks: the obligations are decisions about what a surface *may* do, all three are
discharged in the plan, and all three are asserted on every platform. What waits is the playback
element (an `AVPlayer`-backed arm), not the contract. The arm that gains one reads `plan.muted`
wherever it states muting and inherits the pairing unchanged.

## Image presentation — the two orders, and what a refusal costs

`ImageSpec` carries six slots past `variant` (§3.6.2–§3.6.5). The projection is
`Sources/FuaranUIRenderer/ImagePresentation.swift`; four decisions live here.

- **There are TWO orders for `srcSet`, and they are different orders.** The wire preserves
  **authored** order — canonicalisation sorts object keys and never array elements, so a codec that
  sorted would emit bytes differing from what it decoded. The **renderer** presents ascending by
  width so its output is canonical for a given tree. Both are true because the sort lives in
  `imagePresentationPlan` and never in the decoder. The corpus fixture is authored *descending*
  precisely so a host that conflated them fails.
- **A refused candidate is dropped; a refused primary source is not.** The primary must exist, so it
  collapses to a refusal state the arm renders. A candidate has no such obligation, and offering a
  client a rendition guaranteed to fail is worse than offering it one fewer. Flooring happens
  *before* the ordering, so a refused candidate never occupies a position.
- **`expandable` over a refused `src` emits NO affordance.** The same rule turned on the anchor: a
  link to nothing is a dead control. The plan therefore carries `expansion: String?` *and*
  `expansionRefused: Bool`, because "no expansion declared" and "expansion declared over a refused
  source" are different facts and an `expansion == nil` test alone cannot tell them apart. The
  target is the **primary** source, never a candidate — a surface that put a thumbnail behind the
  link would pass every structural check and defeat the feature.
- **`aspectRatio` reserves a box; `fit` decides what happens to pixels that do not match it.**
  Independent by contract, neither derived from the other, so they project as two values rather than
  one content mode. The reservation is a *layout-pass* obligation here — settled without script,
  hydration or a loaded image — which is this platform's form of the CSS-only obligation §3.6.2
  states, and it is testable today even though the picture is not.

**One slot is carried and NOT acted on: `loading`.** The floor has no network image loader, so there
is no fetch to defer, and a surface claiming to honour `Lazy` would be claiming something it does
not do. It is projected rather than dropped so the arm that gains a loader inherits the declaration
instead of rediscovering the slot. `Eager` is not the unoptimised value — deferring an above-the-fold
image delays first paint rather than helping it — so a loader arriving here must not infer laziness
from position or viewport.

**Forward-coupling.** A new `ImageSpec` slot, a change to either order, or a change to what a
refusal costs on any of the four URL positions updates this section, `ImagePresentation.swift`, the
arm in `FuaranNode.swift`, and `Tests/FuaranUIRendererTests/ImagePresentationTests.swift` in the
same change.

## Accessibility projection — the mapping, and what is dropped

A node's `Accessibility` trait carries six slots. The HTML render tiers project them into `aria-*`
attributes; a SwiftUI surface has no attribute bag, so the projection is a mapping onto
accessibility **modifiers** — and the two vocabularies do not correspond one-for-one. The mapping
lives in `Sources/FuaranUIRenderer/Accessibility.swift`; the decision is here.

| slot | SwiftUI |
|---|---|
| `label` | `.accessibilityLabel(Text(…))`, resolved through the binding; an empty resolved label is dropped |
| `labelledBy` | **no mapping** — dropped, reported |
| `describedBy` | **no mapping** — dropped, reported |
| `role` | `.accessibilityAddTraits` for `button` → `.isButton`, `link` → `.isLink`, `heading` → `.isHeader`; every other token **dropped, reported** |
| `liveRegion` | `polite` / `assertive` → `.accessibilityAddTraits(.updatesFrequently)` (**partial**); `off` → nothing (an exact mapping — `off` is the platform default) |
| `hidden` | `.accessibilityHidden(true)` when the binding resolves true |

**An unmappable slot is DROPPED, never refused — and never silently.** Two halves, and both are
load-bearing:

*Never refused.* A render surface does not reject a tree the wire declares valid. Refusing would
fork the vocabulary by platform — the same tree would render on one surface and fail on another —
and it would make an author's `aria-describedby` a portability hazard rather than a hint. The
model's own posture already says this ("carried best-effort for the render projection").

*Never silently.* Silence is the defect this closed: the trait decoded into the model and was
dropped on the floor, with nothing in the tree recording that a question had been asked. So the
projection **returns its drop set** (`AccessibilityProjection.unmapped`, in wire-slot order), the
tests assert it slot by slot, and this table enumerates it. A slot that becomes mappable moves from
one list to the other and the assertion goes red until both are updated — which is what makes the
drop set a decision rather than an omission.

**Placement is by construction, not by convention.** The reference host decides which element
carries the projection (`../fuaran-dotnet/docs/DECISIONS.md`, D4: the node's semantic element, not
its wrapper `<div>`). A SwiftUI surface has no wrapper — `fuaranNodeKindBody` returns exactly the
view the kind arm renders — so the node's own view IS the semantic element, and there is one
emission site (`fuaranNodeBody`) with no second place to get it wrong.

**Two approximations were declined**, and are worth stating so they are not re-proposed as
improvements: `role: "tab"` as `.isButton` (VoiceOver would announce "button", which is a
mis-statement, not a partial one) and `role: "dialog"` as `.isModal` (`.isModal` is `aria-modal` —
"ignore my siblings" — a different assertion from `role="dialog"`). Compose maps `tab` genuinely
(`Role.Tab`), so the two native surfaces have **different drop sets** by design; neither is the
other's parity target, and the reference `aria-*` projection is what both answer to.

**Forward-coupling.** A new slot on the wire trait, or a new `AriaRole` token, updates the mapping
table above, `semanticTrait(forRole:)`, and the drop-set assertions in
`Tests/FuaranUIRendererTests/AccessibilityProjectionTests.swift` in the same change. The mapping is
deliberately **outside** `#if canImport(SwiftUI)` so those assertions run on every platform — a
decision testable on only one platform is a decision nobody re-checks.

## Embed — a slot that EXECUTES, and what that changes

`Embed` (§3.6.8) is a Display kind carrying a document URL, a mandatory title, an optional aspect
ratio and a closed list of sandbox relaxations that is EMPTY by default. The projection is
`Sources/FuaranUIRenderer/EmbedPresentation.swift`; three decisions live here.

- **A KIND, not a `Mount` variant.** `Mount` composes a COOPERATING guest — a scope id, a declared
  message channel, a capability request list — and a third-party page has none of those and cannot
  acquire them. It is equally not a `Media` variant: `Media` fetches an asset and DISPLAYS it,
  decoded into no scripting context, where an embed fetches a document and lets it EXECUTE. That
  difference is why the source takes its own egress class (see the URL floor above) rather than
  reusing `Media`'s.
- **The sandbox declaration is emitted ALWAYS and EMPTY when nothing is granted, and the type is what
  discharges the "always" half.** `EmbedFramePlan.sandbox` is `[String]` and not `[String]?`, so
  there is no representation of "no sandbox" for an arm to reach — omitting the declaration on a
  permissionless embed produces the same result as an UNSANDBOXED frame, and that is the obligation a
  surface fails by writing the obvious code. The tokens are the VOCABULARY's declaration order,
  de-duplicated, read from `EmbedPermission.allCases` rather than from a second list beside it, so a
  fifth relaxation takes its place with no edit here. `AllowFullscreen` is NOT a sandbox token — it
  is a permissions-policy directive riding `allow`, and the corpus fixture carries exactly that one
  permission so a host that mapped the whole enum onto sandbox tokens fails there and nowhere else.
- **A refused source OMITS the source entirely, and the refusal is still RECORDED.** This is the one
  place a refusal does not take a substitute destination: a frame pointed at a refusal URL RENDERS
  that page, where one with no source is a well-defined empty browsing context that fetches nothing.
  The plan therefore carries `source: String?` **and** `sourceRefused: Bool`, because "nothing was
  declared" and "this was refused" are different facts and an Optional alone cannot tell them apart —
  the `ImagePresentation` `expansionRefused` shape, at the position where the difference matters
  most. An empty resolved source reads as *nothing declared* rather than as a refusal: telling a
  reader their destination was rejected when the document never resolved one is a wrong diagnosis.

**The decoder does NOT apply the floor**, and that is §19.1 rather than an oversight: a document
naming an `http` or relative embed source is a valid wire document, so the decoder carries the value
through unchanged and the check happens where a real destination exists.

**Forward-coupling.** A fifth `EmbedPermission`, a change to the token mapping or the ordering rule,
or a change to what a refusal costs updates this section, `EmbedPresentation.swift`, the arm in
`FuaranNode.swift`, and the three `Embed/*` checkers in
`Tests/FuaranUIRendererTests/RenderObligationTests.swift` in the same change.

## Tree — eight obligations, one of which has a manifest row

`Tree` (§3.6.12) carries a hierarchy of `TreeItem` ROWS — not `Node`s — and, optionally, the names of
the two State slots through which a reader opens rows and selects one. The projection is
`Sources/FuaranUIRenderer/TreeProjection.swift`; what transfers and what does not is here.

**What crosses from the HTML tiers is not the attribute names but the FACTS behind them.** Those
tiers emit `role="tree"` / `role="treeitem"` / `role="group"` with `aria-level`, `aria-setsize`,
`aria-posinset`, `aria-expanded`, `aria-selected` and a roving `tabindex`. A SwiftUI surface has no
attribute bag, so `TreeRowPlan` carries a row's depth, its position in its own sibling set, whether it
owns children, whether it is open, whether it is selected, and which single row is the widget's tab
stop — every one computable from the wire plus the two named slots, with no view involved.

- **`expanded` and `selected` are `Optional`, and `nil` is the ABSENCE of the claim rather than a
  negative one.** On a leaf an expansion claim asserts a subtree that does not exist and assistive
  technology announces the row as closed — a reader told there is more when there is not. A tree that
  names no selection key must not declare a selectable widget with nothing selected.
- **A tree naming no `expandedStateKey` renders FULLY EXPANDED**, and an EMPTY declared set is a
  different state: a document that named a key over which every row is currently closed. Collapsing
  the two would make a declared, fully-closed tree indistinguishable from a static one. A state value
  of any other shape reads as empty rather than as an error — this is the host's own slot, not a wire
  document, and refusing would blank a tree over a value the reader never authored.
- **ONE tab stop.** Exactly one VISIBLE row carries it — the selected row when it is visible, else the
  first visible row — computed from state alone, so a server rendering and an interactive host's first
  frame agree. This is the obligation the kind exists for: a composition of independently focusable
  containers is N tab stops, and no arrangement of them produces one.
- **The accessible name is the row's OWN visible label, stated and never computed.** A treeitem owns
  its child group, so a name computed from contents reads the whole branch out as the row's own name;
  the arm therefore makes each row one accessibility element with a stated label. This is the one
  obligation with a `render-fidelity.json` row, so it is asserted in `RenderObligationTests`; the
  other seven are asserted in `TreeProjectionTests`, because "the manifest does not enumerate it" is
  not the same statement as "no host owes it".
- **Nothing else is derived from a row.** Expandability comes from `children` and from nothing else,
  and there is no per-row expansion state beside the named key — a shadow copy is free to disagree
  with the slot every other row is drawn from. `visibleRowIds` and the plans read the same
  `isExpanded`, so a second walk cannot acquire its own notion of openness.
- **The six key bindings are an INTERACTIVE host's addition** over this identical structure, and are
  deliberately not modelled. The server rendering is complete and navigable; what hydration adds is
  movement, not legibility.

**Row nesting is bounded on its OWN axis (§21.5).** A whole hierarchy lives inside one node, so the
node-depth counter cannot see it however deep it goes, and at roughly two JSON levels per row the
syntactic bound is not reached either — the same two false comforts the `TreeOp.Batch` axis sprang, at
a new slot. `WireWalkState.enterItem` counts it from the root row list and refuses a breach on the way
down, reusing `maxNodeDepth` rather than minting a sixth limit: these frames cost what the node
decoder's frames cost, so a second number would be two figures for one per-frame budget. It does NOT
feed `maxNodes` — a `TreeItem` is not a `Node`, and counting one as the other would let a wide
hierarchy exhaust a budget that exists to bound a different population.

**Row-id uniqueness is an EMIT-side obligation, not a decode refusal**, per §8.1's position for
`NodeId`: duplicate detection is a whole-tree property, a streaming decoder is not required to carry
the id set, and there is no error code for it. This surface accepts a duplicate and is conformant.

## The tooltip trait — a description, never a name

The node-level `tooltip` (§3.1) is a hint that supplements a name which already exists. The
projection is `Sources/FuaranUIRenderer/TooltipProjection.swift`, and the decisions — including two
DECLINED obligations — are recorded in that file's header rather than duplicated here, because
`render-fidelity.json` carries **no row** for it (the trait is a field, not a kind, and §11.2
vocabulary attestation enumerates cases) and so `TooltipProjectionTests` is the whole of this
surface's answer.

Three things are worth stating here anyway.

- **It reaches `accessibilityHint` and NEVER `accessibilityLabel`**, and the separation is structural:
  the projection carries no name-shaped field at all, so there is nothing for an arm to reach for. An
  icon-only control needs both slots saying different things, and a surface that conflated them would
  leave such a control with two competing names and no description.
- **A hint that resolves to empty or whitespace emits NOTHING** — no rendered element, no description.
  This is the one obligation of the six a surface fails by writing the obvious code
  (`if node.tooltip != nil`), and emptiness is decided AFTER resolution, because a bound or `i18n`
  hint resolves only at render time.
- **Two obligations are declined and say so in the projection's own fields.** The focus-stop guarantee
  is not claimed: the render floor gives most kinds no focus stop, and synthesising one around every
  hinted node would rewrite a tree's tab order to satisfy a description. And the `describedBy` merge is
  VACUOUS here, because that slot is an id reference into a document this surface does not have — the
  accessibility projection drops it and reports it dropped, so there is nothing to merge with. Both are
  fields rather than omissions, so a reader can tell a decision from an oversight.

## Sparkline lowering — the posture, and why it is not a placeholder

`Sparkline` lowers to the wire's own `Drawing` and renders through the same canvas an authored
`Drawing` uses (`Sources/FuaranUIRenderer/SparklineLowering.swift`). The full argument is in
`docs/RENDER-PROJECTION.md` — it is a claim a consumer needs, not only a maintainer — and the short
form is: the arm previously took NO arguments, so the series was structurally unreachable; this
surface already carries a vector drawing arm, so lowering costs a pure function and reuses a seam;
and the geometry is fixed by shared goldens rather than by this surface's opinion, so a divergence is
a failing test rather than an argument.

**Forward-coupling.** A change to the geometry, the chrome or the rounding is a change to a SHARED
contract: it moves in the goldens and in every certified host, never here alone. The min/max fold is
written out rather than delegated to a standard-library reduction because NaN ordering is a
language's own choice and the sentinel vector pins the arithmetic; do not "simplify" it to
`series.min()`.

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
