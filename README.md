# fuaran-swift

The **native Swift surface** of the [Fuaran UI wire format](../fuaran-dotnet/docs/WIRE_FORMAT.md) — a
render/authoring surface over the Rust reference core. Apache-2.0.

`fuaran-swift` is **not** a standalone conformant host. The Rust reference core owns truth and
mutation (decode, apply tree-ops, render) behind a C-ABI; the Swift side holds a **render
projection** — a consumer-grade decoder that parses the core's canonical tree JSON into native
sealed Swift types (`NodeKind`, `Spec` families, `Binding`, `Action`, … as `enum`s with associated
values) for rendering. It never canonically *encodes*, so there is no byte-parity contract; the bar
is that it decodes every node fixture in the shared conformance corpus into the sealed model with a
compile-time-exhaustive `switch` — a new wire kind is a build error, never a silent fallback.

## Get started

Add the package and depend on the `FuaranUI` product:

```swift
.package(url: "https://github.com/fuaran-ui/fuaran-swift.git", from: "0.1.0"),
// target dependency: .product(name: "FuaranUI", package: "fuaran-swift")
```

**What that gets you, precisely.** `FuaranUI`'s pure-Swift half — the sealed tree model and the
render-projection decoder — resolves for any consumer. **`FuaranSession` does not.** The C-ABI
binding is wired only when `Package.swift` finds the Rust reference core's native staticlib beside
the manifest (or at `FUARAN_RS_STATICLIB_DIR`), which holds on a side-by-side workspace checkout
and does not for anyone consuming this package over SPM. There is no `binaryTarget` and no
published artefact for one to name. See [Consuming a live session](#consuming-a-live-session).

Decode a session's canonical tree JSON into the sealed model and `switch` over it —
an unmodelled kind is a compile error:

```swift
import FuaranUI

let root = try RenderProjection.decodeNode(json)
guard case .box(let box) = root.kind else { return }   // box.role == .dashboard
for child in box.children {
    switch child.kind {
    case .heading(let h): print(h.level, h.text)   // 2, .literal("Channel performance")
    case .markdown(let m): print(m.text)
    default: break
    }
}
```

Full walkthrough — decode → render projection → SwiftUI:
<https://fuaran-ui.io/get-started/swift>.

## Safety floor — what the embedding app must do

A decoded tree is **untrusted input**. It usually arrives from a model, and a model will happily
emit a `Link` whose `href` is `javascript:…` or a `Navigate` whose `route` points somewhere you did
not intend. Two obligations, and the first is the one that bites:

**1. Never open a tree-supplied URL without the floor.** `LinkSpec.href`, `ImageSpec.src`,
`MediaSpec.src`, the `Video` variant's `poster`, every `ImageSpec.srcSet` candidate, and
`Action.navigate(route:)` are handed to you exactly as the wire spelled them. Route every one
through `FuaranUrlPolicy` before it reaches `UIApplication.open`, `NSWorkspace.open`, an
`URLRequest`, or any web view you add. **The media and `srcSet` slots deserve a separate mention
because they are fetched with no user act at all** — nobody taps a poster frame or a responsive
candidate — so a slot of that shape that skipped the floor would be a documented way around it.
Accessors exist for each (`media.sanitizedSrc`, `media.sanitizedPoster`, `entry.sanitizedSrc`):

```swift
switch link.sanitizedHref {                       // NOT link.href
// `if let`, not `URL(string:)!` — the floor decides whether a DESTINATION is allowed,
// not whether Foundation can parse it, and those are different questions: an interior
// space passes the policy and returns nil here, so the force-unwrap this line used to
// carry crashed the app on a link the floor had just approved.
case .allowed(let str):  if let url = URL(string: str) { open(url) }  // http / https / mailto / tel, or relative
case .rejected(_, let why): log("refused destination: \(why)")
case .dynamic:                                    // the slot is a State / Query / Format binding
    // Resolve it however your app resolves bindings (read the session's
    // resolved projection), then apply the same floor to the result:
    if let safe = FuaranUrlPolicy.sanitize(resolvedHref),
       let url = URL(string: safe) { open(url) }
}
```

The allowlist is `http` / `https` / `mailto` / `tel` plus relative paths and fragments. Everything
else is refused, including unknown schemes (deny by default), protocol-relative `//host` forms, and
backslash forms — `\\host`, `/\host` — which several URL parsers normalise back to `//`. The scheme
candidate is scrubbed of ASCII whitespace and control characters first, so `java\tscript:` is
classified as `javascript:` and refused; a `hasPrefix("javascript:")` check of your own is not a
floor.

**What a refusal MEANS is not the same on every slot, and the difference is specified rather than
left to you.** An element must have a source, so a refused `ImageSpec.src` / `MediaSpec.src` is a
*state you render* — the picture or the player still appears, carrying whatever refusal marker your
app shows — never a reason to drop the node. A slot with no such obligation simply *leaves*: a
refused `srcSet` candidate is dropped from the candidate list, a refused `poster` is not shown (a
video with no poster shows its first frame, which works; a poster at a refusal URL is a broken image
over the player), and a refused `src` under `expandable` emits **no expansion affordance at all**,
because a link to nothing is a dead control. The `ImagePresentationPlan` and `MediaPlaybackPlan`
projections in `FuaranUIRenderer` apply all of this for you; read them rather than re-deriving it.

**2. Do not build an HTML path for tree text.** This surface has no `WKWebView` and no
HTML-parsing attributed-string path, and that absence is why it carries no script-injection sink at
all. `Markdown.text`, labels and every other `TextSource` are rendered as native `Text`. Passing
that content through `NSAttributedString(data:options:documentType:.html)`, or into a web view,
reintroduces exactly the class the native projection removed.

The floor is a public accessor rather than a decode-time filter deliberately: `href` / `src` are
`Binding`s whose value may not exist until the core resolves a `State`, `Query` or `Format` slot, so
a check at decode time would be examining a placeholder. The projection stays a faithful view of the
wire; the check happens where a real destination exists.

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
  staticlib; session tests drive seed → apply-op → re-project end-to-end when the core is linked.

## Consuming a live session

The staticlib is the only route today, and it is a build-it-yourself one: check out the Rust
reference core beside this repository, `cargo build` it, and `Package.swift` picks the library up
from `../fuaran-rs/target/debug` (or `FUARAN_RS_STATICLIB_DIR`). Without it the package still builds
and tests — the pure-Swift render projection is complete on its own, and the session tests skip.

**There is no `FuaranCore.xcframework`, and this section is where that used to be claimed.** A
`run.ps1 -Package` switch and a CI job of the same name both reported success while assembling
nothing at all, so the artefact was cited in three places and existed in none. Both are removed
rather than left green: a passing check for an absent capability is worse than no check, because it
is what everything downstream cites. When the packaging is written, the switch, the CI job (failing
unless an artefact is produced) and a `binaryTarget` land together — that being the only combination
in which an SPM consumer can actually reach `FuaranSession`.
- **SwiftUI renderer floor + interaction round-trip + server-driven driver** — the exhaustive
  `FuaranNode` dispatch spine, the tone bridge, the `FuaranHost` interaction loop, and the
  transport-agnostic driver (SwiftUI legs compile on Apple platforms; the pure layers build
  everywhere).

## Licence

Apache-2.0. See [LICENSE](LICENSE).
