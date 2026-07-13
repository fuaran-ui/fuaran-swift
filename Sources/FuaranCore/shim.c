/* SPDX-License-Identifier: Apache-2.0 */
/* Copyright 2026 Diametrical Ltd. */
/*
 * FuaranCore — the C-ABI header shim for the Fuaran UI wire-format Rust
 * reference core. This target exposes the hand-written `fuaran.h` surface to
 * Swift as an importable module; the concrete symbols are resolved at link time
 * from the Rust reference core's native staticlib (or, on Apple platforms, the
 * FuaranCore.xcframework binary target). This translation unit exists only so
 * the target has a source file; it carries no logic.
 */
#include "fuaran.h"
