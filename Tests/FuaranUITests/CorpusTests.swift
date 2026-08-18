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
    let expectedErrorCode: String?
    let expectedPath: String?
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
      var code: String? = nil
      if case .string(let c)? = f["expectedErrorCode"] { code = c }
      var path: String? = nil
      if case .string(let p)? = f["expectedPath"] { path = p }
      out.append(
        Fixture(
          id: id, kind: kind, decoder: decoder, inputFile: inputFile,
          expectedErrorCode: code, expectedPath: path))
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

  /// The REJECT leg: every malformed `node`-decoder fixture must fail to decode
  /// with the corpus's canonical error code and a `$`-rooted path carrying the
  /// expected prefix.
  ///
  /// This is the negative half of the decode contract, and it was missing while
  /// the positive half was gated — which is the worse of the two omissions to
  /// have. A decoder that accepts every valid tree and also accepts malformed
  /// ones is not "lenient"; it hands the embedding app a projection whose typed
  /// slots do not mean what their types say, and nothing in the render path
  /// would ever notice.
  ///
  /// **Path matching is by PREFIX**, mirroring the reference host's own reject
  /// leg. A discriminator refusal legitimately reports at `<path>.$type` where
  /// the corpus records `<path>`, so an equality check would fail on a correct
  /// message; the prefix rule keeps the assertion strict about *where* without
  /// pinning a suffix the spec does not fix.
  ///
  /// **Two documented, justified exclusions** — neither a filter over the reject
  /// family, both a decoder that does not exist on this surface:
  ///
  ///  - `decoder == "op"` fixtures. This surface has no `TreeOp` decoder at all
  ///    — the Rust core owns apply and mutation, and a render projection never
  ///    sees an op. There is nothing here to feed them to.
  ///  - the `envelope-reject` family (a separate manifest kind, not part of the
  ///    reject family this test covers). It asserts `FOREIGN_PROFILE`, which
  ///    belongs to versioning-envelope negotiation — a codec-host obligation
  ///    this decode-only surface does not carry and does not model.
  func testEveryRejectFixtureIsRefused() throws {
    guard let corpus = Self.corpusDir() else {
      throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
    }
    let rejects = try Self.loadFixtures(corpus).filter {
      $0.kind == "reject" && $0.decoder == "node"
    }
    XCTAssertGreaterThan(rejects.count, 0, "the corpus declared no node reject fixtures")

    var failures: [String] = []
    for fx in rejects {
      let expectedCode = fx.expectedErrorCode ?? ""
      let expectedPath = fx.expectedPath ?? "$"
      let json = (try? String(contentsOf: corpus.appendingPathComponent(fx.inputFile), encoding: .utf8)) ?? ""
      do {
        _ = try RenderProjection.decodeNode(json)
        failures.append(
          "\(fx.id): decode ACCEPTED a malformed input (expected \(expectedCode) at \(expectedPath))")
      } catch let e as FuaranDecodeError {
        if e.code.rawValue != expectedCode {
          failures.append(
            "\(fx.id): wrong code — expected \(expectedCode), got \(e.code.rawValue) at \(e.path): \(e.message)"
          )
        } else if !e.path.hasPrefix(expectedPath) {
          failures.append(
            "\(fx.id): wrong path — expected prefix \(expectedPath), got \(e.path)")
        }
      } catch {
        failures.append("\(fx.id): threw an untyped error \(error) (expected FuaranDecodeError)")
      }
    }

    XCTAssertTrue(
      failures.isEmpty,
      "\(failures.count) of \(rejects.count) reject fixtures failed:\n" + failures.joined(separator: "\n")
    )
    print("CORPUS REJECT LEG: \(rejects.count) fixtures refused with the canonical code + path")
  }

  /// The SANITIZATION family (`WIRE_FORMAT.md` §19 + §22) — semantic invariants.
  ///
  /// Unlike every other family here this one is NOT byte-parity: the markup a host
  /// emits around a URL differs legitimately between an F# React renderer, a Go
  /// static-HTML emitter and this native projection, so comparing bytes would pin
  /// accidents rather than the contract. The family states invariants instead, and
  /// each case carries the URL parser's own verdict (`off-origin` / `same-origin` /
  /// `scheme-refused`), so a "must reject this" claim is backed by what a real
  /// parser does rather than by a reading of the specification.
  ///
  /// ONE group applies to this surface, and the reasons the others do not are
  /// RECORDED rather than left to inference:
  ///
  ///  - `url-floor` (§19) — APPLICABLE and asserted. `Link.href`, `Image.src` and
  ///    `Navigate.route` all reach the embedding app, which may hand one to
  ///    `UIApplication.open` or a web view it adds later, so the scheme floor is
  ///    this surface's real exposure.
  ///  - `markdown-body`, `text-source` (§22) — NOT APPLICABLE. There is no markup
  ///    emission and no HTML-parsing attributed-string path anywhere in this
  ///    projection: text reaches a SwiftUI `Text` as CONTENT, so there is no markup
  ///    for a payload to break out of. A structural property of rendering a decoded
  ///    tree into native views, not a gap.
  ///  - `extra-attributes` (§22) — NOT APPLICABLE. The `ExtraAttributes` seam does
  ///    not exist on a decoded tree here, and every attribute this renderer sets is
  ///    renderer-controlled. (The same declaration `fuaran-go` makes, for the same
  ///    reason.)
  ///
  /// The CLAIMED-GROUPS GUARD is the load-bearing part. Without it a group added to
  /// the corpus later would read as covered while being silently untested — the exact
  /// shape §22.2 refuses — so a group this leg neither runs nor names as
  /// not-applicable FAILS.
  func testSanitizationFamilyInvariants() throws {
    guard let corpus = Self.corpusDir() else {
      throw XCTSkip("wire-format-fixtures corpus not found — standalone checkout; skipping.")
    }
    let notApplicable = [
      "markdown-body":
        "no markup emission and no HTML-parsing text path — text renders as content",
      "text-source":
        "no markup emission and no HTML-parsing text path — text renders as content",
      "extra-attributes": "the ExtraAttributes seam does not exist on a decoded tree here",
    ]

    let manifestURL =
      corpus
      .appendingPathComponent("sanitization")
      .appendingPathComponent("manifest.json")
    let text = try String(contentsOf: manifestURL, encoding: .utf8)
    guard case .object(let root) = try JSON.parse(text),
      case .array(let groups)? = root["groups"]
    else {
      return XCTFail("sanitization/manifest.json carries no `groups` array")
    }

    var urlFloorCases = 0
    var failures: [String] = []
    for g in groups {
      guard case .object(let group) = g, case .string(let gid)? = group["id"] else { continue }
      guard gid == "url-floor" else {
        guard let reason = notApplicable[gid] else {
          return XCTFail(
            "sanitization group '\(gid)' is neither run nor declared not-applicable — it would read as covered while being untested"
          )
        }
        // Logged, not silent: a reader sees WHY the group did not execute rather than
        // inferring it from an absence.
        print("sanitization/\(gid): NOT APPLICABLE — \(reason)")
        continue
      }
      guard case .array(let cases)? = group["cases"] else {
        return XCTFail("the sanitization url-floor group carries no `cases` array")
      }
      urlFloorCases = cases.count
      for c in cases {
        guard case .object(let kase) = c,
          case .string(let id)? = kase["id"],
          case .string(let input)? = kase["input"],
          case .string(let invariant)? = kase["invariant"]
        else { continue }
        var expected: String? = nil
        if case .string(let e)? = kase["expected"] { expected = e }
        let got = FuaranUrlPolicy.sanitize(input)
        switch invariant {
        case "reject":
          if let got {
            failures.append("\(id): the floor ACCEPTED \(input.debugDescription) as \(got.debugDescription)")
          }
        case "accept":
          guard let got else {
            failures.append("\(id): the floor REJECTED \(input.debugDescription), which resolves same-origin")
            continue
          }
          // The emitted form is the §19 rule-1 normalised one, which is NOT always the
          // input: an accepted URL carrying an interior tab loses it, because that is
          // what a parser would have read anyway.
          if let expected, got != expected {
            failures.append(
              "\(id): expected the normalised form \(expected.debugDescription), got \(got.debugDescription)"
            )
          }
        default:
          failures.append("\(id): unknown invariant '\(invariant)'")
        }
      }
    }

    XCTAssertGreaterThan(urlFloorCases, 0, "the sanitization url-floor group enumerated ZERO cases")
    XCTAssertTrue(
      failures.isEmpty,
      "\(failures.count) of \(urlFloorCases) url-floor cases failed:\n"
        + failures.joined(separator: "\n"))
    print("SANITIZATION url-floor: \(urlFloorCases) cases asserted against the URL floor")
  }
}
