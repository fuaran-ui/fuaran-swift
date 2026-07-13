// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Corpus render-coverage harness: every node fixture in the shared
// `../wire-format-fixtures/` corpus must decode into the sealed model without
// hitting a fallback arm (an unknown discriminator throws, so a *successful*
// decode is proof no fallback was taken). Coverage is reported per NodeKind.
// Skips cleanly when the corpus is absent (standalone checkout).

import Foundation
import XCTest

@testable import FuaranUI

final class CorpusTests: XCTestCase {
  /// Locate the shared corpus relative to this source file:
  /// `<repo>/Tests/FuaranUITests/CorpusTests.swift` → `<repo>/../wire-format-fixtures`.
  static func corpusDir() -> URL? {
    let here = URL(fileURLWithPath: #filePath)
    let repoRoot =
      here
      .deletingLastPathComponent()  // FuaranUITests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // fuaran-swift
    let corpus = repoRoot.deletingLastPathComponent().appendingPathComponent(
      "wire-format-fixtures")
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
    let manifestURL = corpus.appendingPathComponent("manifest.json")
    let text = try String(contentsOf: manifestURL, encoding: .utf8)
    guard case .object(let root) = try JSON.parse(text),
      case .array(let entries)? = root["fixtures"]
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

  /// Every `node`-decoder fixture (node-round-trip + lenient-accept shorthand)
  /// decodes into the sealed model. A throw is a hard failure — that is the
  /// "zero fallback-arm hits" bar.
  func testEveryNodeFixtureDecodes() throws {
    guard let corpus = Self.corpusDir() else {
      throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
    }
    let fixtures = try Self.loadFixtures(corpus)
    let nodeFixtures = fixtures.filter {
      $0.decoder == "node" && ($0.kind == "node-round-trip" || $0.kind == "lenient-accept")
    }
    XCTAssertGreaterThan(nodeFixtures.count, 0, "no node fixtures found in the corpus")

    var perKind: [String: Int] = [:]
    var decoded = 0
    for fx in nodeFixtures {
      let url = corpus.appendingPathComponent(fx.inputFile)
      let json: String
      do {
        json = try String(contentsOf: url, encoding: .utf8)
      } catch {
        XCTFail("fixture \(fx.id): could not read \(fx.inputFile): \(error)")
        continue
      }
      do {
        let node = try RenderProjection.decodeNode(json)
        perKind[node.kind.typeName, default: 0] += 1
        decoded += 1
      } catch let e as FuaranDecodeError {
        XCTFail(
          "fixture \(fx.id) (\(fx.kind)) failed to decode: [\(e.code.rawValue)] \(e.path) — \(e.message)"
        )
      } catch {
        XCTFail("fixture \(fx.id): unexpected error \(error)")
      }
    }

    XCTAssertEqual(decoded, nodeFixtures.count, "some node fixtures failed to decode")

    // Coverage report (one line per NodeKind $type actually exercised).
    let report = perKind.keys.sorted().map { "\($0)=\(perKind[$0]!)" }.joined(separator: " ")
    print("CORPUS COVERAGE (\(perKind.count) kinds, \(decoded) fixtures): \(report)")
  }

  /// The node-round-trip family alone must exercise a broad slice of the flat
  /// vocabulary — a guard that the harness is really walking the corpus.
  func testNodeRoundTripFamilyCoversManyKinds() throws {
    guard let corpus = Self.corpusDir() else {
      throw XCTSkip("wire-format-fixtures corpus not found — skipping.")
    }
    let fixtures = try Self.loadFixtures(corpus).filter {
      $0.decoder == "node" && $0.kind == "node-round-trip"
    }
    var kinds = Set<String>()
    for fx in fixtures {
      let json = try String(
        contentsOf: corpus.appendingPathComponent(fx.inputFile), encoding: .utf8)
      kinds.insert(try RenderProjection.decodeNode(json).kind.typeName)
    }
    // The corpus exercises well over a dozen distinct node kinds.
    XCTAssertGreaterThanOrEqual(kinds.count, 15, "expected the node corpus to span many kinds")
  }
}
