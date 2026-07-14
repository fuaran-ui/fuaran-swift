// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The Phase 540 render-coverage gate — the render-leg twin of Phase 538's
// decode-coverage harness. Every node fixture in the shared
// `../wire-format-fixtures/` corpus is decoded (via the shipped
// `FuaranUI.RenderProjection` decoder — the renderer never parses wire JSON) and
// then projected through the SwiftUI floor: `fuaranNodeBody` is invoked for the
// fixture root and every embedded child (walked via `fuaranCoverageChildren`),
// constructing the real SwiftUI view for each node. Constructing the view records
// coverage through a real arm of the exhaustive spine.
//
// The bar: every fixture projects without a decode throw and with **zero
// fallback-arm hits**; per-kind coverage is reported, and any corpus kind not
// exercised is enumerated as an explicit TODO — never a silent gap. Skips
// cleanly when the corpus is absent (standalone checkout) or when SwiftUI is
// unavailable (a non-Apple box).

import XCTest

#if canImport(SwiftUI)

  import Foundation

  @testable import FuaranUI
  @testable import FuaranUIRenderer

  @MainActor
  final class RenderCoverageTests: XCTestCase {
    /// Locate the shared corpus relative to this source file:
    /// `<repo>/Tests/FuaranUIRendererTests/…` → `<repo>/../wire-format-fixtures`.
    static func corpusDir() -> URL? {
      let here = URL(fileURLWithPath: #filePath)
      let repoRoot =
        here
        .deletingLastPathComponent()  // FuaranUIRendererTests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // fuaran-swift
      let corpus = repoRoot.deletingLastPathComponent().appendingPathComponent("wire-format-fixtures")
      var isDir: ObjCBool = false
      let exists = FileManager.default.fileExists(atPath: corpus.path, isDirectory: &isDir)
      return exists && isDir.boolValue ? corpus : nil
    }

    struct Fixture {
      let id: String
      let kind: String
      let decoder: String
      let inputFile: String
    }

    static func loadFixtures(_ corpus: URL) throws -> [Fixture] {
      let text = try String(contentsOf: corpus.appendingPathComponent("manifest.json"), encoding: .utf8)
      guard case .object(let root) = try JSON.parse(text), case .array(let entries)? = root["fixtures"]
      else { return [] }
      var out: [Fixture] = []
      for e in entries {
        guard case .object(let f) = e,
          case .string(let id)? = f["id"],
          case .string(let kind)? = f["kind"],
          case .string(let decoder)? = f["decoder"],
          case .string(let inputFile)? = f["inputFile"]
        else { continue }
        out.append(Fixture(id: id, kind: kind, decoder: decoder, inputFile: inputFile))
      }
      return out
    }

    /// The corpus's authoritative `kinds` enumeration (for the TODO report).
    static func corpusKinds(_ corpus: URL) throws -> Set<String> {
      let text = try String(contentsOf: corpus.appendingPathComponent("manifest.json"), encoding: .utf8)
      guard case .object(let root) = try JSON.parse(text), case .array(let arr)? = root["kinds"]
      else { return [] }
      return Set(arr.compactMap { if case .string(let s) = $0 { return s } else { return nil } })
    }

    /// Walk a decoded tree, projecting each node through the real render spine so
    /// its kind is recorded through a real arm.
    func probe(_ node: Node, _ coverage: RenderCoverage) {
      _ = fuaranNodeBody(node, BindingContext(state: [:], coverage: coverage))
      for child in fuaranCoverageChildren(node) { probe(child, coverage) }
    }

    func testEveryNodeFixtureRendersThroughTheFloorWithZeroFallbacks() throws {
      guard let corpus = Self.corpusDir() else {
        throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
      }
      let fixtures = try Self.loadFixtures(corpus).filter {
        $0.decoder == "node" && ($0.kind == "node-round-trip" || $0.kind == "lenient-accept")
      }
      XCTAssertGreaterThan(fixtures.count, 0, "no node fixtures found in the corpus")

      let coverage = RenderCoverage()
      var failures: [String] = []
      var rendered = 0

      for fx in fixtures {
        let url = corpus.appendingPathComponent(fx.inputFile)
        let json: String
        do {
          json = try String(contentsOf: url, encoding: .utf8)
        } catch {
          failures.append("read \(fx.id) (\(fx.inputFile)): \(error)")
          continue
        }
        do {
          let node = try RenderProjection.decodeNode(json)
          probe(node, coverage)
          rendered += 1
        } catch let e as FuaranDecodeError {
          failures.append("decode \(fx.id) (\(fx.kind)): [\(e.code.rawValue)] \(e.path) — \(e.message)")
        } catch {
          failures.append("render \(fx.id): unexpected \(error)")
        }
      }

      let report = coverage.kinds.keys.sorted().map { "\($0)=\(coverage.kinds[$0]!)" }.joined(separator: " ")
      print("RENDER COVERAGE (\(coverage.kinds.count) kinds, \(rendered) fixtures): \(report)")

      let todo = (try Self.corpusKinds(corpus).subtracting(coverage.kinds.keys)).sorted()
      if todo.isEmpty {
        print("Floor coverage: every corpus node kind rendered through a real arm (no TODO kinds).")
      } else {
        print("TODO kinds (present in corpus, not exercised by a rendered fixture): \(todo)")
      }
      if !coverage.fallbacks.isEmpty { print("FALLBACK-ARM HITS: \(coverage.fallbacks.sorted())") }

      XCTAssertTrue(coverage.fallbacks.isEmpty, "fallback-arm hits: \(coverage.fallbacks.sorted())")
      XCTAssertEqual(rendered, fixtures.count, "some node fixtures failed to render:\n\(failures.joined(separator: "\n"))")
      XCTAssertTrue(failures.isEmpty, "render/decode failures:\n\(failures.joined(separator: "\n"))")
    }

    /// The node-round-trip family alone must exercise a broad slice of the flat
    /// vocabulary — a guard that the harness is really walking the corpus.
    func testNodeRoundTripFamilyCoversManyKinds() throws {
      guard let corpus = Self.corpusDir() else {
        throw XCTSkip("wire-format-fixtures corpus not found — skipping.")
      }
      let fixtures = try Self.loadFixtures(corpus).filter { $0.decoder == "node" && $0.kind == "node-round-trip" }
      let coverage = RenderCoverage()
      for fx in fixtures {
        let json = try String(contentsOf: corpus.appendingPathComponent(fx.inputFile), encoding: .utf8)
        probe(try RenderProjection.decodeNode(json), coverage)
      }
      XCTAssertGreaterThanOrEqual(coverage.kinds.count, 15, "expected the node corpus to span many kinds")
    }
  }

#else

  final class RenderCoverageTests: XCTestCase {
    func testRendererLegSkipsWhenSwiftUIAbsent() throws {
      throw XCTSkip("SwiftUI not available on this platform — the renderer floor is a SwiftUI (macOS-reference) leg; skipping.")
    }
  }

#endif
