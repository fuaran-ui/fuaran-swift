// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// Decoder robustness fuzz — this host's leg.
//
// The threat model's load-bearing claim is that decoding is TOTAL: a malformed or
// hostile input yields a structured, typed error, never a crash and never a hang.
// Until a fuzz leg exists on a host, that claim rests there on a CURATED reject
// corpus — inputs an author chose, which is evidence about the author's
// imagination rather than about the decoder.
//
// ## Why this is a hand-written harness
//
// This package declares NO third-party dependencies, and the toolchain ships no
// coverage-guided fuzzer reachable from `swift test`. What is kept from such a
// tool is what actually matters — a deterministic, replayable generator over the
// named input families, and a minimiser — at the cost of losing coverage-guided
// mutation, which is stated here rather than left to be assumed.
//
// ## The invariants, per input — and which of them PORT to this surface
//
// 1. **Totality** — `RenderProjection.decodeNode` returns a `Node` or throws
//    exactly `FuaranDecodeError`. Anything else thrown is a counterexample.
//    There is only ONE typed error type on this surface: the JSON parser raises
//    `FuaranDecodeError` too (`INVALID_JSON` for syntax, `LIMIT_EXCEEDED` for a
//    §21 bound), so there is no separate syntax-error type to admit.
//
//    **The Swift boundary, stated rather than smoothed over.** A Swift *trap* —
//    a force-unwrapped nil, an out-of-range index, an arithmetic overflow, a
//    failed `Int(Double)` conversion — is NOT a catchable error. It calls
//    `fatalError` and terminates the process. So this harness cannot report a
//    trap the way the reference host's `catch_unwind` reports a panic: the test
//    runner dies, the gate goes red with the trap's own message, and nothing is
//    minimised. That is a real gap in this leg's diagnostic power, and it is why
//    the one trap this leg found is pinned by a direct test on the typed refusal
//    that replaced it, rather than left to the stream.
//
// 2. **Termination** — the decode returns inside a per-input wall-clock budget.
//
// 3. **Bounded work** — NOT PORTABLE HERE, in either of the two forms the
//    sibling legs use, and it is not faked. The reference host installs a
//    counting global allocator and measures allocated bytes for real; there is
//    no portable equivalent reachable from a Swift test on every platform this
//    package supports. The Go and TypeScript legs substitute a *canonical output
//    amplification* proxy — and that substitute needs an ENCODER, which this
//    surface does not have (see 4). So the only bounded-work signal here is the
//    time budget in 2. Two shapes are therefore invisible to this leg: a decoder
//    that allocates heavily and returns quickly, and one that amplifies its
//    output. Neither claim is made.
//
// 4. **Fixed point** — NOT PORTABLE HERE. `RenderProjection` is decode-only:
//    this surface reads canonical wire JSON produced elsewhere and never
//    canonically encodes, so there is no `encode(decode(x)) == canonical(x)` to
//    assert. Asserting some hand-rolled re-serialisation instead would pin the
//    harness's own encoder, not the decoder's, and would report a *pass* for a
//    property nobody checked. It is skipped, and named as skipped.
//
// 4'. **Decode determinism** — the SUBSTITUTE, offered under its own name and
//    NOT as the fixed point. An accepted input decoded twice must yield an equal
//    `Node`. It is strictly weaker than the fixed point (it cannot see an encoder
//    that loses information, because there is no encoder) and strictly real (it
//    catches order-dependent or shared-state decoding, which the §21 per-call
//    `WireWalkState` exists to prevent).
//
// ## Entry points
//
// ONE: `decodeNode`. This surface has no `TreeOp` decoder at all — the Rust
// reference core owns apply and mutation, and a render projection never sees an
// op — so the sibling legs' second door has no counterpart here. The corpus's
// `ops/` fixtures are still loaded as SEED TEXT: an op document fed to the node
// decoder is a well-formed near-miss of exactly the kind a generator is bad at
// inventing.
//
// ## Two defects this leg found on its first run, fixed in the same phase
//
// 1. `Decode.int` (`Sources/FuaranUI/RenderProjection.swift`) converted a decoded
//    JSON number with `Int(n.rounded(.towardZero))` under no finiteness or range
//    guard, and `Int(Double)` TRAPS — uncatchably — on a non-finite value or one
//    outside `Int`'s range. `1e999` in any of the vocabulary's integer slots ended
//    the host process. It now refuses by type, on the slot, and
//    `testNonFiniteAndOutOfRangeIntegerSlotsAreRefusedByType` pins the four
//    minimised documents the leg reported. The leg carried a QUARANTINE for those
//    inputs until the fix landed; it is gone, and every generated input is decoded.
//
// 2. Three decode sites mapped a Swift `Dictionary` into an ORDER-SENSITIVE array
//    without sorting it — `Decode.fragmentArgs` (`FragmentRef.args`,
//    `Mount.inputs`) and the `TextSource.I18n.args` arm — so the same bytes decoded
//    to a different tree on each call (twelve decodes, five orders), and a document
//    with two invalid entries was refused with a different CODE at a different
//    PATH from run to run. They sort by name now, as `Transform.params` and
//    `jvalMap` already did, and `testMapDecodedSlotsDecodeInAStableOrder` pins
//    both the order and the refusal. Invariant 4′ carried an exemption for those
//    documents until the fix landed; it is gone too.
//
// What survives of the exemption machinery is the one case that is NOT a defect:
// a tree carrying a `"NaN"` float sentinel is never `==` to itself, because
// IEEE-754 says so, and comparing two decodes of one would report a
// counterexample against a decoder that did nothing wrong.
//
// ## Determinism, and the replay contract
//
// SplitMix64, hand-rolled — replayability is the whole point of the seed, and the
// standard library has no seedable PRNG. The default seed is 1023, matching the
// sibling legs. Every branch draws from the same generator, so ADDING a family
// renumbers the stream; that is why a reported find carries its payload too and
// replay is the backstop rather than the primary record.
//
// Long run, and the machine-readable evidence a scheduled job collects:
//
//     FUARAN_FUZZ_LONG=1 FUARAN_FUZZ_ITERATIONS=250000 \
//       FUARAN_FUZZ_EVIDENCE=<file> swift test --filter DecoderFuzzTests
//
// ## Where the alphabets differ from the sibling hosts
//
// A Swift `String` is validated UTF-8, so a lone UTF-16 surrogate cannot be a
// CHARACTER in a generated payload at all — the type system removes the case
// rather than the harness declining to test it, exactly as it does on the Rust
// host. What is fuzzed instead, and heavily, is the six-character ESCAPE TEXT
// that DENOTES one: that is the decoder's unescape path, which is the surface a
// lone surrogate actually reaches here, and it is pinned directly by the
// surrogate unit tests at the foot of this file.
//
// **No literal escape sequence appears in this source.** Every one is built by
// `fuzzEsc` / `fuzzChar` in `DecoderFuzzEscapes.swift`, which records why at
// length: an escape literal that is silently resolved into the character it
// denotes inverts the test while every assertion still passes.

import Foundation
import XCTest

@testable import FuaranUI

// ─── Deterministic PRNG ──────────────────────────────────────────────────────

private let fuzzGolden: UInt64 = 0x9E37_79B9_7F4A_7C15

/// SplitMix64. Identical constants and shifts to every sibling leg, so a seed
/// means the same thing when a finding is carried between hosts.
struct FuzzRng {
  private var s: UInt64

  init(seed: UInt64) { self.s = seed == 0 ? fuzzGolden : seed }

  mutating func nextU64() -> UInt64 {
    s = s &+ fuzzGolden
    var z = s
    z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
    z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
    return z ^ (z >> 31)
  }

  /// Uniform in `[0, n)`; `0` for a non-positive `n`, so no caller has to guard.
  mutating func next(_ n: Int) -> Int {
    n <= 1 ? 0 : Int(nextU64() % UInt64(n))
  }

  /// Uniform in `[lo, hi]`, inclusive.
  mutating func range(_ lo: Int, _ hi: Int) -> Int {
    hi <= lo ? lo : lo + next(hi - lo + 1)
  }

  mutating func boolean() -> Bool { nextU64() % 2 == 1 }

  mutating func pick<T>(_ xs: [T]) -> T { xs[next(xs.count)] }
}

// ─── Payloads are SCALAR ARRAYS, not Strings ─────────────────────────────────
//
// Every mutator slices, splices and truncates. `String` indices are not integers,
// and `String.Index` arithmetic is both slow and easy to get wrong; a scalar array
// makes "no cut ever splits a character" true BY CONSTRUCTION rather than by a
// boundary check at each site — the class of bug the reference host has to guard
// against explicitly at every mutator.

typealias FuzzPayload = [Unicode.Scalar]

func fuzzScalars(_ s: String) -> FuzzPayload { Array(s.unicodeScalars) }
func fuzzText(_ p: FuzzPayload) -> String { String(String.UnicodeScalarView(p)) }

// ─── Corpus seeds + vocabulary ───────────────────────────────────────────────

/// Built-in seeds, so the harness is self-sufficient: the go-red self-test must
/// not depend on the shared corpus being checked out alongside this repo in order
/// to prove that the harness can fail. The same nine the sibling legs carry, the
/// two op documents included — see the entry-points note in the header.
let fuzzBuiltinSeeds: [String] = [
  #"{"id":"a","kind":{"$type":"Heading","level":1,"text":"x","variant":"Standard"}}"#,
  #"{"id":"b","kind":{"$type":"Box","children":[],"layout":{"$type":"Auto"},"role":"Group"}}"#,
  // Two hashes: the payload itself contains `"#`, which closes a single-hash raw
  // string mid-literal.
  ##"{"id":"c","kind":{"$type":"Markdown","source":"# hi"}}"##,
  #"{"$type":"RemoveNode","path":["a"]}"#,
  #"{"$type":"Batch","ops":[]}"#,
  "{}",
  "[]",
  "null",
  "",
]

let fuzzFallbackVocab: [String] = [
  "Box", "Heading", "Markdown", "Metric", "Badge", "Form", "Button", "DataGrid", "Chart",
  "Custom",
]

enum FuzzCorpus {
  /// Reuses the corpus locator the render-coverage harness already owns rather
  /// than minting a second one that can go stale independently. A missing corpus
  /// is NOT a failure here — unlike the conformance gate, this harness degrades to
  /// the built-in seed pool, which is a narrower run rather than a vacuous one
  /// (and the seed count is on the evidence line, so the narrowing is visible).
  static func directory() -> URL? { CorpusTests.corpusDir() }

  /// Every corpus payload the harness can find, as raw text. READ-ONLY by
  /// construction: the fuzz never writes into the corpus. A REJECT fixture is the
  /// most productive seed there is, since it already sits one edit away from the
  /// refusal boundary the fuzz is probing.
  static func seeds(_ corpus: URL?) -> [String] {
    var seeds = fuzzBuiltinSeeds
    guard let corpus else { return seeds }
    for family in ["nodes", "ops", "reject", "lenient"] {
      let dir = corpus.appendingPathComponent(family)
      guard let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else {
        continue
      }
      for name in names.sorted()
      where name.hasSuffix(".json") && !name.hasSuffix(".expected.json") {
        if let raw = try? String(contentsOf: dir.appendingPathComponent(name), encoding: .utf8) {
          seeds.append(raw)
        }
      }
    }
    return seeds
  }

  /// The wire vocabulary the near-miss generators aim just beside, read from the
  /// corpus MANIFEST so a newly-admitted kind is fuzzed the day it lands rather
  /// than whenever someone remembers to extend a literal list here. Parsed with
  /// the host's own JSON layer — a manifest this host cannot read is a finding in
  /// its own right, so the fallback is a narrower harness rather than a silent
  /// success.
  static func vocabulary(_ corpus: URL?) -> [String] {
    guard let corpus,
      let raw = try? String(
        contentsOf: corpus.appendingPathComponent("manifest.json"), encoding: .utf8),
      case .object(let root)? = try? JSON.parse(raw),
      case .array(let kinds)? = root["kinds"]
    else { return fuzzFallbackVocab }
    let names: [String] = kinds.compactMap {
      if case .string(let s) = $0 { return s }
      return nil
    }
    return names.isEmpty ? fuzzFallbackVocab : names
  }
}

// ─── Alphabets ───────────────────────────────────────────────────────────────

/// Note what is ABSENT relative to the sibling hosts' lists: the lone UTF-16
/// surrogates. See the header — a Swift `String` cannot carry one, so the case is
/// removed by the type system, not declined by the harness. U+FFFD stands in for
/// "a replacement character already in the text", which is the shape this host
/// actually sees when foreign bytes were decoded upstream.
let fuzzHostileChars: [String] = [
  "{", "}", "[", "]", "\"", ":", ",", fuzzBackslash, "/", "-", "+", ".", "e", "E", "0", "9",
  "n", "t", "f", " ", "\t", "\n", "\r",
  fuzzChar(0x0000), fuzzChar(0x007F), fuzzChar(0xFEFF), fuzzChar(0x2028),
  "é", "中", fuzzChar(0xFFFD),
]

/// The JSON-ESCAPE entries are six-character TEXT (backslash, `u`, four hex
/// digits), not the code points they denote — a decoder's unescape path is what
/// they are aimed at, so writing them as the characters would test the wrong
/// thing. This is where the lone high and low surrogates enter this host's stream,
/// and the only place they can.
let fuzzHostileTokens: [String] = [
  "null", "true", "false", "{}", "[]", "\"\"",
  "-0", "1e999", "-1e999", "1E-999", "NaN", "Infinity", "-Infinity",
  "0x10", "00", "01", "1.2.3", "+1", ".5", "5.", "1e", "1.", "-", "1e+", "1e-",
  fuzzEsc("0000"),
  fuzzEsc("D800"),  // lone HIGH surrogate
  fuzzEsc("DC00"),  // lone LOW surrogate
  fuzzEsc("DBFF") + fuzzEsc("DFFF"),  // a valid pair, at the top of the range
  fuzzEsc("D800") + fuzzEsc("0041"),  // high surrogate + a non-low escape
  fuzzEsc("D83D") + fuzzEsc("DE00"),  // a valid pair
  fuzzEsc("D83D"),
  fuzzEsc("FFFF"),
  fuzzBackslash + "u00",  // truncated
  fuzzBackslash + "x41",  // not a JSON escape at all
  fuzzBackslash,
  fuzzEsc2("\""),
  #""$type":"""#, #""$type":null"#, #""id":"""#, #""id":null"#, #""id":[]"#,
  #""kind":"Heading""#, #""children":"x""#, #""level":1e999"#,
  ",", ":", "[", "]", "{", "}", "\"", "'", "/*", "*/", "//",
  fuzzChar(0x0000), fuzzChar(0xFEFF), "\r\n",
]

/// REAL wire keys, so a generated near-miss reaches deep into the typed decoders
/// instead of bouncing off the first `MISSING_FIELD`. `__proto__` and
/// `constructor` are carried from the sibling legs: they cost nothing here and
/// keep the stream shape comparable, though the prototype-pollution reason that
/// motivates them on the TypeScript host does not port to Swift.
let fuzzWireKeys: [String] = [
  "id", "kind", "$type", "children", "layout", "role", "text", "level", "variant", "source",
  "value", "label", "fields", "items", "columns", "rows", "onSubmit", "onClick", "required",
  "binding", "style", "props", "state", "ops", "path", "node", "index", "target", "name",
  "format", "unit", "min", "max", "options", "spec", "__proto__", "constructor", "", " ",
]

/// Number-grammar edge cases live here as much as in the token list: `1e`, `-0`,
/// `01`, `1.`, `.5` and the 300-digit exponents are all *values* a retype-value
/// mutation can drop into a typed slot.
let fuzzScalarLiterals: [String] = [
  "0", "-1", "1e308", "-1e308", "3.141592653589793",
  "true", "false", "null", "\"\"", "\"x\"", "\"Standard\"", "\"Group\"",
  "9007199254740993", "-0.0", "-0", "01", "1.", ".5", "1e", "1e+", "1E-999",
  "1e" + String(repeating: "3", count: 300),
  "-1e" + String(repeating: "9", count: 320),
  "0." + String(repeating: "0", count: 400) + "1",
]

// ─── Near-miss + mutators ────────────────────────────────────────────────────

/// A near-miss of a real vocabulary word: the class of input a model emitter
/// actually produces, and the class a curated reject corpus is worst at covering,
/// because a human writing fixtures reaches for obvious garbage.
func fuzzNearMiss(_ rng: inout FuzzRng, _ word: String) -> String {
  var w = fuzzScalars(word)
  if w.isEmpty { return "x" }
  switch rng.next(8) {
  case 0: return word.lowercased()
  case 1: return word.uppercased()
  case 2: return word + "s"
  case 3: return fuzzText(Array(w.dropLast()))
  case 4: return word + " "
  case 5: return " " + word
  case 6:
    w.remove(at: rng.next(w.count))
    return fuzzText(w)
  default:
    let i = rng.next(w.count)
    w.insert(contentsOf: fuzzScalars(rng.pick(fuzzHostileChars)), at: i)
    return fuzzText(w)
  }
}

/// Each mutator corrupts a seed payload. Named individually so a reported
/// counterexample records WHICH transformation produced it: a find whose
/// provenance is only "the fuzzer did something" is markedly harder to act on.
let fuzzMutatorNames: [String] = [
  "flip-char", "delete-span", "insert-token", "duplicate-span", "truncate",
  "transpose", "repeat-structural", "retype-value", "near-miss-type",
  "delete-key", "duplicate-key", "escape-injection", "prefix-junk", "suffix-junk",
]

struct FuzzConfig {
  /// Names the stream, so a reported find's replay line reconstructs the exact
  /// configuration as well as the exact seed.
  let name: String
  /// The bounded gate run keeps this small so the suite stays quick; the long run
  /// raises it past the §21 string bound so that bound is actually crossed.
  let maxPayloadChars: Int
  /// One in this many inputs is a deliberately pathological (large) payload.
  let heavyEveryN: Int

  static let bounded = FuzzConfig(name: "bounded", maxPayloadChars: 32 * 1024, heavyEveryN: 120)
  static let long = FuzzConfig(name: "long", maxPayloadChars: 2 * 1024 * 1024, heavyEveryN: 25)
}

private func fuzzFind(_ p: FuzzPayload, _ needle: FuzzPayload, from: Int = 0) -> Int? {
  guard !needle.isEmpty, p.count >= needle.count else { return nil }
  var i = max(0, from)
  while i + needle.count <= p.count {
    if Array(p[i..<(i + needle.count)]) == needle { return i }
    i += 1
  }
  return nil
}

private func fuzzFindAll(_ p: FuzzPayload, _ needle: FuzzPayload) -> [Int] {
  var out: [Int] = []
  var from = 0
  while let i = fuzzFind(p, needle, from: from) {
    out.append(i)
    from = i + 1
  }
  return out
}

private func fuzzCap(_ p: FuzzPayload, _ maximum: Int) -> FuzzPayload {
  p.count <= maximum ? p : Array(p[0..<maximum])
}

private func fuzzNearMissType(_ rng: inout FuzzRng, _ vocab: [String], _ p: FuzzPayload)
  -> FuzzPayload
{
  let marker = fuzzScalars(#""$type":""#)
  let positions = fuzzFindAll(p, marker)
  if positions.isEmpty {
    // No discriminator to corrupt — append one rather than returning the input
    // untouched. A silently no-op mutator quietly shrinks the effective iteration
    // count and nothing reports that it did.
    let word = fuzzNearMiss(&rng, rng.pick(vocab))
    return p + fuzzScalars(#"{"$type":"\#(word)"}"#)
  }
  let start = positions[rng.next(positions.count)] + marker.count
  guard let close = fuzzFind(p, ["\""], from: start) else { return p }
  let replacement =
    rng.boolean()
    ? fuzzNearMiss(&rng, fuzzText(Array(p[start..<close])))
    : fuzzNearMiss(&rng, rng.pick(vocab))
  return Array(p[0..<start]) + fuzzScalars(replacement) + Array(p[close...])
}

/// Delete a whole `"key":value` pair, cutting from the key's opening quote to just
/// past the next comma.
private func fuzzDeleteKey(_ rng: inout FuzzRng, _ p: FuzzPayload) -> FuzzPayload {
  let positions = fuzzFindAll(p, fuzzScalars("\":"))
  if positions.isEmpty { return p }
  let colon = positions[rng.next(positions.count)]
  var closeQuote = colon
  while closeQuote > 0 && p[closeQuote] != "\"" { closeQuote -= 1 }
  var openQuote = closeQuote > 0 ? closeQuote - 1 : 0
  while openQuote > 0 && p[openQuote] != "\"" { openQuote -= 1 }
  let cutTo = min(fuzzFind(p, [","], from: colon).map { $0 + 1 } ?? (colon + 8), p.count)
  return Array(p[0..<openQuote]) + Array(p[cutTo...])
}

func fuzzMutateOnce(
  _ rng: inout FuzzRng, _ vocab: [String], _ cfg: FuzzConfig, _ p: FuzzPayload
) -> (String, FuzzPayload) {
  let name = fuzzMutatorNames[rng.next(fuzzMutatorNames.count)]
  let n = p.count
  var out = p

  switch name {
  case "flip-char" where n > 0:
    let i = rng.next(n)
    out = Array(p[0..<i]) + fuzzScalars(rng.pick(fuzzHostileChars)) + Array(p[(i + 1)...])
  case "delete-span" where n > 1:
    let i = rng.next(n)
    let to = min(i + rng.range(1, 8), n)
    out = Array(p[0..<i]) + Array(p[to...])
  case "insert-token":
    let i = rng.next(n + 1)
    out = Array(p[0..<i]) + fuzzScalars(rng.pick(fuzzHostileTokens)) + Array(p[i...])
  case "duplicate-span" where n > 1:
    let i = rng.next(n)
    let to = min(i + rng.range(1, 64), n)
    let at = rng.next(n + 1)
    out = Array(p[0..<at]) + Array(p[i..<to]) + Array(p[at...])
  case "truncate" where n > 1:
    out = Array(p[0..<rng.next(n)])
  case "transpose" where n > 2:
    let i = rng.next(n - 2)
    out = Array(p[0..<i]) + [p[i + 1], p[i]] + Array(p[(i + 2)...])
  case "repeat-structural":
    let ch = rng.pick(["[", "{", "\"", "]", "}", ","])
    let count = min(rng.range(2, 4096), max(2, cfg.maxPayloadChars / 4))
    let at = rng.next(n + 1)
    out = Array(p[0..<at]) + fuzzScalars(String(repeating: ch, count: count)) + Array(p[at...])
  case "retype-value" where n > 0:
    let i = rng.next(n)
    let to = min(i + rng.range(1, 12), n)
    out = Array(p[0..<i]) + fuzzScalars(rng.pick(fuzzScalarLiterals)) + Array(p[to...])
  case "near-miss-type":
    out = fuzzNearMissType(&rng, vocab, p)
  case "delete-key":
    out = fuzzDeleteKey(&rng, p)
  case "duplicate-key" where n > 4:
    // A duplicated key is a real emitter defect and a classic cross-host parser
    // divergence (first-wins vs last-wins vs refuse) — §20 of the wire
    // specification records the measured matrix and PROPOSES a rule. Fuzzing it
    // for crashes is in scope here; asserting which behaviour is correct is not,
    // until that rule is ratified.
    if let i = fuzzFind(p, ["\""]), let j = fuzzFind(p, [","]), j > i {
      out = Array(p[0...j]) + Array(p[i..<j]) + [","] + Array(p[(j + 1)...])
    }
  case "escape-injection" where n > 0:
    let i = rng.next(n)
    let esc = rng.pick([
      fuzzBackslash + "u", fuzzEsc("D800"), fuzzEsc("DC00"), fuzzBackslash + "u00",
      fuzzBackslash, fuzzEsc2("/"), fuzzEsc2("b") + fuzzEsc2("f"),
    ])
    out = Array(p[0..<i]) + fuzzScalars(esc) + Array(p[i...])
  case "prefix-junk", "suffix-junk":
    var junk: FuzzPayload = []
    for _ in 0..<rng.range(1, 16) { junk += fuzzScalars(rng.pick(fuzzHostileChars)) }
    out = name == "prefix-junk" ? junk + p : p + junk
  default:
    out = p + fuzzScalars(rng.pick(fuzzHostileChars))
  }

  return (name, fuzzCap(out, cfg.maxPayloadChars))
}

// ─── Structure-aware generation ──────────────────────────────────────────────

func fuzzGenValue(
  _ rng: inout FuzzRng, _ depth: Int, _ out: inout FuzzPayload, _ vocab: [String],
  _ cfg: FuzzConfig
) {
  if out.count > cfg.maxPayloadChars {
    out.append("0")
    return
  }
  if depth == 0 {
    out += fuzzScalars(rng.pick(fuzzScalarLiterals))
    return
  }
  let branch = rng.next(12)
  if branch <= 3 {
    out += fuzzScalars(rng.pick(fuzzScalarLiterals))
  } else if branch <= 7 {
    out.append("{")
    let n = rng.range(0, 5)
    for i in 0..<n {
      if i > 0 { out.append(",") }
      out.append("\"")
      out += fuzzScalars(rng.pick(fuzzWireKeys))
      out += fuzzScalars("\":")
      fuzzGenValue(&rng, depth - 1, &out, vocab, cfg)
    }
    out.append("}")
  } else if branch <= 10 {
    out.append("[")
    let n = rng.range(0, 5)
    for i in 0..<n {
      if i > 0 { out.append(",") }
      fuzzGenValue(&rng, depth - 1, &out, vocab, cfg)
    }
    out.append("]")
  } else {
    // A plausible node shell around a wrong interior: the shape that gets furthest
    // into the typed decoders before it fails, and so the one most likely to reach
    // code a shallow syntax reject never does.
    out += fuzzScalars(#"{"id":"g","kind":{"$type":""#)
    out += fuzzScalars(fuzzNearMiss(&rng, rng.pick(vocab)))
    out += fuzzScalars("\",\"")
    out += fuzzScalars(rng.pick(fuzzWireKeys))
    out += fuzzScalars("\":")
    fuzzGenValue(&rng, depth - 1, &out, vocab, cfg)
    out += fuzzScalars("}}")
  }
}

/// Depth, width and string length taken past the §21 limits. Every payload is
/// assembled as TEXT: building one as a nested value would blow the harness's own
/// stack while CONSTRUCTING the input, which proves nothing about the decoder.
func fuzzGenPathological(_ rng: inout FuzzRng, _ cfg: FuzzConfig) -> FuzzPayload {
  let cap = cfg.maxPayloadChars
  switch rng.next(9) {
  case 0:
    let n = min(cap / 2, rng.range(64, 200_000))
    return fuzzScalars(String(repeating: "[", count: n) + String(repeating: "]", count: n))
  case 1:
    let n = min(cap / 6, rng.range(64, 100_000))
    return fuzzScalars(
      String(repeating: #"{"a":"#, count: n) + "1" + String(repeating: "}", count: n))
  case 2:
    // Unterminated as well as over-deep: the depth guard must fire on the way
    // DOWN, before truncation is ever reached.
    return fuzzScalars(String(repeating: "[", count: min(cap / 2, rng.range(64, 200_000))))
  case 3:
    // Deep NODE nesting rather than deep JSON — crosses the tree depth bound while
    // staying far inside the JSON one, isolating the tree limit.
    var acc =
      #"{"id":"leaf","kind":{"$type":"Heading","level":1,"text":"x","variant":"Standard"}}"#
    for i in 1...max(2, rng.range(2, 400)) {
      if acc.count >= cap { break }
      acc =
        #"{"id":"n\#(i)","kind":{"$type":"Box","children":[\#(acc)],"layout":{"$type":"Auto"},"role":"Group"}}"#
    }
    return fuzzScalars(acc)
  case 4:
    let n = min(cap / 2, rng.range(1000, 200_000))
    let body = Array(repeating: "1", count: n).joined(separator: ",")
    return fuzzScalars(#"{"id":"a","kind":[\#(body)]}"#)
  case 5:
    let n = min(cap, rng.range(1000, 1_200_000))
    let big = String(repeating: "x", count: n)
    return fuzzScalars(
      #"{"id":"a","kind":{"$type":"Heading","level":1,"text":"\#(big)","variant":"Standard"}}"#)
  case 6:
    var acc = #"{"$type":"Batch","ops":[]}"#
    for _ in 0..<rng.range(2, 300) {
      if acc.count >= cap { break }
      acc = #"{"$type":"Batch","ops":[\#(acc)]}"#
    }
    return fuzzScalars(acc)
  case 7:
    // Escape-heavy: nearly every character an escape, so the UNESCAPE path does
    // the work rather than the structural walk. SIX characters of text per unit,
    // matching the `cap / 6` divisor — a plain literal here would divide by six
    // and then emit one character per unit, exercising no unescape path at all.
    let n = min(cap / 6, rng.range(500, 100_000))
    let esc = String(repeating: fuzzEsc("0041"), count: n)
    return fuzzScalars(#"{"id":"a","kind":{"$type":"Markdown","source":"\#(esc)"}}"#)
  default:
    let n = min(cap / 4, rng.range(500, 50_000))
    let body = (0..<n).map { #""k\#($0)":1"# }.joined(separator: ",")
    return fuzzScalars("{\(body)}")
  }
}

struct FuzzGenerated {
  let payload: FuzzPayload
  let origin: String
}

/// Deterministic in `(seed, iteration, cfg)` — the replay contract.
func fuzzGenerate(
  _ rng: inout FuzzRng, _ seeds: [FuzzPayload], _ vocab: [String], _ cfg: FuzzConfig,
  _ iteration: Int
) -> FuzzGenerated {
  if iteration % cfg.heavyEveryN == 0 {
    return FuzzGenerated(payload: fuzzGenPathological(&rng, cfg), origin: "pathological")
  }
  let branch = rng.next(10)
  if branch <= 1 {
    var out: FuzzPayload = []
    fuzzGenValue(&rng, rng.range(1, 6), &out, vocab, cfg)
    return FuzzGenerated(payload: out, origin: "structured-generation")
  }
  if branch == 2 {
    var out: FuzzPayload = []
    for _ in 0..<rng.range(0, 200) { out += fuzzScalars(rng.pick(fuzzHostileChars)) }
    return FuzzGenerated(payload: out, origin: "raw-junk")
  }
  if branch == 3 {
    // Crossover: prefix of one seed, suffix of another. Produces half-valid
    // documents no single-seed mutation reaches.
    let a = rng.pick(seeds)
    let c = rng.pick(seeds)
    let i = rng.next(a.count + 1)
    let j = rng.next(c.count + 1)
    return FuzzGenerated(
      payload: fuzzCap(Array(a[0..<i]) + Array(c[j...]), cfg.maxPayloadChars),
      origin: "crossover")
  }
  var acc = rng.pick(seeds)
  var names: [String] = []
  for _ in 0..<rng.range(1, 4) {
    let (name, next) = fuzzMutateOnce(&rng, vocab, cfg, acc)
    acc = next
    names.append(name)
  }
  return FuzzGenerated(payload: acc, origin: "mutation:" + names.joined(separator: "+"))
}

// ─── The determinism exemption ───────────────────────────────────────────────

/// Invariant 4′ is EXEMPTED — never the whole input skipped — for one recorded
/// class, which is a limit of the invariant and not a decoder defect. An
/// EXEMPTION skips ONE invariant on an input that is still fully checked for
/// totality and termination, and it is counted and named on the evidence line so
/// its size is visible rather than silent. It is pinned by
/// `testMapDecodedSlotsDecodeInAStableOrder`, so it cannot silently widen.
enum FuzzDeterminism {
  /// The reason this document's determinism check is exempt, or `nil`.
  static func exemption(_ parsed: JSON) -> String? {
    if carriesNaNSentinel(parsed) { return "nan-inequality" }
    return nil
  }

  /// **A limit of the invariant, NOT a decoder defect.**
  /// `Decode.float` maps the `"NaN"` sentinel to `Double.nan`, and IEEE-754 says
  /// `nan != nan`, so a tree carrying one is never `==` to itself however
  /// perfectly it decoded. Comparing such a tree would report a counterexample
  /// against a decoder that did nothing wrong. `Infinity` is unaffected — it
  /// compares equal to itself — so only the NaN spelling is exempted.
  static func carriesNaNSentinel(_ j: JSON) -> Bool {
    switch j {
    case .string(let s): return s == "NaN"
    case .array(let a): return a.contains(where: carriesNaNSentinel)
    case .object(let o): return o.values.contains(where: carriesNaNSentinel)
    default: return false
    }
  }
}

/// One parse, one verdict: the exemption asks its question of the parsed tree,
/// and the parse is shared with nothing else because there is nothing else to ask.
struct FuzzTriage {
  var determinismExemption: String? = nil

  static func of(_ text: String) -> FuzzTriage {
    guard let parsed = try? JSON.parse(text) else { return FuzzTriage() }
    return FuzzTriage(determinismExemption: FuzzDeterminism.exemption(parsed))
  }
}

// ─── Subjects + verdicts ─────────────────────────────────────────────────────

/// What one decode entry point did with one input. Deliberately field-typed rather
/// than returning a `Node`, so the go-red mutants can fabricate every outcome
/// without constructing a tree — one machinery, two kinds of subject.
struct FuzzSubjectResult {
  var refusedCode: String? = nil
  var untypedError: String? = nil
  var accepted: Bool = false
  /// Invariant 4′ — see the header. Meaningful only when `accepted`.
  var deterministic: Bool = true
}

/// One decode entry point, or a deliberately-broken stand-in.
struct FuzzSubject {
  let name: String
  let run: (String) -> FuzzSubjectResult
}

/// The real subject. ONE entry point — see the header's entry-points note.
func fuzzNodeSubject() -> FuzzSubject {
  FuzzSubject(name: "decodeNode") { input in
    do {
      let first = try RenderProjection.decodeNode(input)
      // Invariant 4′. Only on the accept path: it is the accept path that has a
      // tree to compare, and re-decoding every refusal would double the run's cost
      // to re-observe an error the harness already has.
      let second = try? RenderProjection.decodeNode(input)
      return FuzzSubjectResult(accepted: true, deterministic: second == first)
    } catch let e as FuaranDecodeError {
      return FuzzSubjectResult(refusedCode: e.code.rawValue)
    } catch {
      // A non-`FuaranDecodeError` from a total decoder is itself a finding, so it
      // is reported under a name that cannot be mistaken for a canonical code.
      return FuzzSubjectResult(untypedError: "\(type(of: error)): \(error)")
    }
  }
}

/// `kind` is the coarse class; `detail` is for the report. `rejected` and `clean`
/// are both PASSES — a fuzz harness that treated refusal as failure would be
/// asserting the opposite of the claim under test.
struct FuzzVerdict {
  let kind: String
  let detail: String
  var isCounterexample: Bool { kind != "rejected" && kind != "clean" }
}

struct FuzzBudgets {
  /// `swift test` builds the DEBUG configuration — no optimisation, and this
  /// package's hand-written JSON layer is exactly the sort of tight scalar code
  /// that costs an order of magnitude there. A budget within a small factor of the
  /// observed maximum goes red on a slower CI runner for reasons having nothing to
  /// do with the decoder, and a flaky budget is worse than a loose one: it gets
  /// raised in a hurry by whoever it blocks, and nobody records why.
  var softTimeMs: Double = 10_000
}

struct FuzzMeasured {
  let verdict: FuzzVerdict
  let elapsedMs: Double
}

/// Run one input through one subject and judge it against every invariant.
///
/// **This function is the harness**, and it takes a `FuzzSubject` precisely so the
/// go-red self-test can point it at a deliberately broken closure and drive the
/// IDENTICAL machinery: a fuzz harness nobody has ever seen fail is decoration.
func fuzzCheck(
  _ subject: FuzzSubject, _ budgets: FuzzBudgets, _ input: String,
  exemptDeterminism: Bool = false
) -> FuzzMeasured {
  let clock = ContinuousClock()
  var result = FuzzSubjectResult()
  let elapsed = clock.measure { result = subject.run(input) }
  let ms =
    Double(elapsed.components.seconds) * 1000.0
    + Double(elapsed.components.attoseconds) / 1_000_000_000_000_000.0

  func at(_ kind: String, _ detail: String) -> FuzzMeasured {
    FuzzMeasured(verdict: FuzzVerdict(kind: kind, detail: detail), elapsedMs: ms)
  }

  // Order matters: an input that both ran long AND escaped is reported as the time
  // breach, because that is the one an operator has to act on first.
  if ms > budgets.softTimeMs {
    return at("timed-out", "decode returned only after \(Int(ms)) ms")
  }
  if let untyped = result.untypedError {
    return at("escaped-error", "an error outside the typed contract escaped — \(untyped)")
  }
  if let code = result.refusedCode { return at("rejected", code) }
  // The exemption is applied HERE, after totality and termination, so an exempt
  // input is still fully checked for the two invariants that matter most.
  if result.accepted && !result.deterministic && !exemptDeterminism {
    return at("determinism-broken", "the same input decoded to two different trees")
  }
  if result.accepted { return at("clean", "") }
  return at("no-verdict", "the subject neither accepted nor refused the input")
}

/// The coarse class the minimiser preserves. Deliberately drops payload-specific
/// detail, so a SMALLER input failing the same way is accepted as a reduction.
func fuzzVerdictClass(_ v: FuzzVerdict) -> String {
  v.isCounterexample ? v.kind : "held"
}

// ─── The run ─────────────────────────────────────────────────────────────────

struct FuzzCounterexample {
  let subject: String
  let iteration: Int
  let origin: String
  let verdict: FuzzVerdict
  let original: FuzzPayload
  var minimised: FuzzPayload

  func describe(seed: UInt64, configName: String) -> String {
    let text = fuzzText(minimised)
    let preview =
      text.unicodeScalars.count > 300
      ? fuzzText(Array(text.unicodeScalars.prefix(300))) + " ...(truncated)" : text
    return """
      subject: \(subject)
      seed: \(seed), iteration: \(iteration), config: \(configName)
      origin: \(origin)
      verdict: \(verdict.kind) — \(verdict.detail)
      length: \(original.count) chars original, \(minimised.count) minimised
      minimised input: \(preview.debugDescription)

      Counterexample policy: fix the decoder, then land the minimised input as a
      permanent reject fixture in the shared corpus, so every conformant host
      inherits the case rather than only this one.
      """
  }
}

struct FuzzRunStats {
  var iterations = 0
  var inputs = 0
  var corpusSeeds = 0
  /// Invariant 4' exemptions, by recorded reason — see `FuzzDeterminism`.
  var determinismExempt: [String: Int] = [:]
  var rejectCodes: [String: Int] = [:]
  var origins: [String: Int] = [:]
  var accepted = 0
  var maxDecodeMs = 0.0
  var elapsedSeconds = 0.0
  var counterexamples: [FuzzCounterexample] = []
}

struct FuzzRunOptions {
  var minimise = true
}

/// Delta-debugging by span deletion, preserving the coarse verdict class.
///
/// Bounded on BOTH axes — 400 candidate evaluations and 25 s — because the class
/// most worth minimising (a time breach) is exactly the one where each probe is
/// expensive. Cuts land on scalar boundaries by construction: the payload is a
/// scalar array, so there is no split-a-character hazard to guard against.
func fuzzMinimise(
  _ subject: FuzzSubject, _ budgets: FuzzBudgets, _ payload: FuzzPayload, _ target: String
) -> FuzzPayload {
  var best = payload
  var granularity = 2
  var evaluations = 0
  let clock = ContinuousClock()
  let started = clock.now

  while best.count > 1 && evaluations < 400 && started.duration(to: clock.now) < .seconds(25) {
    let chunk = max(1, best.count / granularity)
    var reduced = false
    var i = 0
    while i < best.count && evaluations < 400 {
      let to = min(i + chunk, best.count)
      let candidate = Array(best[0..<i]) + Array(best[to...])
      if candidate.isEmpty {
        i = to
        continue
      }
      evaluations += 1
      if fuzzVerdictClass(fuzzCheck(subject, budgets, fuzzText(candidate)).verdict) == target {
        best = candidate
        reduced = true
      } else {
        i = to
      }
    }
    if reduced {
      granularity = max(2, granularity / 2)
    } else {
      if chunk == 1 { break }
      granularity *= 2
    }
  }
  return best
}

func fuzzRun(
  subjects: [FuzzSubject], budgets: FuzzBudgets, cfg: FuzzConfig, seed: UInt64, iterations: Int,
  seeds: [FuzzPayload], vocab: [String], options: FuzzRunOptions = FuzzRunOptions()
) -> FuzzRunStats {
  var rng = FuzzRng(seed: seed)
  var stats = FuzzRunStats()
  stats.corpusSeeds = seeds.count
  let clock = ContinuousClock()
  let started = clock.now

  for i in 1...max(1, iterations) {
    let g = fuzzGenerate(&rng, seeds, vocab, cfg, i)
    let text = fuzzText(g.payload)
    stats.origins[g.origin.hasPrefix("mutation:") ? "mutation" : g.origin, default: 0] += 1
    stats.iterations = i

    let triage = FuzzTriage.of(text)
    if let reason = triage.determinismExemption {
      stats.determinismExempt[reason, default: 0] += 1
    }

    for subject in subjects {
      let m = fuzzCheck(
        subject, budgets, text, exemptDeterminism: triage.determinismExemption != nil)
      stats.inputs += 1
      stats.maxDecodeMs = max(stats.maxDecodeMs, m.elapsedMs)
      switch m.verdict.kind {
      case "rejected": stats.rejectCodes[m.verdict.detail, default: 0] += 1
      case "clean": stats.accepted += 1
      default:
        var find = FuzzCounterexample(
          subject: subject.name, iteration: i, origin: g.origin, verdict: m.verdict,
          original: g.payload, minimised: g.payload)
        if options.minimise {
          find.minimised = fuzzMinimise(subject, budgets, g.payload, fuzzVerdictClass(m.verdict))
        }
        stats.counterexamples.append(find)
      }
    }
  }

  let took = started.duration(to: clock.now)
  stats.elapsedSeconds =
    Double(took.components.seconds) + Double(took.components.attoseconds) / 1e18
  return stats
}

/// The one-line human summary, printed on every run, pass or fail: a harness whose
/// output is only visible when it fails cannot be checked for having quietly
/// stopped generating anything.
///
/// Reject codes are sorted ALPHABETICALLY (the Go host's choice, not the
/// TypeScript host's descending-count one), so the ORDER of the code list is
/// stable whatever the counts did.
///
/// **The COUNTS are not fully stable at one seed, and that is a finding rather
/// than harness noise.** The generated stream is exactly reproducible, but the
/// decoder's refusal for a document with two invalid map entries depends on
/// dictionary iteration order, so a run can shift one refusal between two codes —
/// see the third block of
/// `testTheKnownDeterminismFindingsAreRecordedAndExempted`. Expect two runs at one
/// seed to agree on every figure except a small drift across the refusal codes;
/// a difference anywhere else means the stream itself moved.
func fuzzSummarise(_ stats: FuzzRunStats, seed: UInt64, cfg: FuzzConfig) -> String {
  let codes = stats.rejectCodes.map { "\($0.key)=\($0.value)" }.sorted().joined(separator: " ")
  let families = stats.origins.keys.sorted().joined(separator: " ")
  let exempt = stats.determinismExempt.map { "\($0.key)=\($0.value)" }.sorted()
    .joined(separator: " ")
  let decoded = stats.iterations
  let perIteration = decoded <= 0 ? 0 : stats.inputs / decoded
  return
    "host=fuaran-swift seed=\(seed) config=\(cfg.name) — "
    + "\(stats.inputs) inputs (\(decoded) decoded iterations x \(perIteration) entry point) "
    + "in \(String(format: "%.1f", stats.elapsedSeconds)) s, "
    + "corpusSeeds=\(stats.corpusSeeds), families [\(families)], "
    + "accepted \(stats.accepted), refused [\(codes)], "
    + "determinism-exempt [\(exempt)], "
    + "counterexamples=\(stats.counterexamples.count); "
    + "max decode \(String(format: "%.0f", stats.maxDecodeMs)) ms"
}

// ─── Environment ─────────────────────────────────────────────────────────────

enum FuzzEnv {
  static func string(_ name: String) -> String? {
    guard let raw = ProcessInfo.processInfo.environment[name] else { return nil }
    let t = raw.trimmingCharacters(in: .whitespaces)
    return t.isEmpty ? nil : t
  }

  /// A malformed value is a hard stop, never a silent fallback: a run that quietly
  /// ignored a mistyped `FUARAN_FUZZ_ITERATIONS` would report a green gate for a
  /// fraction of the work someone asked for.
  static func positiveInt(_ name: String, _ fallback: Int) -> Int {
    guard let raw = string(name) else { return fallback }
    guard let n = Int(raw), n > 0 else {
      fatalError("\(name): \(raw.debugDescription) is not a positive integer")
    }
    return n
  }

  static func uint64(_ name: String, _ fallback: UInt64) -> UInt64 {
    guard let raw = string(name) else { return fallback }
    guard let n = UInt64(raw) else {
      fatalError("\(name): \(raw.debugDescription) is not an unsigned integer")
    }
    return n
  }

  static var isLong: Bool { string("FUARAN_FUZZ_LONG") == "1" }
}

let fuzzDefaultSeed: UInt64 = 1023

// ─── The gate ────────────────────────────────────────────────────────────────

final class DecoderFuzzTests: XCTestCase {

  static func loadedSeeds() -> ([FuzzPayload], [String], Bool) {
    let corpus = FuzzCorpus.directory()
    return (FuzzCorpus.seeds(corpus).map(fuzzScalars), FuzzCorpus.vocabulary(corpus), corpus != nil)
  }

  /// The main gate: the refusal contract over generated hostile input.
  func testTheRefusalContractHoldsOverGeneratedHostileInput() throws {
    let (seeds, vocab, corpusPresent) = Self.loadedSeeds()
    let cfg = FuzzEnv.isLong ? FuzzConfig.long : FuzzConfig.bounded
    // 10 000 measures at ~1.5 s on the reference machine — a tenth of the ~10 s the
    // task allows this leg to add, which is deliberate headroom rather than
    // under-use: a CI runner several times slower than a developer box must not turn
    // the gate into the slowest thing in the suite. Raise it per-run with the
    // environment variable; the long config is where a big number belongs.
    let iterations = FuzzEnv.positiveInt(
      "FUARAN_FUZZ_ITERATIONS", FuzzEnv.isLong ? 250_000 : 10_000)
    let seed = FuzzEnv.uint64("FUARAN_FUZZ_SEED", fuzzDefaultSeed)

    let subjects = [fuzzNodeSubject()]
    let stats = fuzzRun(
      subjects: subjects, budgets: FuzzBudgets(), cfg: cfg, seed: seed, iterations: iterations,
      seeds: seeds, vocab: vocab,
      options: FuzzRunOptions(minimise: true))

    print("  [decoder-fuzz] \(fuzzSummarise(stats, seed: seed, cfg: cfg))")

    if let path = FuzzEnv.string("FUARAN_FUZZ_EVIDENCE") {
      let codes = stats.rejectCodes.keys.sorted()
        .map { "    \($0.debugDescription): \(stats.rejectCodes[$0]!)" }
        .joined(separator: ",\n")
      let json = """
        {
          "host": "fuaran-swift",
          "entryPoints": ["decodeNode"],
          "config": "\(cfg.name)",
          "seed": "\(seed)",
          "iterations": \(stats.iterations),
          "inputs": \(stats.inputs),
          "corpusSeeds": \(stats.corpusSeeds),
          "corpusPresent": \(corpusPresent),
          "determinismExempt": \(stats.determinismExempt.values.reduce(0, +)),
          "accepted": \(stats.accepted),
          "rejectCodes": {
        \(codes)
          },
          "counterexamples": \(stats.counterexamples.count),
          "maxDecodeMs": \(String(format: "%.3f", stats.maxDecodeMs)),
          "elapsedSeconds": \(String(format: "%.3f", stats.elapsedSeconds)),
          "notPortable": ["bounded-work", "fixed-point"]
        }

        """
      try? json.write(toFile: path, atomically: true, encoding: .utf8)
    }

    if !stats.counterexamples.isEmpty {
      let detail = stats.counterexamples.prefix(5)
        .map { $0.describe(seed: seed, configName: cfg.name) }
        .joined(separator: "\n\n")
      XCTFail(
        "\(stats.counterexamples.count) counterexample(s) — the decoder's refusal contract does "
          + "not hold over generated hostile input.\n\n\(detail)")
    }

    // A run that generated nothing would report zero counterexamples and look
    // identical to a clean one. Pin the work actually done.
    XCTAssertEqual(stats.iterations, iterations, "the stream stopped short")
    XCTAssertEqual(
      stats.inputs, iterations * subjects.count,
      "every iteration must be decoded by every subject")
    // Both outcomes must occur. A stream that only ever refuses never reaches the
    // determinism invariant; one that only ever accepts is not hostile.
    XCTAssertGreaterThan(
      stats.accepted, 0, "no generated input was ACCEPTED — invariant 4' was never exercised")
    XCTAssertFalse(
      stats.rejectCodes.isEmpty, "no generated input was REFUSED — the stream is not hostile")
    // All five families must actually fire.
    XCTAssertEqual(
      Set(stats.origins.keys),
      Set(["mutation", "structured-generation", "raw-junk", "crossover", "pathological"]),
      "an input family stopped producing: \(stats.origins.keys.sorted())")
  }

  /// The floor under everything else: the machinery must call a GOOD input good. A
  /// harness that reported every input as a counterexample would pass every go-red
  /// test in this file.
  func testAWellFormedNodeIsNeitherARefusalNorACounterexample() throws {
    let good = #"{"id":"a","kind":{"$type":"Heading","level":1,"text":"x","variant":"Standard"}}"#
    let m = fuzzCheck(fuzzNodeSubject(), FuzzBudgets(), good)
    XCTAssertEqual(m.verdict.kind, "clean", "a well-formed node verdicted \(m.verdict.detail)")
    XCTAssertFalse(m.verdict.isCounterexample)
  }

  // ─── Go-red: the harness fails when the decoder is broken ──────────────────
  //
  // Permanent, not a one-off demonstration at authoring time. Each mutant breaks
  // ONE invariant, and the inverse pin proves each is PARTIAL — a mutant that broke
  // every input would make the harness look sensitive while testing nothing.
  //
  // **What is NOT here, and why.** The sibling hosts' `mutant:panics` has no
  // counterpart: a Swift trap (`fatalError`, a force-unwrapped nil, an
  // out-of-range `Int(Double)` conversion) cannot be caught, so a mutant that
  // trapped would terminate the test runner and prove only that the process can
  // die. The catchable half of that class — an error thrown outside the typed
  // contract — IS covered, by `mutant:throws`. The gap is the same one the header
  // records under invariant 1 — which is why the one real trap this leg found
  // (`Decode.int` on a non-finite or out-of-range number) is pinned by a DIRECT
  // test on the typed refusal rather than left to the stream to rediscover.

  struct DeliberateEscape: Error, CustomStringConvertible {
    var description: String { "deliberate: the decoder let an untyped error escape" }
  }

  /// Fires only on inputs whose length is divisible by `n`, and otherwise reports
  /// an ordinary refusal — partial by design, so the inverse pin below means
  /// something.
  static func everyNth(_ n: Int, _ name: String, _ broken: @escaping () -> FuzzSubjectResult)
    -> FuzzSubject
  {
    FuzzSubject(name: name) { input in
      input.unicodeScalars.count % n == 0
        ? broken() : FuzzSubjectResult(refusedCode: "INVALID_JSON")
    }
  }

  func testTheHarnessGoesRedOnABrokenDecoder() throws {
    let (seeds, vocab, _) = Self.loadedSeeds()

    // The slow mutant is measured against a DELIBERATELY TIGHT budget rather than
    // the shipped one. Sleeping past the real budget would cost ten seconds per
    // firing — the sort of cost that gets a go-red test deleted rather than fixed.
    // What is under test is the harness's ability to see a decode that returned
    // past ITS budget, and that is exactly as true at 5 ms.
    let tight = FuzzBudgets(softTimeMs: 5)

    let cases: [(FuzzSubject, FuzzBudgets)] = [
      (
        Self.everyNth(3, "mutant:throws") {
          // The real subject's `catch` arm writes this same field, which is what
          // makes this a proof about the harness rather than about a mock.
          FuzzSubjectResult(untypedError: "DeliberateEscape: \(DeliberateEscape())")
        }, FuzzBudgets()
      ),
      (
        Self.everyNth(5, "mutant:slow") {
          Thread.sleep(forTimeInterval: 0.025)
          return FuzzSubjectResult(refusedCode: "INVALID_JSON")
        }, tight
      ),
      (
        Self.everyNth(7, "mutant:determinism-broken") {
          FuzzSubjectResult(accepted: true, deterministic: false)
        }, FuzzBudgets()
      ),
      (
        Self.everyNth(11, "mutant:no-verdict") { FuzzSubjectResult() },
        FuzzBudgets()
      ),
    ]

    for (subject, budgets) in cases {
      let stats = fuzzRun(
        subjects: [subject], budgets: budgets, cfg: .bounded, seed: fuzzDefaultSeed,
        iterations: 200, seeds: seeds, vocab: vocab,
        options: FuzzRunOptions(minimise: false))
      XCTAssertFalse(
        stats.counterexamples.isEmpty,
        "\(subject.name) produced no counterexample — the harness cannot see this defect class")
      // The inverse pin, in the same place as the claim it qualifies.
      XCTAssertLessThan(
        stats.counterexamples.count, stats.inputs,
        "\(subject.name) broke EVERY input — it proves nothing about the harness's discrimination")
    }
  }

  /// The minimiser has to actually reduce, or a reported counterexample is no more
  /// replayable than the raw payload.
  func testTheMinimiserReducesAFindWhilePreservingItsClass() throws {
    // A subject that escapes on any input containing `Z`: the minimiser must be
    // able to strip everything else and keep the class.
    let subject = FuzzSubject(name: "mutant:escapes-on-Z") { input in
      input.contains("Z")
        ? FuzzSubjectResult(untypedError: "deliberate")
        : FuzzSubjectResult(refusedCode: "INVALID_JSON")
    }
    let payload = fuzzScalars(
      String(repeating: "abcdefgh", count: 40) + "Z" + String(repeating: "ijkl", count: 40))
    let m = fuzzCheck(subject, FuzzBudgets(), fuzzText(payload))
    XCTAssertTrue(m.verdict.isCounterexample, "the fixture subject did not go red")
    let minimised = fuzzMinimise(subject, FuzzBudgets(), payload, fuzzVerdictClass(m.verdict))
    XCTAssertLessThan(minimised.count, payload.count, "the minimiser reduced nothing")
    XCTAssertTrue(
      fuzzText(minimised).contains("Z"),
      "the minimiser reduced past the cause: \(fuzzText(minimised).debugDescription)")
    XCTAssertEqual(
      fuzzVerdictClass(fuzzCheck(subject, FuzzBudgets(), fuzzText(minimised)).verdict),
      fuzzVerdictClass(m.verdict), "the minimised input changed class")
  }

  // ─── The two findings, as regression tests ──────────────────────────────────

  /// The FIRST defect this leg found, now a regression test on the fix: a JSON
  /// number that `Int` cannot represent — non-finite, or outside its range — is
  /// refused by TYPE on the slot that asked for an integer, where `Int(Double)`
  /// used to trap and end the process. Finite values keep the reference host's
  /// truncation, so the accepted side of the contract did not move.
  func testNonFiniteAndOutOfRangeIntegerSlotsAreRefusedByType() throws {
    let refused: [(String, String, String)] = [
      (
        #"{"id":"a","kind":{"$type":"Heading","level":1e999,"text":"x","variant":"Standard"}}"#,
        "$.kind.level", "infinite"
      ),
      (
        #"{"id":"a","kind":{"$type":"Heading","level":-1e999,"text":"x","variant":"Standard"}}"#,
        "$.kind.level", "negative infinite"
      ),
      (
        #"{"id":"a","kind":{"$type":"Heading","level":1e30,"text":"x","variant":"Standard"}}"#,
        "$.kind.level", "finite but greater than Int.max"
      ),
      (
        #"{"id":"a","kind":{"$type":"Skeleton","rows":1e999}}"#,
        "$.kind.rows", "a different spec, the same root cause — every int slot is affected"
      ),
    ]
    for (input, path, why) in refused {
      do {
        _ = try RenderProjection.decodeNode(input)
        XCTFail("ACCEPTED an integer slot Int cannot hold (\(why)): \(input)")
      } catch let e as FuaranDecodeError {
        XCTAssertEqual(e.code, .wrongType, "\(why): wrong code — \(e)")
        XCTAssertEqual(e.path, path, "\(why): the refusal names the slot — \(e)")
      } catch {
        XCTFail("\(why): threw an untyped error \(error)")
      }
    }

    // The accepted side did not move: a finite in-range value truncates toward
    // zero, as the reference host's decoder does.
    guard
      case .heading(let spec) = try RenderProjection.decodeNode(
        #"{"id":"a","kind":{"$type":"Heading","level":2.9,"text":"x","variant":"Standard"}}"#
      ).kind
    else { return XCTFail("a Heading with a fractional level no longer decodes") }
    XCTAssertEqual(spec.level, 2, "a finite value truncates toward zero, as the reference host does")
  }

  /// The SECOND defect this leg found, now a regression test on the fix: a
  /// map-decoded slot (`FragmentRef.args`, `Mount.inputs`, `I18n.args`) decodes
  /// in ONE order — sorted by name — and a document with two invalid entries is
  /// refused with ONE code at ONE path, every time. Both were dictionary
  /// iteration order before the sort. The `nan-inequality` exemption that shares
  /// this machinery is pinned here too, with the reason it is a limit of the
  /// invariant and not a defect.
  func testMapDecodedSlotsDecodeInAStableOrder() throws {
    let reproducer =
      #"{"id":"f","kind":{"$type":"FragmentRef","args":{"ow":{"$type":"Str","value":"Os"},"l":{"$type":"Int","value":2},"t":{"$type":"Str","value":"In"}},"name":"s"}}"#
    var orders = Set<String>()
    for _ in 0..<24 {
      guard case .fragmentRef(let spec) = try RenderProjection.decodeNode(reproducer).kind
      else { return XCTFail("the reproducer no longer decodes as a FragmentRef") }
      orders.insert(spec.args.map(\.name).joined(separator: ","))
    }
    XCTAssertEqual(orders, ["l,ow,t"], "FragmentRef.args decodes sorted by name, every time")

    // Two invalid entries: the refusal is the FIRST by name, and only ever that one.
    let twoBadArgs =
      #"{"id":"f","kind":{"$type":"FragmentRef","args":{"a":{"$type":"Nope"},"b":42},"name":"s"}}"#
    var refusals = Set<String>()
    for _ in 0..<40 {
      do {
        _ = try RenderProjection.decodeNode(twoBadArgs)
        XCTFail("a document with two invalid args was ACCEPTED")
      } catch let e as FuaranDecodeError {
        refusals.insert("\(e.code.rawValue)@\(e.path)")
      }
    }
    XCTAssertEqual(refusals.count, 1, "one refusal, whichever entry the dictionary would have walked first: \(refusals)")
    XCTAssertTrue(
      refusals.first?.hasSuffix("@$.kind.args.a.$type") == true,
      "the refusal names the first entry BY NAME, not by iteration order: \(refusals)")

    // The `Binding.I18n` arm, the third site: the same rule. It is reached through
    // a `Bound` text source, which is where the named-binding form of `args` lives.
    let i18n =
      #"{"id":"m","kind":{"$type":"Markdown","text":{"$type":"Bound","binding":{"$type":"I18n","key":"k","args":{"z":{"$type":"State","key":"z","defaultValue":""},"a":{"$type":"State","key":"a","defaultValue":""}}}}}}"#
    var i18nOrders = Set<String>()
    for _ in 0..<24 {
      guard case .markdown(let spec) = try RenderProjection.decodeNode(i18n).kind,
        case .bound(.i18n(_, let args)) = spec.text
      else { return XCTFail("the I18n reproducer no longer decodes as a bound I18n binding") }
      i18nOrders.insert((args ?? []).map(\.name).joined(separator: ","))
    }
    XCTAssertEqual(i18nOrders, ["a,z"], "Binding.I18n.args decodes sorted by name, every time")

    // The one exemption that remains: the harness's limit, not the decoder's error.
    let nan =
      #"{"id":"l","kind":{"$type":"Sparkline","source":{"$type":"Static","value":[1,"NaN",3,5]}}}"#
    XCTAssertEqual(FuzzDeterminism.exemption(try JSON.parse(nan)), "nan-inequality")
    // TWO SEPARATE decodes, and the separateness is load-bearing: `Array ==` has a
    // fast path for operands sharing storage, so a value compared with ITSELF
    // returns true without ever reaching the NaN elements.
    let first = try RenderProjection.decodeNode(nan)
    let second = try RenderProjection.decodeNode(nan)
    XCTAssertNotEqual(
      first, second,
      "two decodes of a NaN-bearing tree compared EQUAL — if Double equality or the NaN "
        + "sentinel mapping changed, the `nan-inequality` exemption is no longer needed")

    // The inverse pin: the exemption must not swallow ordinary documents — the
    // map-ordered reproducer included, now that it decodes deterministically.
    for input in [
      #"{"id":"a","kind":{"$type":"Heading","level":1,"text":"x","variant":"Standard"}}"#,
      reproducer,
      #"{"id":"a","kind":{"$type":"Nope"}}"#,
    ] {
      XCTAssertNil(
        FuzzDeterminism.exemption(try JSON.parse(input)),
        "the exemption is over-broad — it would skip \(input)")
    }

    // What the NaN predicate's over-breadth COSTS, asserted rather than asserted
    // away: it cannot tell a float sentinel from the same three letters used as
    // display text, so a heading reading "NaN" loses its determinism check. The
    // safe direction — one invariant on one document, never a refusal.
    let nanAsText =
      #"{"id":"a","kind":{"$type":"Heading","level":1,"text":"NaN","variant":"Standard"}}"#
    XCTAssertEqual(
      FuzzDeterminism.exemption(try JSON.parse(nanAsText)), "nan-inequality",
      "if the predicate became position-aware this over-breadth is gone — narrow the comment")
  }

  // ─── Direct unit tests: the unicode-escape and surrogate-pair path ─────────
  //
  // `JSON.parse`'s `parseUnicodeEscape` is the branch this leg's own generator
  // hammers hardest (every escape family is in the token alphabet), and it is the
  // one place where a malformed input can produce a PLAUSIBLE WRONG ANSWER rather
  // than a refusal — which no fuzz invariant can see, because a wrong character
  // decodes perfectly well. So the fuzz's statistical coverage is paired with these
  // direct assertions on the exact boundary.

  /// Every refusal on this path is `INVALID_JSON` at `$`; the harness asserts the
  /// message too, because on this branch the message is the whole diagnosis.
  private func expectParseRefusal(
    _ json: String, contains fragment: String, _ label: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    do {
      let v = try JSON.parse(json)
      XCTFail("\(label): ACCEPTED \(json.debugDescription) as \(v)", file: file, line: line)
    } catch let e as FuaranDecodeError {
      XCTAssertEqual(e.code, .invalidJson, "\(label): wrong code", file: file, line: line)
      XCTAssertTrue(
        e.message.contains(fragment),
        "\(label): expected a message naming \(fragment.debugDescription), got "
          + e.message.debugDescription, file: file, line: line)
    } catch {
      XCTFail("\(label): threw an untyped error \(error)", file: file, line: line)
    }
  }

  private func parseStringValue(_ json: String) throws -> String {
    guard case .object(let o) = try JSON.parse(json), case .string(let s)? = o["a"] else {
      throw FuaranDecodeError(code: .wrongType, path: "$.a", message: "not a string")
    }
    return s
  }

  func testAValidSurrogatePairDecodesToTheSupplementaryScalar() throws {
    XCTAssertEqual(
      try parseStringValue(fuzzDoc(fuzzEsc("D83D") + fuzzEsc("DE00"))), fuzzChar(0x1F600))
    // The two ends of the supplementary range, so the arithmetic is pinned at both
    // boundaries rather than at one convenient midpoint.
    XCTAssertEqual(
      try parseStringValue(fuzzDoc(fuzzEsc("D800") + fuzzEsc("DC00"))), fuzzChar(0x10000))
    XCTAssertEqual(
      try parseStringValue(fuzzDoc(fuzzEsc("DBFF") + fuzzEsc("DFFF"))), fuzzChar(0x10FFFF))
    // Surrounded by ordinary text, so the parser's index bookkeeping across a
    // twelve-character escape is exercised rather than only the escape itself.
    XCTAssertEqual(
      try parseStringValue(fuzzDoc("x" + fuzzEsc("D83D") + fuzzEsc("DE00") + "y")),
      "x" + fuzzChar(0x1F600) + "y")
  }

  func testALoneLowSurrogateIsRefusedByName() throws {
    // The refusal names the MISSING HIGH HALF. `Unicode.Scalar(0xDC00)` is already
    // nil, so a bare guard would refuse it too — but as "invalid unicode escape",
    // which sends an author to inspect their hex digits rather than to notice what
    // is actually wrong.
    expectParseRefusal(
      fuzzDoc(fuzzEsc("DC00")), contains: "must follow a high surrogate",
      "lone low surrogate DC00")
    expectParseRefusal(
      fuzzDoc(fuzzEsc("DFFF")), contains: "must follow a high surrogate",
      "lone low surrogate DFFF")
  }

  func testAHighSurrogateFollowedByAnEscapeOutsideTheLowRangeIsRefused() throws {
    // THE case this branch was changed for. The arithmetic subtracts 0xDC00
    // unconditionally, so before the guard a high surrogate followed by an escape
    // for U+0041 combined to U+0F83D — a Tibetan character bearing no relation to
    // either half — and the `Unicode.Scalar` check said nothing, because the sum
    // happened to land on a scalar that exists. A malformed pair became a
    // plausible-looking wrong character, silently, in decoded document text.
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D83D") + fuzzEsc("0041")), contains: "expected a low surrogate",
      "high surrogate + an escape for U+0041")
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D800") + fuzzEsc("D800")), contains: "expected a low surrogate",
      "high surrogate + another high surrogate")
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D800") + fuzzEsc("0000")), contains: "expected a low surrogate",
      "high surrogate + a NUL escape")
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D800") + fuzzEsc("FFFF")), contains: "expected a low surrogate",
      "high surrogate + a non-surrogate BMP escape")

    // The regression guard proper: the pre-change combination must not be reachable
    // by ANY route. Asserting the refusal above says the input is rejected; this
    // says the wrong ANSWER is gone, which is the property that actually mattered.
    if let wrong = try? parseStringValue(fuzzDoc(fuzzEsc("D83D") + fuzzEsc("0041"))) {
      XCTFail("the malformed pair still decodes, to \(wrong.unicodeScalars.map { $0.value })")
    }

    // WHY the `Unicode.Scalar` guard could not have caught this, computed rather
    // than asserted from memory. The arithmetic subtracts 0xDC00 unconditionally,
    // so this pair lands on a code point that is perfectly VALID — which is the
    // whole mechanism: the malformed input did not fail a validity check, it
    // passed one, and produced an unrelated character.
    let preChange = 0x10000 + ((0xD83D - 0xD800) << 10) + (0x0041 - 0xDC00)
    XCTAssertNotNil(
      Unicode.Scalar(UInt32(preChange)),
      "if this combination were NOT a valid scalar the range guard alone would have "
        + "refused it, and the named low-surrogate check would be redundant")
    // Pinned so a change to the arithmetic shows up here as well as in the refusal.
    XCTAssertEqual(preChange, 0x11841)
  }

  func testAHighSurrogateNotFollowedByAnEscapeAtAllIsRefused() throws {
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D800") + "x"), contains: "expected low surrogate",
      "high surrogate + literal text")
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D800")), contains: "expected low surrogate",
      "high surrogate at end of string")
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D800") + fuzzEsc2("n")), contains: "expected low surrogate",
      "high surrogate + a two-character escape")
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D800") + fuzzEsc2(fuzzBackslash)), contains: "expected low surrogate",
      "high surrogate + an escaped backslash")
  }

  func testATruncatedOrMalformedEscapeIsRefused() throws {
    expectParseRefusal(
      fuzzDoc(fuzzBackslash + "uD8"), contains: "invalid hex digit",
      "two hex digits then a quote")
    expectParseRefusal(
      fuzzDoc(fuzzBackslash + "u"), contains: "invalid hex digit", "no hex digits")
    expectParseRefusal(
      fuzzDoc(fuzzBackslash + "uZZZZ"), contains: "invalid hex digit", "non-hex digits")
    expectParseRefusal(
      fuzzDoc(fuzzEsc("D83D") + fuzzBackslash + "uDE0"), contains: "invalid hex digit",
      "truncated low half")
    expectParseRefusal(
      fuzzDoc(fuzzEsc2("q")), contains: "invalid escape", "an unknown escape letter")
    // Genuinely running off the end of the document, rather than hitting a quote.
    expectParseRefusal(
      "{\"a\":\"" + fuzzBackslash + "u00", contains: "truncated", "input ends mid-escape")
  }

  func testTheOrdinaryEscapeFamiliesStillDecode() throws {
    // The negative tests above are only meaningful beside a positive one: a parser
    // that refused every escape would pass all of them.
    XCTAssertEqual(
      try parseStringValue(
        fuzzDoc(fuzzEsc("0041") + fuzzEsc("00E9") + fuzzEsc("4E2D") + fuzzEsc("FFFD"))),
      "Aé中" + fuzzChar(0xFFFD))
    let two =
      fuzzEsc2("\"") + fuzzEsc2(fuzzBackslash) + fuzzEsc2("/") + fuzzEsc2("b") + fuzzEsc2("f")
      + fuzzEsc2("n") + fuzzEsc2("r") + fuzzEsc2("t")
    XCTAssertEqual(
      try parseStringValue(fuzzDoc(two)),
      "\"" + fuzzBackslash + "/" + fuzzChar(0x08) + fuzzChar(0x0C) + "\n\r\t")
    XCTAssertEqual(try parseStringValue(fuzzDoc(fuzzEsc("0000"))), fuzzChar(0x0000))
  }
}
