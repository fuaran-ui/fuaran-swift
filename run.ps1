#Requires -Version 7.0
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Diametrical Ltd.
#
# Stage-0 entry point for fuaran-swift — the native Swift surface over the Rust
# reference core of the Fuaran UI wire format.
#
#   pwsh ./run.ps1                 # C-ABI header check + swift build + swift test
#   pwsh ./run.ps1 -SkipBuild      # switches: -SkipBuild / -SkipTests
#
# `-Package` is GONE, deliberately. It advertised assembling a
# FuaranCore.xcframework and never did: off macOS it skipped, and ON macOS it
# printed "packaging implementation is macOS-side" and produced nothing — while a
# CI job invoked it and reported success. A switch that reports success for work
# it does not do is worse than an absent one; it is the mechanism by which
# everything downstream came to believe an xcframework exists. See the README's
# "Consuming this package" section for what IS true today.
#
# The macOS toolchain is the reference target. On a machine with no Swift
# toolchain (or an incomplete Windows toolchain), the build/test legs SKIP
# cleanly so the workspace sweep stays green — mirroring how the sibling Rust
# host skips its Apple-only legs with a named message. The header check below
# runs REGARDLESS, because it needs no toolchain at all.

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

# SEED $LASTEXITCODE BEFORE ANY STAGE READS IT.
#
# PowerShell leaves it UNSET until the session's first native command, and it does not
# reset it between commands afterwards. Both halves bite:
#
#   * unset, `$LASTEXITCODE -ne 0` is `$null -ne 0`, which is TRUE — so a check reached
#     before any native command runs reports a failure that did not happen;
#   * set, it survives into a stage that ran no native command of its own, which is then
#     graded on whatever the last unrelated one left behind.
#
# The sibling `Fuaran-Program` launcher shipped the first half and returned a green `exit
# $null` having built and tested nothing. Seeding it costs one line and removes the class.
$LASTEXITCODE = 0

function Write-Skip($msg) { Write-Host "SKIP: $msg" -ForegroundColor Yellow }
function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

# ── C-ABI header drift (the reference-stylesheet shape) ───────────────────────
# `Sources/FuaranCore/include/fuaran.h` is a COPY. The reference lives in the Rust
# core; this leg byte-compares them when the sibling checkout is present.
#
# It runs BEFORE the toolchain gate on purpose: it is a text comparison needing no
# Swift, no MSVC linker and no Rust, so a box with none of them still answers the
# one question it CAN answer instead of exiting 0 having checked nothing. The copy
# was 56 lines behind the reference — missing an entire family of session verbs —
# and every gate in this repository was green throughout, because nothing compared
# them.
#
# NOT CHECKED rather than a quiet pass when the sibling is absent: a single-repo
# checkout has no sibling, and a green line saying nothing about the header would
# read to every later log reader as "the copy is current".
$HeaderCopy = Join-Path $PSScriptRoot "Sources/FuaranCore/include/fuaran.h"
$HeaderRef = Join-Path $PSScriptRoot "../fuaran-rs/include/fuaran.h"
Write-Step "C-ABI header (fuaran.h) drift"
if (-not (Test-Path $HeaderCopy)) {
    throw "fuaran.h copy missing at $HeaderCopy — the FuaranCore module target cannot build without it."
}
elseif (-not (Test-Path $HeaderRef)) {
    Write-Skip "no sibling core checkout at $HeaderRef — NOT CHECKED, the copy was not compared."
}
elseif ((Get-FileHash -Algorithm SHA256 $HeaderCopy).Hash -ne (Get-FileHash -Algorithm SHA256 $HeaderRef).Hash) {
    throw @"
fuaran.h has drifted from the reference.

  copy:      $HeaderCopy
  reference: $HeaderRef

The copy is GENERATED — regenerate it rather than hand-editing either side:
  Copy-Item '$HeaderRef' '$HeaderCopy'

Then read the diff before committing. A declaration this module is missing is a
verb Swift cannot call; one whose signature has changed is a link-time or run-time
fault on a device, which is the failure this check exists to move to build time.
"@
}
else {
    Write-Host "  fuaran.h byte-identical to the reference." -ForegroundColor Green
}

# ── Corpus pin drift (Phase 1703) ─────────────────────────────────────────────
# `corpus-pin.json` records the ONE corpus revision this repository's gates certify
# against, and CI checks the corpus out at it. That closes the class where a corpus
# commit reddens this repository with no change of its own — at the price of a
# SILENT staleness if nobody ever looks, which is exactly why the distance is
# reported here and on every CI run rather than only when something breaks.
#
# Advisory, never fatal: being behind the corpus is the ordinary resting state
# between an authored fixture and the decoder work that adopts it. Same placement
# and same reasoning as the header check above — a text comparison needing no
# toolchain, so a box with none still answers the question it CAN answer.
Write-Step "corpus pin drift"
$LASTEXITCODE = 0
& pwsh -NoProfile -File (Join-Path $PSScriptRoot "dev-scripts/corpus-pin.ps1")
if ($LASTEXITCODE -eq 2) {
    Write-Skip "the corpus has moved past the pin (above). Adopting it is a deliberate change-set, not a sweep."
}
$LASTEXITCODE = 0

# ── Toolchain presence ────────────────────────────────────────────────────────
$swift = Get-Command swift -ErrorAction SilentlyContinue
if (-not $swift) {
    Write-Skip "no Swift toolchain on PATH — fuaran-swift is a Swift-toolchain (macOS-reference) leg. Nothing to build here."
    exit 0
}

# ── Windows: Swift/SwiftPM needs SDKROOT + the MSVC linker ─────────────────────
# (On macOS both are provided by the platform toolchain and this block is a no-op.)
if ($IsWindows) {
    if (-not $env:SDKROOT) {
        $userSdk = [Environment]::GetEnvironmentVariable('SDKROOT', 'User')
        if ($userSdk) { $env:SDKROOT = $userSdk }
    }
    if (-not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
        $vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
        if (Test-Path $vswhere) {
            # -prerelease: without it vswhere skips Insiders/Preview installs entirely, returning
            # empty on a machine whose only VS is prerelease — and a null $vsRoot must fall through
            # to the clean skip below, never into Join-Path.
            $vsRoot = & $vswhere -latest -prerelease -products * -property installationPath | Select-Object -First 1
            if ($vsRoot) {
                # Match the vcvars script to the HOST architecture: vcvars64 on an ARM64 host
                # imports the x64 cross environment, not the native ARM64 one.
                $vcvarsName = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'vcvarsarm64.bat' } else { 'vcvars64.bat' }
                $vcvars = Join-Path $vsRoot "VC\Auxiliary\Build\$vcvarsName"
                if (Test-Path $vcvars) {
                    Write-Step "importing MSVC build environment ($vcvarsName)"
                    cmd /c "`"$vcvars`" >nul 2>&1 && set" | ForEach-Object {
                        if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:\$($matches[1])" -Value $matches[2] }
                    }
                }
            }
        }
    }
    if (-not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
        Write-Skip "MSVC linker (link.exe) not found — Swift on Windows links through Visual Studio Build Tools. Skipping build/test."
        exit 0
    }
}

# ── Rust reference core staticlib (enables the C-ABI session leg) ──────────────
# The FuaranSession actor + SessionTests link the Rust reference core's native
# staticlib. Build it best-effort from the sibling repo; Package.swift then
# auto-detects it at `../fuaran-rs/target/debug` (or an explicit
# FUARAN_RS_STATICLIB_DIR). If it is absent, the session leg skips cleanly and
# the pure-Swift render projection still builds + tests.
if (-not $env:FUARAN_RS_STATICLIB_DIR) {
    $rsDir = Join-Path $PSScriptRoot "..\fuaran-rs"
    $cargo = Get-Command cargo -ErrorAction SilentlyContinue
    if ((Test-Path $rsDir) -and $cargo) {
        Write-Step "building the Rust reference core staticlib (cargo build in ../fuaran-rs)"
        Push-Location $rsDir
        # Seeded again HERE, not only at the top: `cargo` may throw before it runs at all
        # (the catch below swallows that), in which case $LASTEXITCODE still holds whatever
        # the vcvars import or vswhere probe left — and the check would then report a cargo
        # failure that never happened, or miss one that did.
        $LASTEXITCODE = 0
        try { & cargo build } catch { $LASTEXITCODE = 1 }
        Pop-Location
        # BEST-EFFORT, deliberately: this leg only ENABLES the C-ABI session tests. Its
        # failure is reported and skipped, never fatal — unlike `swift build` / `swift test`
        # below, which are the gate and exit with their own code.
        if ($LASTEXITCODE -ne 0) {
            Write-Skip "cargo build did not succeed in ../fuaran-rs; the C-ABI session leg will use any existing staticlib or skip."
        }
    }
}

# ── Build + test ──────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Step "swift build"
    & swift build
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

if (-not $SkipTests) {
    Write-Step "swift test"
    & swift test
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
}

Write-Host "OK" -ForegroundColor Green
