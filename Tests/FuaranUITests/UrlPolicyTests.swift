// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The URL safety floor. These are the cases an embedding app would otherwise
// have to rediscover for itself — each one is a real evasion, not a synthetic
// permutation.

import XCTest

@testable import FuaranUI

final class UrlPolicyTests: XCTestCase {
  func testAllowedSchemesPass() {
    XCTAssertEqual(FuaranUrlPolicy.sanitize("https://example.org/a?b=1#c"), "https://example.org/a?b=1#c")
    XCTAssertEqual(FuaranUrlPolicy.sanitize("http://example.org"), "http://example.org")
    XCTAssertEqual(FuaranUrlPolicy.sanitize("mailto:a@example.org"), "mailto:a@example.org")
    XCTAssertEqual(FuaranUrlPolicy.sanitize("tel:+441234567890"), "tel:+441234567890")
  }

  func testRelativeAndEmptyPass() {
    XCTAssertEqual(FuaranUrlPolicy.sanitize(""), "")
    XCTAssertEqual(FuaranUrlPolicy.sanitize("/settings"), "/settings")
    XCTAssertEqual(FuaranUrlPolicy.sanitize("#section"), "#section")
    XCTAssertEqual(FuaranUrlPolicy.sanitize("?q=1"), "?q=1")
  }

  func testDangerousSchemesRefused() {
    XCTAssertNil(FuaranUrlPolicy.sanitize("javascript:alert(1)"))
    XCTAssertNil(FuaranUrlPolicy.sanitize("JAVASCRIPT:alert(1)"))
    XCTAssertNil(FuaranUrlPolicy.sanitize("vbscript:x"))
    XCTAssertNil(FuaranUrlPolicy.sanitize("data:text/html,<script>x</script>"))
    XCTAssertNil(FuaranUrlPolicy.sanitize("file:///etc/passwd"))
  }

  /// The evasion a `hasPrefix("javascript:")` check misses: the scheme candidate
  /// is scrubbed of ASCII whitespace and C0 controls before comparison.
  func testWhitespaceSplitSchemeIsStillClassified() {
    XCTAssertNil(FuaranUrlPolicy.sanitize("java\tscript:alert(1)"))
    XCTAssertNil(FuaranUrlPolicy.sanitize("  javascript:alert(1)  "))
    XCTAssertNil(FuaranUrlPolicy.sanitize("java\nscript:alert(1)"))
  }

  /// Protocol-relative and backslash forms — the two shapes that look relative
  /// and are not. `\\evil.example` is normalised to `//evil.example` by several
  /// URL parsers, so refusing only `//` is not enough.
  func testProtocolRelativeAndBackslashFormsRefused() {
    XCTAssertNil(FuaranUrlPolicy.sanitize("//evil.example/x"))
    XCTAssertNil(FuaranUrlPolicy.sanitize("\\\\evil.example\\x"))
    XCTAssertNil(FuaranUrlPolicy.sanitize("/\\evil.example"))
  }

  /// Deny by default — a scheme nobody listed is refused, not passed through.
  func testUnknownSchemeRefused() {
    XCTAssertNil(FuaranUrlPolicy.sanitize("myapp://open?id=1"))
    XCTAssertNil(FuaranUrlPolicy.sanitize("ftp://example.org/x"))
  }

  func testClassifyReportsWhy() {
    guard case .rejected(_, let reason) = FuaranUrlPolicy.classify("javascript:x") else {
      return XCTFail("expected a rejection")
    }
    XCTAssertTrue(reason.contains("javascript"), "the reason should name the scheme: \(reason)")
  }

  // ── The accessors on the decoded tree ────────────────────────────────────

  func testSanitizedHrefOnALiteralLink() throws {
    let json = """
      {"id":"l1","kind":{"$type":"Link","href":{"$type":"Static","value":"javascript:alert(1)"},
      "label":{"$type":"Literal","text":"Go"},"download":false}}
      """
    let node = try RenderProjection.decodeNode(json)
    guard case .link(let spec) = node.kind else { return XCTFail("expected a Link") }
    guard case .rejected = spec.sanitizedHref else {
      return XCTFail("a javascript: href must be rejected, got \(spec.sanitizedHref)")
    }
    // The raw value is still reachable — the floor is an accessor, not a filter
    // applied during decode; the projection stays a faithful view of the wire.
    XCTAssertEqual(spec.href.literalString, "javascript:alert(1)")
  }

  func testSanitizedHrefReportsDynamicForANonLiteralBinding() throws {
    let json = """
      {"id":"l2","kind":{"$type":"Link","href":{"$type":"State","key":"dest"},
      "label":{"$type":"Literal","text":"Go"},"download":false}}
      """
    let node = try RenderProjection.decodeNode(json)
    guard case .link(let spec) = node.kind else { return XCTFail("expected a Link") }
    XCTAssertEqual(spec.sanitizedHref, .dynamic)
    XCTAssertNil(spec.sanitizedHref.openable)
  }

  func testSanitizedNavigateRoute() {
    XCTAssertEqual(
      Action.navigate(route: "/dashboard").sanitizedNavigateRoute, .allowed("/dashboard"))
    guard case .rejected? = Action.navigate(route: "javascript:x").sanitizedNavigateRoute else {
      return XCTFail("a javascript: route must be rejected")
    }
    XCTAssertNil(Action.dispatch.sanitizedNavigateRoute)
  }
}
