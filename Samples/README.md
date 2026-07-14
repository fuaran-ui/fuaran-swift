<!-- SPDX-License-Identifier: Apache-2.0 -->
# fuaran-swift samples

The end-to-end SwiftUI sample (Phase 541) ships as a compiled, preview-able view,
`FuaranSampleView`, in
[`../Sources/FuaranUIRenderer/Sample.swift`](../Sources/FuaranUIRenderer/Sample.swift).
It drives a live wire tree through a `FuaranHost` and renders it with
`InteractiveFuaranTree` under `FuaranTheme` — the mobile server-driven-UI loop as
a library, made visible.

Because the sample is a library view (not a separate target), CI type-checks it
on every build and it drops straight into a SwiftUI `#Preview` or an app scene:

```swift
import SwiftUI
import FuaranUIRenderer

@main
struct FuaranSampleApp: App {
    var body: some Scene {
        WindowGroup { FuaranSampleView() }
    }
}
```

`FuaranSampleView` seeds an in-memory `PreviewTreeSession` (no native core). To
drive the **live Rust session**, build with the `fuaran-rs` staticlib present
(so `FUARAN_CORE_AVAILABLE` is set) and swap the session for a `FuaranSession`:

```swift
let session = try FuaranSession(treeJSON: initialTreeJSON)   // FUARAN_CORE_AVAILABLE
let host = try await FuaranHost.start(session: session)
InteractiveFuaranTree(host: host)
```

For the server-driven loop, wire `ServerDrivenDriver` (in `FuaranUIDriver`) over a
`URLSessionTransport`.

**Runnable app bundle.** A fully runnable iOS/macOS `.app` needs an Xcode project,
which SwiftPM cannot emit — so this repo ships the sample **view** (CI-verified)
rather than an app bundle, exactly as the phase scopes it. Create an Xcode app
target, add this package as a dependency, and set `FuaranSampleView()` as the root
view to run it on a device or simulator.
