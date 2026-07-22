// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// A minimal SwiftUI sample (Phase 541) driving a live tree end-to-end through a
// `FuaranHost` — the demo that makes the mobile SDUI story visible. It seeds an
// in-memory session, projects the tree through `InteractiveFuaranTree` under
// `FuaranTheme`, and surfaces a validator reject inline.
//
// This ships as a compiled, preview-able SwiftUI view (CI type-checks it). A
// fully runnable iOS/macOS *app bundle* needs an Xcode project, which SwiftPM
// cannot emit — see `Samples/README.md`. Over the live Rust session, swap
// `PreviewTreeSession` for a `FuaranSession` (gated on the native core).
//
// Guarded by `#if canImport(SwiftUI)`.

#if canImport(SwiftUI)

  import FuaranUI
  import SwiftUI

  /// An in-memory `FuaranTreeSession` for the sample / SwiftUI previews (no
  /// native core). It adopts an applied op as the replacement tree JSON — enough
  /// to drive the re-projection loop without the Rust core. An `actor` so it
  /// satisfies the single-owner, `async` session contract by construction.
  actor PreviewTreeSession: FuaranTreeSession {
    private var current: String
    init(initial: String) { self.current = initial }
    func treeJSON() -> String { current }
    // No native evaluator: the projection is the raw tree (Phase 650).
    func projectResolved() -> String { current }
    func applyOp(_ opJSON: String) throws { current = opJSON }
    func setState(key: String, valueJSON: String) throws {}
    func setFilter(name: String, valueJSON: String) throws {}
    func setQuery(name: String, valueJSON: String) throws {}
  }

  /// A minimal end-to-end sample view: a themed, interactive Fuaran tree over a
  /// live host.
  public struct FuaranSampleView: View {
    @State private var host: FuaranHost?

    public init() {}

    public var body: some View {
      FuaranTheme {
        VStack(alignment: .leading, spacing: 8) {
          Text("Fuaran · SwiftUI sample").font(.headline)
          if let host {
            if let error = host.lastError {
              Text("rejected: \(String(describing: error))")
                .font(.caption)
                .foregroundStyle(.red)
            }
            InteractiveFuaranTree(host: host)
          } else {
            Text("Loading…").foregroundStyle(.secondary)
          }
        }
        .padding()
      }
      .task {
        if host == nil {
          host = try? await FuaranHost.start(session: PreviewTreeSession(initial: Self.sampleTreeJSON))
        }
      }
    }

    /// A small, valid wire tree the sample projects. Kept intentionally simple so
    /// it decodes with the shipped `RenderProjection` decoder.
    static let sampleTreeJSON = #"""
      {"id":"root","kind":{"$type":"Box","role":"Card","layout":{"$type":"Flex","direction":"Vertical"},"children":[
        {"id":"h","kind":{"$type":"Heading","level":2,"text":{"$type":"Literal","text":"Fuaran on SwiftUI"},"variant":"Standard"}},
        {"id":"m","kind":{"$type":"Markdown","text":{"$type":"Literal","text":"A live wire tree, projected through the SwiftUI floor and driven through the session."}}},
        {"id":"b","kind":{"$type":"Badge","label":{"$type":"Literal","text":"server-driven"},"variant":"Brand"}}
      ]}}
      """#
  }

#endif
