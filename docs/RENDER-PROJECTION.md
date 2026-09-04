# The Swift render projection

`fuaran-swift` is the **native Swift surface of the Fuaran UI wire format, over
the Rust reference core**. The core owns truth and mutation — decode, apply
tree-ops, render — behind a C-ABI; the Swift side decodes the core's canonical
tree JSON into native sealed types for rendering.

That division decides what this package does and does not owe you, so it is worth
being exact about before anything else.

## What this is, and what it is not

**This is a render projection, not a conformant host.** The wire format's own
host roster classifies it that way, and draws the consequence: a render
projection consumes a codec host's already-decoded tree for native rendering
only. It never canonically *encodes*, so it carries **no byte-parity leg**. Its
bar is a render-coverage checklist over the node corpus — a new `NodeKind`
lacking a renderer arm is a build error in this tier, but is not a *wire*
conformance failure.

So the claim this package makes is: **every node fixture in the shared
conformance corpus decodes into the sealed model, with a compile-time-exhaustive
`switch`.** A byte-parity claim would be a claim about the core.

Three things follow, and each is visible in the code rather than merely asserted:

- **`JSON.object` is an unordered dictionary.** A canonical codec could not model
  it that way — canonicalisation sorts object keys and reproduces number form
  byte-exactly. The read-only model is structural proof that no encode leg is
  possible from it.
- **There is no `TreeOp` decoder at all.** The core owns apply, and a render
  projection never sees an op.
- **There is no pre-emit validator.** A pre-emit validator is a check an emitter
  runs before it emits, and this surface emits no tree.

One function will look like a counter-example and is not.
`Interaction.swift`'s internal `jsonToWire` serialises a **scalar** so a state
write-back can hand a value back to the session. It is not a canonical tree
encoder, and the only thing that ever travels Swift → core is a `$state` value;
the core owns the canonical encode of the tree that results.

## Package shape

Swift 6 tools version, macOS 13 / iOS 16, and **zero external package
dependencies** — the only imports across `Sources/` are `Foundation`, `SwiftUI`,
`Combine`, and the local C target.

| Product | What it is |
|---|---|
| `FuaranUI` | The sealed tree model, the render-projection decoder, the URL policy, and `FuaranSession` |
| `FuaranUIRenderer` | The SwiftUI floor, the tone bridge, and the pure render plans |
| `FuaranUIDriver` | The server-driven loop. Foundation only, so it builds everywhere |

### The native core is linked conditionally, and that is load-bearing

There is no `systemLibrary` target and no build plugin. `Package.swift` probes
the filesystem for the Rust static library — at `FUARAN_RS_STATICLIB_DIR` if set,
otherwise the sibling `../fuaran-rs/target/debug` — and only when it finds one
does it add the `FuaranCore` C target, wire the linker flags, and define
`FUARAN_CORE_AVAILABLE`.

**So a checkout without the core still builds and tests the pure-Swift
projection**, and the session tests skip cleanly. The whole of `Session.swift`
sits behind that flag; on a machine without the core, the file compiles to
nothing and the decoder stands alone.

On Apple platforms the reference packaging is a `FuaranCore.xcframework` binary
target assembled with `xcodebuild`; on Windows and Linux the same C surface links
the static library directly, which is how the Swift↔C-ABI binding gets exercised
on a non-Apple box.

## Decoding a tree

One public entry point:

```swift
import FuaranUI

let root = try RenderProjection.decodeNode(json)   // canonical tree JSON from a session
```

```swift
public struct Node: Equatable, Sendable {
  public var id: String
  public var kind: NodeKind
  public var state: StateBehaviour
  public var style: SemanticStyle
  public var accessibility: Accessibility?
}
```

`NodeKind` is an `indirect enum` with one case per wire `$type`, so a `switch`
over it is exhaustive at compile time:

```swift
guard case .box(let box) = root.kind else { return }   // box.role == .dashboard
for child in box.children {
    switch child.kind {
    case .heading(let h): print(h.level, h.text)   // 2, .literal("Channel performance")
    case .markdown(let m): print(m.text)
    default: break
    }
}
```

**In your own exhaustive walks, leave off the `default`.** A new wire kind then
arrives as a build error naming your file — which is the guarantee the sealed
model exists to give. The package keeps three such tripwires deliberately:
`NodeKind.typeName` and `NodeKind.category` in the model itself, and
`fuaranCoverageChildren` in the renderer.

Three Swift names differ from their wire spelling, because the obvious ones are
taken or reserved: the cases are `switchKind` (`"Switch"`), `dataGrid`
(`"DataGrid"`), and `filters` — the only case whose payload is a bare array
(`[FilterSpec]`) rather than a spec record.

The closed bare-string vocabularies (`ToneVariant`, `BoxRole`, `ChartKind`, and
some forty others) are `String`-raw enums whose `rawValue` *is* the wire
spelling, so `init?(rawValue:)` is the parse and a missing case is a throwable
unknown discriminator rather than a silent fallback.

### Failure is typed, and the path convention has a subtlety

```swift
public struct FuaranDecodeError: Error, Equatable {
  public enum Code: String {
    case invalidJson   = "INVALID_JSON"
    case missingField  = "MISSING_FIELD"
    case wrongType     = "WRONG_TYPE"
    case unknownDuCase = "UNKNOWN_DU_CASE"
    case emptyNodeId   = "EMPTY_NODE_ID"
    case wrongNodeKind = "WRONG_NODE_KIND"
    case limitExceeded = "LIMIT_EXCEEDED"
  }
  public let code: Code
  public let path: String      // "$"-rooted, e.g. "$.kind.level"
  public let message: String
}
```

`LIMIT_EXCEEDED` is deliberately not `INVALID_JSON`: the input is well-formed
JSON, refused for being structurally unbounded, and calling a
well-formed-but-too-deep document malformed is an actively wrong diagnosis. The
message names the limit and the observed shape so an author knows which bound to
come back under.

**The `$type` suffix appears in a path only when a discriminator is genuinely at
fault.** An unrecognised case of a `$type`-tagged union reports at
`$.kind.$type`; an unrecognised case of a *bare* enum reports at the field's own
path — `$.style.tone`, with no suffix. There is no `$type` member in the document
at a bare-enum position, so naming one would send an author to edit a key that is
not there.

### The limits are per call, not global

```swift
public enum WireLimits {
  public static let maxNodeDepth   = 24
  public static let maxJSONDepth   = 256
  public static let maxStringLength = 1_048_576
  public static let maxArrayLength  = 100_000
  public static let maxNodes        = 100_000
}
```

The counters are created per `decodeNode` call and threaded down the walk rather
than held in global or thread-local state. `decodeNode` is public API, so
concurrent decode from several tasks is expected usage, and shared mutable
counters would be a data race of the damaging kind: two decodes silently
mis-bounding each other shows up as a *valid* tree refused on a busy machine and
never on a quiet one. Under Swift 6 strict concurrency it would not compile
without an unsafe escape hatch, and reaching for one to bound untrusted input
would be an odd trade.

The compiler is the checklist: a decoder function that reaches `node` without
carrying the state is a build error.

### Lenient where the specification says to be, strict where it matters

This is a *consumer-grade* decoder — being stricter than the language is an
availability defect, not a safe default. Four enumerated leniencies:

- **A `Static` envelope wrapped around a plain scalar unwraps** before every
  scalar read, in one place rather than site by site. An object that is not a
  well-formed `Static` envelope passes through and fails normally.
- **Curated enum alias tables.** `"Row"`/`"row"` read as `.horizontal` on the CSS
  flex-direction prior; `"Positive"` as `.success`; `"Danger"`/`"Negative"` as
  `.critical`. Anything else still fails `UNKNOWN_DU_CASE` naming the canonical
  list.
- **Field-name aliases**, with the canonical name always winning when both are
  present, and the nested path always using the canonical name.
- **Five legacy node-kind upgrades** — `Dashboard`, `Stack`, `GridLayout`, `Card`
  fold into `Box`.

And two places it is deliberately strict. An explicit `null` in a host-opaque
payload slot is refused: the wire spells absence by *omitting* the key, so a
`null` is a malformed document, and accepting it would hand the app a slot that
claims to carry a value and does not. And a typed binding slot still checks its
type — the shorthand rules are about *shape*, so `"label": "Home"` is sanctioned
while `"hidden": "yes"` is refused.

### What the projection does not model

`motion` and `extraAttributes` are wire-omitted by design and absent from the
model. Closure-bearing slots carry a `Closure` marker — presence only, since the
value is unobservable. And `TrendPolarity.Neutral` is reserved by the
specification and deliberately not a case: the case set *is* the accepted wire
set, so `"Neutral"` fails rather than this surface quietly deciding a question
the reservation holds open. No alias arm is registered for it, because the
obvious candidates are precisely the spellings that must not be accepted.

Two modelling decisions are worth knowing because they read as omissions and are
not. An image's `fit` / `aspectRatio` / `loading` are **total, not optional** —
"absent means `Natural`" is a default rather than a third state, and modelling
absence as `nil` would push the decision out to every reader. And `srcSet` is
`[SrcSetEntry]`, not `[SrcSetEntry]?`, because an absent slot and an empty one
denote the same document; a surface answering `nil` for an absent `srcSet` has
produced a value the format's own encoder cannot round-trip.

## The safety floor

A decoded tree is **untrusted input**, and usually arrives from a model.

```swift
switch link.sanitizedHref {                       // NOT link.href
case .allowed(let url):     open(URL(string: url)!)
case .rejected(_, let why): log("refused destination: \(why)")
case .dynamic:                                    // a State / Query / Format binding
    if let safe = FuaranUrlPolicy.sanitize(resolvedHref) { open(URL(string: safe)!) }
}
```

Accessors exist for every slot the wire hands over verbatim:
`LinkSpec.sanitizedHref`, `ImageSpec.sanitizedSrc`, each
`SrcSetEntry.sanitizedSrc`, `MediaSpec.sanitizedSrc`, a video's
`sanitizedPoster`, and `Action.sanitizedNavigateRoute`.

The floor is a **public accessor rather than a decode-time filter**, and the
reason is a real consequence of the architecture: `href` and `src` are `Binding`s
whose value may not exist until the core resolves a `State`, `Query` or `Format`
slot, so a check at decode time would be examining a placeholder. The projection
stays a faithful view of the wire; the check happens where a real destination
exists. `.dynamic` is a case rather than a `nil` for the same reason — "refused"
and "not knowable yet" call for different handling.

The full policy, and the per-slot account of what a refusal *means* (an image
must have a source, so a refused `src` is a state you render; a refused `srcSet`
candidate or poster simply leaves), is in the repository README. Read it before
shipping.

## The `FuaranSession` actor

```swift
let session = try FuaranSession(treeJSON: seed)
let tree = try RenderProjection.decodeNode(await session.projectResolved())
await session.applyOp(opJSON)
```

### Single ownership, expressed by construction

The C-ABI session is **single-owner**: the handle and every call taking it must
stay on one executor for its whole lifetime. A Swift `actor` expresses that
contract by construction — every method is actor-isolated, so no two calls touch
the raw pointer concurrently, and the pointer never escapes the actor.

Three details are Swift-6-specific and worth knowing before you modify the file:

- **The handle is stored as a `UInt` bit pattern, not an `OpaquePointer`.** A raw
  pointer is not `Sendable`; the bit pattern is, which is what lets the
  `nonisolated deinit` read it under strict concurrency. The live pointer is
  reconstructed per isolated call.
- **It is a `let`, so free-exactly-once is structural.** No other reference can
  exist at `deinit`, so freeing there cannot race a concurrent call.
- **`fuaran_last_error` is a per-thread slot.** Each method is a single
  synchronous C-call sequence with no internal suspension, so it runs to
  completion on one executor thread — which is why a failing `init` reads its
  error envelope in the same synchronous context that saw the failure.

The actor's serialisation is the contract's load-bearing guarantee. A dedicated
pinned serial executor is the stricter option if strict thread-affinity is ever
required.

### `projectResolved()` versus `treeJSON()`

`treeJSON()` is the round-trip exit point. `projectResolved()` is the same tree
with scalar `Transform` bindings folded to the values they evaluate to — and it
is what a decode-only surface should render from, because this side carries no
compute evaluator at all (a `Binding.Transform` resolves to the empty string in
the render floor). The core resolves it; the projection renders what it decodes.

## Rendering with SwiftUI

The renderer floor is **shipped**, and its architecture is the thing to
understand first.

**Every normative render decision lives in a pure function outside the
`#if canImport(SwiftUI)` gate** — `mediaPlaybackPlan`, `imagePresentationPlan`,
`customPlaceholder`, `accessibilityProjection`, the drawing lowering, the trend
sentiment. Only the thin view application is Apple-gated. The reasoning is
recorded in each of those files: the decision is the load-bearing part, and a
decision testable on only one platform is a decision nobody re-checks. The plans
are asserted on Windows and Linux too.

```swift
FuaranNode(node, ctx)      // ctx: BindingContext
```

The dispatch spine is an exhaustive `switch` with no `default`, so a new wire
kind is a compile error until its arm lands. The corpus render-coverage gate
proves it holds: every node fixture projects through a real arm with **zero
fallback-arm hits**. A visible development placeholder exists as a *defined*
fallback a host may deliberately route through — it is structurally unreachable
from the spine, and its use is loud, because it is coverage-tracked.

### What "floor" means, arm by arm

Every one of the kinds has an arm; what differs is how much each arm paints.

- **Real** — layout containers (including masonry), headings, markdown, math,
  code blocks, lists, metrics with the trend glyph and sentiment tint, badges,
  callouts, toasts, facts, label/value rows, icons, progress, skeletons, tabs,
  steppers, disclosures, the vector drawing canvas, and the data grid with its
  twelve cell kinds.
- **Rendered but not interactive** — a link is styled text with no gesture.
- **Placeholder with the full plan applied** — an image reserves its aspect,
  binds its caption and decides its expansion affordance, but there is **no
  network image loader**; media discharges all three of its obligations in the
  plan and renders a labelled transport tile, but there is **no playback
  engine**. Pulling either in is not a decision a decoding surface makes for you.
- **Descriptive only** — chart, map, sparkline, mount, fragment reference.

### Interaction, and the boundary it does not cross

`FuaranHost` wraps a live session and publishes the re-projected tree as SwiftUI
state:

```
control interaction → FuaranHost.dispatch / writeBack → session.applyOp / setState
  → session re-encodes tree_json → RenderProjection.decodeNode re-projects
  → the published tree changes → SwiftUI recomposes
```

No wire-JSON handling happens outside the session boundary. A validator reject
surfaces as a typed `lastError` while the tree keeps the last-good projection:
the interaction is rejected, the UI is not crashed. Re-projection is deliberately
coarse — the whole tree is re-decoded per step, on the "measured before
optimising" principle.

Button dispatch is live. **Form write-back is live for four field kinds — text,
number, checkbox and toggle — and every other value-carrying arm is inert *by
construction*.** That distinction is the whole finding, and it is not the same as
a gap: the inert arms are `.disabled(true)` over a constant binding, or plain
text. The user cannot edit them, so there is no input to drop. Wiring write-back
into them would be dead code that merely looked like a fix. Making them live is
renderer feature work — real pickers, live slider thumbs — and is deliberately
not done here.

**If you add a value-carrying arm, it must either wire the write-back in the same
change or land disabled.** The sealed tree forces the arm to *exist*; nothing can
force it to *write*.

One interaction boundary is named rather than papered over: a `SetState` carrying
a literal `value` is wire-complete and is applied, but one carrying `valueFrom`
is not — resolving that binding needs the render context (a `Selection` reads the
clicked row of a named grid), which the dispatch seam does not carry. Leaving it
unapplied is the honest answer; writing a placeholder would put a wrong value
under a right-looking key.

## What is pending — stated plainly

- **The most recent platform-baseline wave has not been adopted here.** The
  shared corpus carries node kinds `Embed` and `Tree` and form-field kinds
  `Tokens`, `Rating` and `Color`, none of which this surface models; and
  `WriteToClipboard` has widened from a bare string to a text source, so a bound
  payload is refused as `WRONG_TYPE`. Seventeen node fixtures and eleven reject
  fixtures name that vocabulary. The reject ones matter most: they answer with
  the wrong code and path rather than the pinned one, and while that stands a
  genuine regression in the reject leg is invisible.
- **`FileUpload` silently drops four newer slots.** `capture`, `destination`,
  `dropTarget` and `acceptPaste` decode fine and fall on the floor — a different
  and quieter failure than a refusal.
- **The render-obligation roster is short by nine claims.** The artefact declares
  nineteen; this surface registers eight checkers and two declared exemptions.
  The remaining nine report as *unchecked with no checker registered*, which
  **reds that gate against today's corpus** — the mechanism working exactly as
  designed. Not checked is not passed, and silence is never an answer.
- **Three adoption bars are open**: contract cards, timed advance, and streamed
  upload. A host that has not adopted is not thereby exempt — it owes the
  obligation and has simply not made its answer visible.
- **Grid cells backed by closure accessors read empty**, because a closure never
  rides the wire: an editable cell shows its value without committing, a checkbox
  reads unchecked, a link is styled without a destination, a progress cell reads
  zero. That is the decoded-path floor, matched across the surfaces.
- **`Binding.Format` is not applied in the render floor** — the underlying value
  is shown; number and date formatting is host work.
- **There is no runnable app bundle.** SwiftPM cannot emit an Xcode project, so
  the repository ships the sample *view* rather than an app. Create an Xcode app
  target, depend on this package, and set `FuaranSampleView()` as the root view.
- **There is no formatting gate.** `swift-format` ships with the toolchain but is
  not wired into `run.ps1`; match the surrounding style by hand.

## Verifying

```powershell
pwsh ./run.ps1              # swift build + swift test
pwsh ./run.ps1 -SkipBuild   # switches: -SkipBuild / -SkipTests / -Package
```

or drive SwiftPM directly with `swift build` and `swift test`. The reference
toolchain is Swift 6 on macOS; the build is portable to a correctly-configured
Swift-on-Windows toolchain. `run.ps1` skips cleanly with a named message when
there is no Swift toolchain, or on Windows when the MSVC linker is absent, and it
best-effort builds the sibling Rust core first so the session leg is available.

Two environment variables are worth knowing:

- **`FUARAN_RS_STATICLIB_DIR`** — point the package at a static-library directory
  to enable the C-ABI session leg.
- **`FUARAN_RENDER_FIDELITY`** — point the render-obligation suite at an
  alternative artefact file. It exists so the go-red property can be *proven*: a
  perturbed scratch copy carrying a claim no checker covers must turn the suite
  red, and demonstrating that must never involve writing to the shared corpus,
  which is the oracle every sibling surface answers to.

The conformance legs place the corpus at `<repo>/../wire-format-fixtures`. When
it is missing, the suite distinguishes two cases rather than skipping both: on a
standalone clone a skip is honest, but in a cross-host checkout it would mean the
gate silently certified nothing while reporting success — so that case **fails**.

CI is macOS-only, deliberately. Windows and Linux boxes have the Swift compiler
and Foundation but not SwiftUI, so the renderer floor and the interaction driver
cannot build off an Apple platform.
