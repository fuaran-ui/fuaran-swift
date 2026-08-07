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

**1. Never open a tree-supplied URL without the floor.** `LinkSpec.href`, `ImageSpec.src` and
`Action.navigate(route:)` are handed to you exactly as the wire spelled them. Route every one
through `FuaranUrlPolicy` before it reaches `UIApplication.open`, `NSWorkspace.open`, an
`URLRequest`, or any web view you add:

```swift
switch link.sanitizedHref {                       // NOT link.href
case .allowed(let url):  open(URL(string: url)!)  // http / https / mailto / tel, or relative
case .rejected(_, let why): log("refused destination: \(why)")
case .dynamic:                                    // the slot is a State / Query / Format binding
    // Resolve it however your app resolves bindings (read the session's
    // resolved projection), then apply the same floor to the result:
    if let safe = FuaranUrlPolicy.sanitize(resolvedHref) { open(URL(string: safe)!) }
}
```

The allowlist is `http` / `https` / `mailto` / `tel` plus relative paths and fragments. Everything
else is refused, including unknown schemes (deny by default), protocol-relative `//host` forms, and
backslash forms — `\\host`, `/\host` — which several URL parsers normalise back to `//`. The scheme
candidate is scrubbed of ASCII whitespace and control characters first, so `java\tscript:` is
classified as `javascript:` and refused; a `hasPrefix("javascript:")` check of your own is not a
floor.

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
  staticlib (or the `FuaranCore.xcframework` on Apple platforms); session tests drive
  seed → apply-op → re-project end-to-end when the core is linked.
- **SwiftUI renderer floor + interaction round-trip + server-driven driver** — the exhaustive
  `FuaranNode` dispatch spine, the tone bridge, the `FuaranHost` interaction loop, and the
  transport-agnostic driver (SwiftUI legs compile on Apple platforms; the pure layers build
  everywhere).

## Licence

Apache-2.0. See [LICENSE](LICENSE).
