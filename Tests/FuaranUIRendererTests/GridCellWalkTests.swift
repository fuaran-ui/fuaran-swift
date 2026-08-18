// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Phase 752 — the SwiftUI grid cell walk. macOS-gated, because the renderer it
// exercises is behind `#if canImport(SwiftUI)`; the load-bearing lowering
// semantics are covered on every platform by `GridCellLoweringTests` instead, so
// what remains here is that the VIEW arms are reachable and do not trap.
//
// The bar this can honestly meet: constructing the body of a data-bound grid
// through every cell kind exercises each arm's construction path. SwiftUI views
// are not introspectable without a host app, so this asserts reachability and
// the coverage sink, not pixels.

import XCTest

#if canImport(SwiftUI)

  import SwiftUI

  @testable import FuaranUI
  @testable import FuaranUIRenderer

  @MainActor
  final class GridCellWalkTests: XCTestCase {
    /// One column per cell kind, so building the grid body walks every arm of
    /// the exhaustive `switch`.
    private func everyCellKindGrid() -> Node {
      let kinds: [CellKindErased] = [
        .text, .numeric, .date, .editable, .checkbox,
        .button(label: .literal("Go")),
        .buttonGroup(labels: [.literal("A"), .literal("B")]),
        .link, .pill,
        .tonedPill(field: "status", map: ["Delayed": .warning], defaultTone: .subdued),
        .progress, .custom,
      ]
      let columns = kinds.enumerated().map { i, kind in
        ColumnErased(
          format: .none, kind: kind, label: "c\(i)", width: .auto, value: nil, field: "status")
      }
      return Node(
        id: "grid",
        kind: .dataGrid(
          GridSpec(
            columns: columns, editable: false, source: .query(name: "rows", dependsOn: []),
            onRowClick: nil, rowKey: nil, rowKeyField: "status", staticRows: nil,
            sortStateKey: nil, pageStateKey: nil, editStateKey: nil, pageSize: nil,
            defaultSort: nil)))
    }

    private func rows(_ values: [String]) -> ResolvedRows {
      .rows(values.map { .object(["status": .string($0)]) })
    }

    func testEveryCellKindArmIsReachable() {
      let ctx = BindingContext(
        rows: ["grid": rows(["Delayed", "Unknown"])], coverage: RenderCoverage())
      // Building the body walks the grid arm, which walks every column's cell
      // arm for every row. A missing arm is a compile error; a trapping one
      // fails here.
      _ = fuaranNodeBody(everyCellKindGrid(), ctx)
      XCTAssertEqual(ctx.coverage?.kinds["DataGrid"], 1)
      XCTAssertEqual(ctx.coverage?.fallbacks, [], "no cell kind may fall through")
    }

    func testTheThreeRowOutcomesEachBuildADistinctBody() {
      // Each outcome must reach the renderer as itself. The bodies differ; what
      // is asserted here is that none of the three traps and all are reachable.
      for outcome: ResolvedRows in [rows(["Delayed"]), .rows([]), .notResolved, .noRowSource] {
        let ctx = BindingContext(rows: ["grid": outcome], coverage: RenderCoverage())
        _ = fuaranNodeBody(everyCellKindGrid(), ctx)
        XCTAssertEqual(ctx.coverage?.fallbacks, [])
      }
    }

    func testAGridWithNoSeededRowsStillBuilds() {
      // The absent-entry path (reads as `.notResolved` → loading surface).
      let ctx = BindingContext(coverage: RenderCoverage())
      _ = fuaranNodeBody(everyCellKindGrid(), ctx)
      XCTAssertEqual(ctx.coverage?.kinds["DataGrid"], 1)
    }
  }

#else

  final class GridCellWalkTests: XCTestCase {
    func testGridCellWalkSkipsWhenSwiftUIAbsent() throws {
      throw XCTSkip(
        "SwiftUI not available — the cell walk is a SwiftUI leg; the lowering semantics are covered by GridCellLoweringTests on every platform."
      )
    }
  }

#endif
