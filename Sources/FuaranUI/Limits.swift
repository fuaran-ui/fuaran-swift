// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Decode-side resource limits for untrusted wire input (WIRE_FORMAT.md §21).
//
// WHY THIS EXISTS. The wire format promises that decoding is total: a malformed or
// hostile input yields a structured, typed refusal, never a crash and never an error
// outside the declared contract. That promise held on *semantics* here — a wrong-typed
// field, an unrecognised discriminator — and was silent on *shape*. This decoder is a
// recursive descent over a recursive document, and nothing bounded the recursion.
//
// Two measured symptoms this closes, both from the shared corpus: a 257-level
// bare-nesting document was refused as `WRONG_TYPE` (the parser built it happily and the
// node decoder then said "not an object"), which is the diagnosis §21.2 rule 2
// explicitly forbids — it sends an author to repair a shape that is not the problem; and
// a 25-level node tree, one past the limit, was ACCEPTED outright, so a document every
// rostered host refuses decoded here.

/// The five §21.1 figures.
///
/// They are **protocol numbers, not tuning knobs**: a document within them is one every
/// host MUST decode, and a document beyond them is one every host MUST refuse, with the
/// same typed error. Changing one is a format change — it moves in the specification and
/// across every host, never here alone. §21.4 records how ``maxNodeDepth`` was derived,
/// by bisecting each walk's true overflow depth on the reference host; it is not
/// re-derived per host, and a host that measures a tighter budget on some walk of its own
/// bounds that walk rather than proposing a smaller limit.
///
/// The two depth numbers are separate because neither derives from the other. One tree
/// level costs several JSON levels (a `Box` costs three — the node object, its `children`
/// array, the child object), and a structured payload slot nests freely WITHIN one node
/// and consumes no node depth at all. A host must never report a node-depth breach as a
/// syntax-depth breach: that diagnosis sends the author to repair the wrong thing.
public enum WireLimits {
  /// NODE nesting — the longest root-to-leaf chain of `Node` objects, the root counting
  /// as 1.
  public static let maxNodeDepth = 24

  /// SYNTACTIC nesting: every `{` and `[` counts, whether it carries a node, a spec, or a
  /// structured payload — and whether or not it is empty. The empty composite is the
  /// trap: an implementation that tests the bound *after* deciding a `{}` / `[]` is empty
  /// leaves exactly one level unmeasured, because the innermost level of a `[[[…]]]`
  /// payload is always the empty one. That off-by-one cost the host family a cross-host
  /// divergence, so the check here runs before the empty arm.
  public static let maxJSONDepth = 256

  /// Characters in a single decoded JSON string.
  public static let maxStringLength = 1_048_576

  /// Elements in a single JSON array, and members in a single JSON object.
  public static let maxArrayLength = 100_000

  /// `Node` objects in one document.
  ///
  /// Needed even once depth is bounded, because the depth, string and array limits
  /// together still admit a document that is hostile by being WIDE — 24 levels of 100 000
  /// siblings is within every other limit. Its cost is linear in the input, but the
  /// constant is not: a decoded tree is far larger in memory than the bytes that produced
  /// it.
  public static let maxNodes = 100_000
}

/// One decode call's §21 node-axis counters.
///
/// **Threaded through the decode walk rather than held in global or thread-local state**,
/// which is the one place this host has to differ from a host with a garbage-collected
/// runtime and mutable module scope. `RenderProjection.decodeNode` is public API, so
/// concurrent decode from several tasks is expected usage; shared mutable counters would
/// be a data race — and the damaging kind, since two decodes silently mis-bounding each
/// other shows up as a *valid* tree refused on a busy machine and never on a quiet one.
/// Under Swift 6 strict concurrency it would not compile at all without an unsafe escape
/// hatch, and reaching for one to bound untrusted input would be an odd trade.
///
/// So the state is created per call and passed down, exactly as the sibling Go host does
/// and for the same reason. The compiler is the checklist: a decoder that reaches `node`
/// without carrying the state is a build error, never a silent hole.
final class WireWalkState {
  private var nodeDepth = 0
  private var nodes = 0

  /// Called on the way DOWN, before the recursion that would breach the bound (§21.2 rule
  /// 4) — never afterwards by measuring the tree that was built. A check that runs after
  /// the walk it is meant to bound has already paid the cost it exists to refuse, and on
  /// a host with a hard stack limit it never runs at all.
  func enterNode(_ path: String) throws {
    if nodeDepth >= WireLimits.maxNodeDepth {
      throw FuaranDecodeError(
        code: .limitExceeded, path: path,
        message:
          "node nesting deeper than the wire limit maxNodeDepth = \(WireLimits.maxNodeDepth); "
          + "expected a tree nesting nodes no more than \(WireLimits.maxNodeDepth) levels deep")
    }
    nodes += 1
    if nodes > WireLimits.maxNodes {
      throw FuaranDecodeError(
        code: .limitExceeded, path: path,
        message:
          "the document holds more than the wire limit maxNodes = \(WireLimits.maxNodes) nodes; "
          + "expected a tree of no more than \(WireLimits.maxNodes) nodes in total")
    }
    nodeDepth += 1
  }

  /// Paired with ``enterNode(_:)`` through `defer`, which is what makes it correct on the
  /// ERROR paths — and on a default-deny decoder those are most of the paths. A counter
  /// that only decremented on success would tighten with every refusal until a valid tree
  /// was refused too.
  func exitNode() {
    nodeDepth -= 1
  }
}
