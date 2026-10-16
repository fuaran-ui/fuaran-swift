// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// `swift run fuaran-idl-gen [<idl.json>] [<out>]` — regenerate the sealed tree
// model from the wire corpus's `idl.json` (Phase 2299). With no arguments it
// reads `$FUARAN_WIRE_FIXTURES/idl.json` and writes the package's generated
// file; the regenerate-or-drift test in `FuaranUITests` runs the same generator.

import Foundation
import FuaranUIIdlGen

let args = Array(CommandLine.arguments.dropFirst())
let env = ProcessInfo.processInfo.environment
let packageRoot = URL(fileURLWithPath: #filePath)
  .deletingLastPathComponent()  // fuaran-idl-gen
  .deletingLastPathComponent()  // Sources
  .deletingLastPathComponent()  // the package root

let idlPath: String
if let first = args.first {
  idlPath = first
} else if let fixtures = env["FUARAN_WIRE_FIXTURES"], !fixtures.isEmpty {
  idlPath = URL(fileURLWithPath: fixtures).appendingPathComponent("idl.json").path
} else {
  FileHandle.standardError.write(
    Data("usage: fuaran-idl-gen <idl.json> [<out>] (or set FUARAN_WIRE_FIXTURES)\n".utf8))
  exit(2)
}
let outPath =
  args.count > 1
  ? args[1] : packageRoot.appendingPathComponent(IdlCodegen.generatedRelativePath).path

do {
  let bytes = try Data(contentsOf: URL(fileURLWithPath: idlPath))
  let text = try IdlCodegen.generate(idl: bytes)
  try Data(text.utf8).write(to: URL(fileURLWithPath: outPath))
  print("wrote \(outPath) from \(idlPath) (idl.json sha256 \(IdlCodegen.sha256(bytes)))")
} catch {
  FileHandle.standardError.write(Data("fuaran-idl-gen: \(error)\n".utf8))
  exit(1)
}
