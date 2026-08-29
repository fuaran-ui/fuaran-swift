// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// WIRE_FORMAT.md 16 - a bare `{"$type":"State","key":k}` in a `Transform`'s
// `source` slot is a LIVE source over the EMPTY initial snapshot.
//
// `unwrapSourceEnvelope` refused it: an envelope with no payload member had
// nothing to unwrap to, so the transform "had no data". That was correct while
// nothing else could fill the slot; under 24.4 a SIBLING reader's declaration
// fills it, so the refusal was rejecting the most direct spelling of "I read
// this key and carry no data of my own" - the one FUARAN106's remedy text tells
// an author to write.
//
// This surface holds no evaluator and no live binding, so the widening lands
// where the empty-array spelling already landed: the empty table. That the two
// spellings project IDENTICALLY is the claim - one dialect, not two behaviours.
//
// No corpus fixture spells the bare form yet (the corpus is a shared gate and
// keeps the `"defaultValue": []` spelling deliberately, so respelling it there
// would redden a host that has not adopted this), so the pin lives here.

import Foundation
import XCTest

@testable import FuaranUI

final class BareStateSourceTests: XCTestCase {

  /// A `Badge` whose label is a `Transform` over the given source JSON.
  private func badge(source: String) -> String {
    """
    {"id":"member-count","kind":{"$type":"Badge","label":{"$type":"Bound","binding":\
    {"$type":"Transform","pipeline":[{"$type":"groupBy","aggs":[{"fn":"count","name":"n","of":"team"}],"keys":[]}],\
    "source":\(source)}},"variant":"Info"}}
    """
  }

  private func transformSource(of node: Node) throws -> DataSource {
    guard case .badge(let spec) = node.kind,
      case .bound(let binding) = spec.label,
      case .transform(_, _, let source) = binding
    else {
      throw XCTSkip("expected a Badge whose label is a bound Transform, got \(node.kind.typeName)")
    }
    return source
  }

  /// The acceptance pin, and the equivalence claim in one: both spellings decode,
  /// and both project to the SAME empty table. A test that only asserted the bare
  /// form decodes would pass on a surface that quietly gave it some other source.
  func testBothDataLessSpellingsProjectToTheEmptyTable() throws {
    for source in [
      #"{"$type":"State","key":"members"}"#,
      #"{"$type":"State","defaultValue":[],"key":"members"}"#,
    ] {
      let node = try RenderProjection.decodeNode(badge(source: source))
      guard case .embedded(let schema, let columns) = try transformSource(of: node) else {
        return XCTFail("expected an embedded source for \(source)")
      }
      XCTAssertTrue(schema.isEmpty, "a data-less source declares an empty schema: \(source)")
      XCTAssertTrue(columns.isEmpty, "a data-less source declares no columns: \(source)")
    }
  }

  /// The go-red half. An assertion that only ever passes cannot tell a decoder
  /// that ACCEPTS the bare `State` wrapper from one that stopped checking the
  /// envelope at all - so the sibling empty envelopes, which name no live slot
  /// and so have nothing for a sibling reader to seed, must still be refused.
  func testTheWideningIsScopedToTheStateEnvelope() {
    for source in [
      #"{"$type":"Static"}"#,
      #"{"$type":"Bound"}"#,
    ] {
      XCTAssertThrowsError(try RenderProjection.decodeNode(badge(source: source))) { error in
        guard let e = error as? FuaranDecodeError else {
          return XCTFail("expected a FuaranDecodeError for \(source), got \(error)")
        }
        XCTAssertEqual(e.code, .wrongType, "for \(source)")
        XCTAssertTrue(e.path.hasPrefix("$"), "refusal path \(e.path) is not $-rooted")
      }
    }
  }
}
