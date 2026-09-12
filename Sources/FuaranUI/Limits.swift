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

/// The §21 figures — five structural bounds from §21.1, plus the two VALUE bounds §21.8
/// and §21.9 added later.
///
/// The count is not restated here on purpose: it was "five" while the type held six, and
/// then while it held seven, because a number in prose beside a list is one more thing to
/// keep in step with the list.
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

  /// Maximum `ColExpr` nodes in ONE expression (§21.8).
  ///
  /// The other limits bound the SIZE of a document; this one bounds what a host
  /// must EVALUATE, which is why it exists beside them rather than being
  /// derived from them. Counted per expression rather than per document — a
  /// tree may carry many expressions, each bounded here, with the whole still
  /// bounded by `maxNodes`.
  ///
  /// Its scope is EVERY expression a decoded document can name (Phase 1662): a
  /// `Binding.expr`'s expression, and the `ColExpr` a `Binding.transform`
  /// PIPELINE embeds — a `derive` step's `expr`, a `filter` step's `pred`.
  /// Those positions are the whole surface, and that is a fact about the step
  /// vocabulary rather than a hope: `filter` and `derive` are the only steps
  /// carrying an expression, and a `join` / `union` / `intersect` / `except`
  /// operand is a data source, never another pipeline.
  ///
  /// This comment carried the OPPOSITE rule until Phase 1677 — "its scope is
  /// `Binding.expr` and nothing else", with a pipeline's cost said to be
  /// bounded already by its own rows and steps. That reasoning is superseded
  /// rather than merely out of date: a pipeline's rows bound how MANY times an
  /// expression is evaluated, never how large the expression is, so naming the
  /// pipeline positions as excluded made the bound bypassable by wrapping the
  /// expression in a `transform` — the one shape from which a decoded document
  /// could still name an unbounded evaluation. §21.8 states the consequence
  /// outright, because closing it refuses documents this projection previously
  /// accepted: no profile boundary, and no grandfathering.
  public static let maxExprNodes = 512

  /// Maximum `rows` on ONE `Skeleton` node (§21.9).
  ///
  /// The first bound here that a document breaches with four digits rather than
  /// with bulk, and ``maxExprNodes``'s argument applies more sharply because
  /// this is not even an evaluation — the rows are simply not present in the
  /// input. A renderer emits one placeholder row per count, so
  /// `{"$type":"Skeleton","rows":100000000}` is a document well inside every
  /// other limit (a handful of bytes, one node, three JSON levels) that names a
  /// hundred million rendered rows. Every structural limit is satisfied, and
  /// each is satisfied because none of them is looking at the VALUE.
  ///
  /// **§7.1 decides FIRST, and the ORDER is the whole of what keeps the two
  /// rules apart.** §7.1 governs what a typed integer slot can HOLD, and
  /// `2147483647` is finite, fraction-free and inside signed 32-bit, so §7.1
  /// admits it; this bound then refuses it for the work it names. So a value
  /// that is not an integer at all stays `WRONG_TYPE` and never a limit breach,
  /// and a 32-bit-valid value past the bound is `LIMIT_EXCEEDED` and never a
  /// wrong type. Reading this as a narrowing of the slot's TYPE also refuses
  /// the at-the-bound document every host must accept — one misreading,
  /// breaching §21.2 rules 1 and 2 at once, which is why both halves are corpus
  /// fixtures.
  ///
  /// **An UPPER bound only, and the omission is deliberate.** A negative `rows`
  /// is not a resource breach — nothing expands — and answering
  /// `LIMIT_EXCEEDED` for it would be the actively-wrong diagnosis: it tells an
  /// author to come back under a ceiling when what they wrote is a count that
  /// cannot be drawn at all. That is an authoring defect, and it belongs to the
  /// pre-emit validator family, which this decode-only projection over the Rust
  /// reference core does not carry.
  public static let maxSkeletonRows = 10_000
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
  /// The §21.5 item axis — see ``enterItem(_:)``. Separate from ``nodeDepth`` because a
  /// whole hierarchy lives inside one node and consumes no node depth at all.
  private var itemDepth = 0

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

  /// §21.5 (Phase 1120) — the THIRD recursion axis, bounded separately for the reason the
  /// op axis is.
  ///
  /// A `Tree`'s rows nest inside ONE node, so ``enterNode(_:)`` cannot see them at all
  /// however deep they go, and at roughly two JSON levels per row the syntactic bound is
  /// not reached either — the same two false comforts the `TreeOp.Batch` axis sprang, at a
  /// new slot. So item nesting is counted from the root row list on its own axis, and a
  /// breach is refused on the way DOWN.
  ///
  /// **The FIGURE is ``WireLimits/maxNodeDepth``, reused rather than a sixth limit
  /// minted.** These frames cost what the node decoder's frames cost, so a second number
  /// would be two figures for one per-frame budget and every host would have to carry
  /// both. The rule generalises past both axes: *any* self-referential record this format
  /// grows is bounded by that figure on its own axis, on the day it lands.
  ///
  /// Note it does NOT feed ``WireLimits/maxNodes``: a `TreeItem` is not a `Node`, and
  /// counting one as the other would let a wide hierarchy exhaust a budget that exists to
  /// bound a different population.
  func enterItem(_ path: String) throws {
    if itemDepth >= WireLimits.maxNodeDepth {
      throw FuaranDecodeError(
        code: .limitExceeded, path: path,
        message:
          "tree-item nesting deeper than the wire limit maxNodeDepth = "
          + "\(WireLimits.maxNodeDepth); expected a hierarchy nesting rows no more than "
          + "\(WireLimits.maxNodeDepth) levels deep")
    }
    itemDepth += 1
  }

  /// Paired with ``enterItem(_:)`` through `defer`, on the ``exitNode()`` argument.
  func exitItem() {
    itemDepth -= 1
  }

  /// Paired with ``enterNode(_:)`` through `defer`, which is what makes it correct on the
  /// ERROR paths — and on a default-deny decoder those are most of the paths. A counter
  /// that only decremented on success would tighten with every refusal until a valid tree
  /// was refused too.
  func exitNode() {
    nodeDepth -= 1
  }
}
