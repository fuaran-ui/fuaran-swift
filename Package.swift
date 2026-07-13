// swift-tools-version:6.0
// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// fuaran-swift — the native Swift surface over the Rust reference core of the
// Fuaran UI wire format. Phase 538 establishes the sealed tree model + the
// render-projection decoder as the pure-Swift `FuaranUI` library. The C-ABI
// session binding (FuaranCore + the `FuaranSession` actor) arrives in Phase 539.

import PackageDescription

let package = Package(
    name: "fuaran-swift",
    products: [
        .library(name: "FuaranUI", targets: ["FuaranUI"])
    ],
    targets: [
        .target(name: "FuaranUI"),
        .testTarget(name: "FuaranUITests", dependencies: ["FuaranUI"]),
    ]
)
