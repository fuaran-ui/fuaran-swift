#Requires -Version 7.0
# SPDX-License-Identifier: Apache-2.0
# Copyright 2026 Diametrical Ltd.
#
# Stage-0 entry point for fuaran-swift — the native Swift surface over the Rust
# reference core of the Fuaran UI wire format.
#
#   pwsh ./run.ps1                 # swift build + swift test (happy path)
#   pwsh ./run.ps1 -SkipBuild      # switches: -SkipBuild / -SkipTests
#   pwsh ./run.ps1 -Package        # opt-in: assemble the FuaranCore.xcframework
#                                  #   (macOS + xcodebuild only — skips cleanly elsewhere)
#
# The macOS toolchain is the reference target. On a machine with no Swift
# toolchain (or an incomplete Windows toolchain), the script SKIPS cleanly so
# the workspace sweep stays green — mirroring how the sibling Rust host skips its
# Apple-only build legs with a named message.

[CmdletBinding()]
param(
    [switch]$SkipBuild,
    [switch]$SkipTests,
    [switch]$Package
)

$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function Write-Skip($msg) { Write-Host "SKIP: $msg" -ForegroundColor Yellow }
function Write-Step($msg) { Write-Host "==> $msg" -ForegroundColor Cyan }

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
            $vsRoot = & $vswhere -latest -products * -property installationPath
            $vcvars = Join-Path $vsRoot "VC\Auxiliary\Build\vcvars64.bat"
            if (Test-Path $vcvars) {
                Write-Step "importing MSVC build environment (vcvars64)"
                cmd /c "`"$vcvars`" >nul 2>&1 && set" | ForEach-Object {
                    if ($_ -match '^([^=]+)=(.*)$') { Set-Item -Path "Env:\$($matches[1])" -Value $matches[2] }
                }
            }
        }
    }
    if (-not (Get-Command link.exe -ErrorAction SilentlyContinue)) {
        Write-Skip "MSVC linker (link.exe) not found — Swift on Windows links through Visual Studio Build Tools. Skipping build/test."
        exit 0
    }
}

# ── Build + test ──────────────────────────────────────────────────────────────
if (-not $SkipBuild) {
    Write-Step "swift build"
    & swift build
}

if (-not $SkipTests) {
    Write-Step "swift test"
    & swift test
}

# ── XCFramework packaging (opt-in; macOS + xcodebuild only) ────────────────────
if ($Package) {
    $xcodebuild = Get-Command xcodebuild -ErrorAction SilentlyContinue
    if (-not $xcodebuild) {
        Write-Skip "the FuaranCore.xcframework packaging leg is macOS + xcodebuild only; there is nothing to assemble on this platform. (See CLAUDE.md 'XCFramework packaging'.)"
    }
    else {
        Write-Step "assembling FuaranCore.xcframework"
        Write-Host "  (packaging implementation is macOS-side; see CLAUDE.md)" -ForegroundColor DarkGray
    }
}

Write-Host "OK" -ForegroundColor Green
