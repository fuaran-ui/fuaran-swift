// SPDX-License-Identifier: Apache-2.0
// Copyright 2026 Diametrical Ltd.
//
// The accessibility projection — a node's `Accessibility` trait rendered as
// SwiftUI accessibility modifiers.
//
// The HTML render tiers of the Fuaran UI wire format project the trait's six
// slots into `aria-*` attributes (`label` → `aria-label`, `labelledBy` →
// `aria-labelledby`, `describedBy` → `aria-describedby`, `role` → `role`,
// `liveRegion` → `aria-live`, `hidden` → `aria-hidden`). A SwiftUI surface has
// no attribute bag, so the projection is a mapping onto accessibility MODIFIERS,
// and the two vocabularies do not correspond one-for-one. The mapping — and,
// just as importantly, the slots that have no native equivalent — is decided and
// enumerated here; see `CLAUDE.md`, "Accessibility projection", for the decision
// record and its rationale.
//
// **Placement.** The reference host decides which element carries the projection
// (`../fuaran-dotnet/docs/DECISIONS.md`, D4: the node's semantic element rather
// than its wrapper `<div>`). A SwiftUI surface has no wrapper: `fuaranNodeBody`
// returns exactly the view the kind arm renders, so the node's own view IS the
// semantic element and the rule is satisfied by construction. It is applied at
// that one site, and there is deliberately no second emission point.
//
// **Pure, and deliberately OUTSIDE the SwiftUI gate** — the same reasoning as
// the grid-cell lowering in `BindingContext.swift`. The mapping decisions (which
// role tokens carry a trait, which slots are dropped, what an empty resolved
// label does) are the load-bearing part, and a helper that lives inside
// `#if canImport(SwiftUI)` can only ever be tested on macOS. Here they run on
// every platform; the thin modifier application below is the only Apple-gated
// half.

import Foundation
import FuaranUI

/// The six slots of the wire trait, named so a dropped one can be reported
/// rather than vanish. The order is the wire's own.
public enum AccessibilitySlot: String, CaseIterable, Equatable, Sendable {
  case label
  case labelledBy
  case describedBy
  case role
  case liveRegion
  case hidden
}

/// A SwiftUI accessibility trait, named platform-neutrally so the projection
/// itself stays testable off Apple platforms. Mapped to `AccessibilityTraits`
/// by `swiftUITraits` inside the SwiftUI gate.
public enum SemanticTrait: String, CaseIterable, Equatable, Sendable {
  /// `role: "button"` → `.isButton`.
  case button
  /// `role: "link"` → `.isLink`.
  case link
  /// `role: "heading"` → `.isHeader`.
  case header
  /// `liveRegion: polite | assertive` → `.updatesFrequently` (a PARTIAL mapping
  /// — see the projection's doc comment).
  case updatesFrequently
}

/// The resolved projection of one node's `Accessibility` trait: what SwiftUI can
/// carry, plus the slots it cannot.
public struct AccessibilityProjection: Equatable, Sendable {
  /// The resolved accessible name, or nil when the slot is absent or resolves
  /// empty. An empty resolved label is DROPPED rather than applied, mirroring
  /// the reference projection — an empty `.accessibilityLabel` would erase the
  /// view's natural name instead of leaving it alone.
  public var label: String?
  /// Traits to add. Additive by construction: the projection never REMOVES a
  /// trait the view earned natively.
  public var traits: [SemanticTrait]
  /// Whether the node is hidden from the accessibility tree.
  public var hidden: Bool
  /// Slots the author populated that this platform cannot express, in wire
  /// order. Carried rather than discarded so the drop set is assertable — the
  /// whole point of the policy in `CLAUDE.md`: dropped, never silently.
  public var unmapped: [AccessibilitySlot]

  public init(
    label: String? = nil, traits: [SemanticTrait] = [], hidden: Bool = false,
    unmapped: [AccessibilitySlot] = []
  ) {
    self.label = label
    self.traits = traits
    self.hidden = hidden
    self.unmapped = unmapped
  }

  /// Nothing to apply. Note `unmapped` is deliberately NOT consulted: a trait
  /// carrying only unmappable slots projects no modifier, so the view is
  /// returned untouched — the drop is reported, not rendered.
  public var isEmpty: Bool { label == nil && traits.isEmpty && !hidden }

  public static let none = AccessibilityProjection()
}

/// The role token → trait map. Keyed on the wire's own lowercase ARIA tokens,
/// matched EXACTLY: the reference projection emits the token the author
/// declared, and a case-folding match here would accept a spelling no HTML tier
/// honours. A token outside this map — including any custom role, whose meaning
/// the host cannot know — has no SwiftUI trait and is reported unmapped.
///
/// Three of the wire's roles map. The landmark roles (`banner` / `navigation` /
/// `main` / `form` / `region`), the tab family (`tab` / `tablist` / `tabpanel`),
/// `dialog`, `alert`, `status` and `progressbar` have no SwiftUI trait that
/// means what they mean, and are dropped rather than approximated: announcing a
/// `tab` as a button, or a `dialog` as `.isModal` (which is `aria-modal`, a
/// different assertion), would be a mis-statement rather than a partial one.
public func semanticTrait(forRole role: String) -> SemanticTrait? {
  switch role {
  case "button": return .button
  case "link": return .link
  case "heading": return .header
  default: return nil
  }
}

/// Project a node's `Accessibility` trait, resolving its bindings through the
/// render context.
///
/// **Fidelity limits, stated rather than assumed away.**
///
///  - `labelledBy` / `describedBy` carry another node's id. SwiftUI has no
///    id-referenced labelling or description — an accessible name is a value on
///    the element, not a pointer to another one — so both are dropped. Resolving
///    the reference here would mean walking the tree from a node that does not
///    have it, and inlining another node's text as this one's label is a
///    different assertion from `aria-labelledby`.
///  - `liveRegion` maps PARTIALLY. SwiftUI's live announcement is imperative
///    (`AccessibilityNotification`), fired when a value changes; a stateless
///    render projection has no change to fire on. `.updatesFrequently` is the
///    declarative half — it tells VoiceOver this element's value changes — so
///    `polite` and `assertive` both carry it and the politeness DISTINCTION is
///    lost. `off` maps exactly: it asserts "do not announce", which is the
///    platform default, so its faithful projection is the absence of the trait
///    rather than a drop.
public func accessibilityProjection(
  _ a11y: Accessibility?, _ ctx: BindingContext
) -> AccessibilityProjection {
  guard let a = a11y else { return .none }

  var unmapped: [AccessibilitySlot] = []
  var traits: [SemanticTrait] = []

  let resolvedLabel = a.label.map { ctx.resolve($0) }
  let label = (resolvedLabel?.isEmpty ?? true) ? nil : resolvedLabel

  if a.labelledBy != nil { unmapped.append(.labelledBy) }
  if a.describedBy != nil { unmapped.append(.describedBy) }

  if let role = a.role {
    if let trait = semanticTrait(forRole: role) {
      traits.append(trait)
    } else {
      unmapped.append(.role)
    }
  }

  switch a.liveRegion {
  case .polite, .assertive: traits.append(.updatesFrequently)
  case .off, nil: break
  }

  return AccessibilityProjection(
    label: label, traits: traits, hidden: ctx.resolveBool(a.hidden), unmapped: unmapped)
}

#if canImport(SwiftUI)

  import SwiftUI

  /// Map the platform-neutral traits onto SwiftUI's option set.
  func swiftUITraits(_ traits: [SemanticTrait]) -> AccessibilityTraits {
    var out = AccessibilityTraits()
    for trait in traits {
      switch trait {
      case .button: out.insert(.isButton)
      case .link: out.insert(.isLink)
      case .header: out.insert(.isHeader)
      case .updatesFrequently: out.insert(.updatesFrequently)
      }
    }
    return out
  }

  extension View {
    /// Apply a projection. Each modifier is applied only when the projection
    /// carries it: an unconditional `.accessibilityLabel(Text(""))` would ERASE
    /// the view's natural name, which is worse than the gap this projection
    /// closes.
    ///
    /// An empty projection returns the view untouched — so a node with no trait
    /// (which is every node in the shared corpus today) renders through exactly
    /// the path it rendered through before this projection existed.
    func fuaranAccessibility(_ projection: AccessibilityProjection) -> AnyView {
      var view = AnyView(self)
      if let label = projection.label {
        view = AnyView(view.accessibilityLabel(Text(label)))
      }
      if !projection.traits.isEmpty {
        view = AnyView(view.accessibilityAddTraits(swiftUITraits(projection.traits)))
      }
      if projection.hidden {
        view = AnyView(view.accessibilityHidden(true))
      }
      return view
    }
  }

#endif
