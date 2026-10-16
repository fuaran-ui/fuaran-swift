// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The hand-written half of the per-kind spec vocabulary.
//
// Every kind spec, record and tagged union the IDL declares is GENERATED into
// `Model.generated.swift` (Phase 2299). What stays here is the small set of
// types whose Swift representation is deliberately not a function of the IDL
// type — each named, with its reason, as a `handWritten` entry in
// `Sources/FuaranUIIdlGen/Dialect.swift` — and the conveniences the projection
// builds over generated types. Layout containers hold `[Node]`; the structural
// kinds hold single `Node`s (behind the indirect `NodeKind`, so the value graph
// stays finite).

import Foundation

// ── Conveniences over generated types ────────────────────────────────────────

extension MediaKind {
  /// The wire `$type` of the variant, inside `kind.kind`.
  public var typeName: String {
    switch self {
    case .video: return "Video"
    case .audio: return "Audio"
    }
  }
}

extension DrawStyle {
  public static let empty = DrawStyle(
    fill: nil, stroke: nil, strokeWidth: nil, opacity: nil,
    textAnchor: nil, fontSize: nil, emphasis: nil, fontFamily: nil, markId: nil,
    rotation: nil, tip: nil)
}

extension EffectClass {
  /// The declared default of `FragmentDecl.effect`, applied by the decoder when
  /// the slot is omitted.
  public static let pureDeterministic = EffectClass(
    determinism: .deterministic, hostEffect: .pure)
}

// ── Hand-written: a `Switch` case (the `SwitchCase` dialect entry) ───────────

public enum SwitchCondition: Equatable, Sendable {
  /// Compares the switch's resolved selector against a literal string.
  case match(String)
  /// Evaluates a `Binding<bool>` and takes the case on a RESOLVED `true` only —
  /// a resolved `false`, an unresolved binding and an errored one all fall
  /// through. There is no truthiness rule: `0`, `""` and `"false"` are refused
  /// by the coercion rather than read as `false`.
  ///
  /// It consults no selector at all, so a switch whose cases are ALL predicates
  /// needs no `on` and has no state key for anything to write.
  case when(Binding)
}

public struct SwitchCase: Equatable, Sendable {
  /// EXACTLY ONE of `match` and `when` is present (§3.6) — both together and
  /// neither at all are decode errors, the same shape and the same reasoning as
  /// `setState`'s `value` / `valueFrom` pair.
  ///
  /// A case naming no condition is not a case that never matches; it is a
  /// document whose author meant something the wire cannot say, and a host that
  /// silently skipped it would render the `default` and report nothing. A
  /// precedence rule for "both" would have to be specified, agreed on every
  /// host and remembered by every author, for a document nobody meant to write.
  public var condition: SwitchCondition
  public var child: Node
}

// ── Hand-written: fragment arguments (the `FragmentArg` dialect entry) ───────

/// One fragment argument: a scalar value, or a slot filled with a tree. The
/// IDL's four scalar cases (`Int`, `Float`, `Bool`, `Str`) fold into
/// `value(FragmentScalar)`, so a reader branches once on value-versus-slot and
/// once more, only where it needs to, on the scalar.
public enum FragmentArg: Equatable, Sendable {
  case value(FragmentScalar)
  case slot(tree: Node)
}

/// A named `FragmentArg` entry (fragment-ref args / mount inputs). A named
/// struct rather than a `(String, FragmentArg)` tuple so `Equatable` synthesis
/// works.
public struct FragmentArgEntry: Equatable, Sendable {
  public var name: String
  public var arg: FragmentArg
  public init(name: String, arg: FragmentArg) {
    self.name = name
    self.arg = arg
  }
}
