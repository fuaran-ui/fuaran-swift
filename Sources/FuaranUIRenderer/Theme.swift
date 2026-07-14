// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The SwiftUI tone bridge (Phase 541) — the Swift twin of the Kotlin Material
// tone bridge. The wire's class-name / tone vocabulary (the Phase 12-H styling
// contract: `ToneVariant`, `Emphasis`, `StyleWeight`, `HeadingVariant`) is
// mapped onto a SwiftUI styling layer so server-emitted styling *intent* renders
// with native styling and adapts to the platform light/dark colour scheme with
// no per-node colour handling.
//
// `FuaranTheme` provides a scheme-matched `FuaranTonePalette` through
// `@Environment(\.fuaranTones)`; because the palette is provided per-scheme, the
// same tone token resolves to different, scheme-correct colours in light vs dark
// — the acceptance-criterion "differs visibly and correctly between light and
// dark". Spacing + emphasis/heading typography are pure (scheme-independent) and
// unit-testable without a live view.
//
// Guarded by `#if canImport(SwiftUI)` — the whole bridge is SwiftUI-typed.

#if canImport(SwiftUI)

  import FuaranUI
  import SwiftUI

  // ── Tone colour tokens ──────────────────────────────────────────────────────

  /// A resolved tone swatch: a filled container, its readable foreground, and an
  /// accent for emphasis.
  public struct ToneSwatch: Sendable {
    public let container: Color
    public let onContainer: Color
    public let accent: Color
    public init(container: Color, onContainer: Color, accent: Color) {
      self.container = container
      self.onContainer = onContainer
      self.accent = accent
    }
  }

  /// The full tone palette for one platform scheme. A light and a dark instance
  /// exist (`LightTones` / `DarkTones`); `FuaranTheme` provides the
  /// scheme-appropriate one so a tone token is scheme-aware by construction.
  public struct FuaranTonePalette: Sendable {
    public let defaultTone: ToneSwatch
    public let subdued: ToneSwatch
    public let brand: ToneSwatch
    public let success: ToneSwatch
    public let warning: ToneSwatch
    public let critical: ToneSwatch
    public let info: ToneSwatch

    /// Resolve a `ToneVariant` to its swatch. Exhaustive over the sealed vocab.
    public func swatch(_ tone: ToneVariant) -> ToneSwatch {
      switch tone {
      case .default: return defaultTone
      case .subdued: return subdued
      case .brand: return brand
      case .success: return success
      case .warning: return warning
      case .critical: return critical
      case .info: return info
      }
    }

    /// Map the badge-variant vocabulary onto the palette (Neutral → subdued).
    public func badge(_ variant: BadgeVariant) -> ToneSwatch {
      switch variant {
      case .neutral: return subdued
      case .brand: return brand
      case .success: return success
      case .warning: return warning
      case .critical: return critical
      case .info: return info
      }
    }
  }

  private func rgb(_ r: Int, _ g: Int, _ b: Int) -> Color {
    Color(red: Double(r) / 255, green: Double(g) / 255, blue: Double(b) / 255)
  }

  /// Light-scheme tones — higher-luminance containers, dark foregrounds.
  public let LightTones = FuaranTonePalette(
    defaultTone: ToneSwatch(container: rgb(242, 242, 245), onContainer: rgb(27, 27, 31), accent: rgb(58, 58, 64)),
    subdued: ToneSwatch(container: rgb(230, 230, 234), onContainer: rgb(90, 90, 98), accent: rgb(116, 116, 124)),
    brand: ToneSwatch(container: rgb(220, 227, 255), onContainer: rgb(0, 26, 65), accent: rgb(45, 91, 208)),
    success: ToneSwatch(container: rgb(211, 241, 218), onContainer: rgb(4, 54, 26), accent: rgb(30, 123, 69)),
    warning: ToneSwatch(container: rgb(253, 231, 194), onContainer: rgb(62, 46, 0), accent: rgb(154, 106, 0)),
    critical: ToneSwatch(container: rgb(253, 218, 214), onContainer: rgb(65, 0, 2), accent: rgb(186, 26, 26)),
    info: ToneSwatch(container: rgb(207, 231, 245), onContainer: rgb(4, 48, 63), accent: rgb(12, 110, 147)))

  /// Dark-scheme tones — low-luminance containers, light foregrounds.
  public let DarkTones = FuaranTonePalette(
    defaultTone: ToneSwatch(container: rgb(42, 42, 46), onContainer: rgb(228, 226, 230), accent: rgb(199, 198, 203)),
    subdued: ToneSwatch(container: rgb(53, 53, 58), onContainer: rgb(182, 181, 188), accent: rgb(154, 154, 161)),
    brand: ToneSwatch(container: rgb(21, 52, 111), onContainer: rgb(219, 225, 255), accent: rgb(174, 198, 255)),
    success: ToneSwatch(container: rgb(20, 81, 44), onContainer: rgb(185, 240, 197), accent: rgb(138, 214, 162)),
    warning: ToneSwatch(container: rgb(92, 66, 0), onContainer: rgb(252, 223, 166), accent: rgb(231, 180, 91)),
    critical: ToneSwatch(container: rgb(147, 0, 10), onContainer: rgb(255, 218, 214), accent: rgb(255, 180, 171)),
    info: ToneSwatch(container: rgb(0, 73, 95), onContainer: rgb(188, 231, 250), accent: rgb(127, 208, 240)))

  // ── The ambient palette + theme wrapper ─────────────────────────────────────

  private struct FuaranTonesKey: EnvironmentKey {
    static let defaultValue: FuaranTonePalette = LightTones
  }

  extension EnvironmentValues {
    /// The ambient tone palette; defaults to the light set so a tone read outside
    /// `FuaranTheme` still resolves.
    public var fuaranTones: FuaranTonePalette {
      get { self[FuaranTonesKey.self] }
      set { self[FuaranTonesKey.self] = newValue }
    }
  }

  /// Install the Fuaran tone theme: provide the scheme-matched
  /// `FuaranTonePalette`. Follows the platform light/dark preference by default;
  /// pass `dark` to force a scheme (the render tests drive both explicitly).
  public struct FuaranTheme<Content: View>: View {
    @Environment(\.colorScheme) private var colorScheme
    private let forcedDark: Bool?
    private let content: Content

    public init(dark: Bool? = nil, @ViewBuilder content: () -> Content) {
      self.forcedDark = dark
      self.content = content()
    }

    public var body: some View {
      let dark = forcedDark ?? (colorScheme == .dark)
      content.environment(\.fuaranTones, dark ? DarkTones : LightTones)
    }
  }

  // ── Typography tokens (pure — scheme-independent) ───────────────────────────

  /// The font weight the `Emphasis` facet maps to.
  public func emphasisWeight(_ emphasis: Emphasis) -> Font.Weight {
    switch emphasis {
    case .quiet: return .light
    case .normal: return .regular
    case .loud: return .bold
    }
  }

  /// A relative type-scale multiplier the `Emphasis` facet maps to (1.0 = base).
  public func emphasisScale(_ emphasis: Emphasis) -> CGFloat {
    switch emphasis {
    case .quiet: return 0.9
    case .normal: return 1.0
    case .loud: return 1.15
    }
  }

  /// The base heading point size (before `emphasisScale`) for a variant × level.
  public func headingSize(_ variant: HeadingVariant, _ level: Int) -> CGFloat {
    let base: CGFloat = {
      switch min(max(level, 1), 6) {
      case 1: return 26
      case 2: return 22
      case 3: return 19
      case 4: return 17
      case 5: return 15
      default: return 13
      }
    }()
    switch variant {
    case .standard: return base
    case .lead: return base * 1.1
    case .eyebrow: return 12
    case .caption: return 11
    }
  }

  // ── Spacing tokens (pure) ───────────────────────────────────────────────────

  /// Spacing tokens keyed off the `StyleWeight` density vocabulary.
  public enum FuaranSpacing {
    /// The inner padding a themed container applies at each density.
    public static func pad(_ weight: StyleWeight) -> CGFloat {
      switch weight {
      case .compact: return 4
      case .standard: return 8
      case .spacious: return 14
      }
    }

    /// The gap between siblings at each density.
    public static func gap(_ weight: StyleWeight) -> CGFloat {
      switch weight {
      case .compact: return 2
      case .standard: return 6
      case .spacious: return 12
      }
    }
  }

#endif
