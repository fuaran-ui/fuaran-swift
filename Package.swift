// swift-tools-version:6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// fuaran-swift — the native Swift surface over the Rust reference core of the
// Fuaran UI wire format.
//
//   • Phase 538: the pure-Swift `FuaranUI` library (sealed tree model +
//     render-projection decoder).
//   • Phase 539: the C-ABI session binding — the `FuaranCore` header shim over
//     `fuaran.h` + the `FuaranSession` actor, resolved against the Rust
//     reference core's native staticlib.
//
// The session leg is wired ONLY when the native staticlib is discoverable, so a
// checkout without it still builds + tests the pure-Swift projection (the session
// tests skip cleanly). The same C surface links the staticlib directly on every
// platform, which is how the Swift↔C-ABI binding is exercised on a non-Apple dev
// box as well as on macOS.
//
// There is NO `binaryTarget` here, and the comment that used to describe one — "on
// Apple platforms the reference packaging is a FuaranCore.xcframework binary
// target" — described an artefact nothing built. The consequence is worth stating
// where a consumer will meet it: an SPM consumer of this package gets the
// pure-Swift projection and CANNOT reach `FuaranSession`, because the staticlib is
// not beside their manifest. See README "Consuming a live session".

import Foundation
import PackageDescription

// Locate the Rust reference core's native staticlib: an explicit
// FUARAN_RS_STATICLIB_DIR override, else the sibling `../fuaran-rs/target/debug`.
let manifestDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let defaultLibDir =
  manifestDir
  .appendingPathComponent("../fuaran-rs/target/debug")
  .standardizedFileURL.path
let libDir = ProcessInfo.processInfo.environment["FUARAN_RS_STATICLIB_DIR"] ?? defaultLibDir

#if os(Windows)
  let staticLibFile = "fuaran_rs.lib"
  let coreSystemLibs = ["-lkernel32", "-lntdll", "-luserenv", "-lws2_32", "-ldbghelp"]
#else
  let staticLibFile = "libfuaran_rs.a"
  let coreSystemLibs: [String] = []
#endif

let coreAvailable = FileManager.default.fileExists(atPath: libDir + "/" + staticLibFile)

var targets: [Target] = []

var fuaranUIDeps: [Target.Dependency] = []
var fuaranUISwiftSettings: [SwiftSetting] = []
var testSwiftSettings: [SwiftSetting] = []
var testLinkerSettings: [LinkerSetting] = []

if coreAvailable {
  targets.append(.target(name: "FuaranCore"))
  fuaranUIDeps.append("FuaranCore")
  fuaranUISwiftSettings.append(.define("FUARAN_CORE_AVAILABLE"))
  testSwiftSettings.append(.define("FUARAN_CORE_AVAILABLE"))
  testLinkerSettings.append(.unsafeFlags(["-L", libDir, "-lfuaran_rs"] + coreSystemLibs))
}

targets.append(
  .target(name: "FuaranUI", dependencies: fuaranUIDeps, swiftSettings: fuaranUISwiftSettings))

// The SwiftUI renderer floor (Phase 540) + interaction / tone bridge (Phase 541).
// Its SwiftUI code is guarded by `#if canImport(SwiftUI)`, so the target compiles
// to nothing (the pure Coverage / BindingContext helpers aside) on a non-Apple box
// and the reference macOS build renders for real.
targets.append(
  .target(name: "FuaranUIRenderer", dependencies: ["FuaranUI"]))

// Phase 2331: the ONE wire-corpus locator every test suite reads — the declared
// `FUARAN_WIRE_FIXTURES` first, then the sibling and primary-worktree candidates.
// Foundation only, and in no product.
targets.append(.target(name: "FuaranWireCorpus"))
targets.append(
  .testTarget(
    name: "FuaranUIRendererTests",
    dependencies: ["FuaranUI", "FuaranUIRenderer", "FuaranWireCorpus"],
    swiftSettings: testSwiftSettings, linkerSettings: testLinkerSettings))

// The server-driven (SDUI) driver (Phase 541): transport seam + URLSession
// reference impl + the fetch/apply/re-project loop. Foundation only (no SwiftUI);
// written against the pure FuaranTreeSession seam, so it builds without the core.
targets.append(
  .target(name: "FuaranUIDriver", dependencies: ["FuaranUI"]))
targets.append(
  .testTarget(
    name: "FuaranUIDriverTests", dependencies: ["FuaranUI", "FuaranUIDriver"],
    swiftSettings: testSwiftSettings, linkerSettings: testLinkerSettings))

// Phase 2299: this repository's own generator over the wire corpus's published
// `idl.json`, which writes the sealed tree model (`Sources/FuaranUI/Model.generated.swift`).
// Foundation only, and in no product: a consumer of the package never builds it and
// never needs the corpus. `FuaranUITests` drives it as the regenerate-or-drift check;
// `swift run fuaran-idl-gen <idl.json>` runs it directly.
targets.append(.target(name: "FuaranUIIdlGen"))
targets.append(
  .executableTarget(name: "fuaran-idl-gen", dependencies: ["FuaranUIIdlGen"]))

targets.append(
  .testTarget(
    name: "FuaranUITests", dependencies: ["FuaranUI", "FuaranUIIdlGen", "FuaranWireCorpus"],
    swiftSettings: testSwiftSettings, linkerSettings: testLinkerSettings))

let package = Package(
  name: "fuaran-swift",
  platforms: [.macOS(.v13), .iOS(.v16)],
  products: [
    .library(name: "FuaranUI", targets: ["FuaranUI"]),
    .library(name: "FuaranUIRenderer", targets: ["FuaranUIRenderer"]),
    .library(name: "FuaranUIDriver", targets: ["FuaranUIDriver"]),
  ],
  targets: targets
)
