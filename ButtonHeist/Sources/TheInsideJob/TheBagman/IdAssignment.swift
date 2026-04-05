#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

// MARK: - HeistId Assignment

extension TheBagman {

    /// Assigns deterministic heistIds to accessibility elements.
    /// Pure value-in, value-out — no mutable state.
    struct IdAssignment {

    /// Trait priority for heistId prefix — most descriptive wins.
    /// Precomputed bitmasks from AccessibilitySnapshotParser's knownTraits.
    private static let traitPriority: [(name: String, mask: UIAccessibilityTraits)] = [
        ("backButton", UIAccessibilityTraits.fromNames(["backButton"])),
        ("searchField", UIAccessibilityTraits.fromNames(["searchField"])),
        ("textEntry", UIAccessibilityTraits.fromNames(["textEntry"])),
        ("switchButton", UIAccessibilityTraits.fromNames(["switchButton"])),
        ("adjustable", .adjustable),
        ("button", .button),
        ("link", .link),
        ("image", .image),
        ("header", .header),
        ("tabBar", UIAccessibilityTraits.fromNames(["tabBar"])),
    ]

    /// Assign deterministic `heistId` to each AccessibilityElement.
    /// Developer-provided identifiers take priority — they become the heistId directly.
    /// Synthesized IDs use `{trait}_{slug}` with label for the slug (value excluded for stability).
    /// Duplicates get `_1`, `_2` suffixes in traversal order — all instances, not just the second.
    /// Returns the heistId array, parallel to the input elements array.
    func assign(_ elements: [AccessibilityElement]) -> [String] {
        // Phase 1: generate base IDs
        var heistIds = elements.map { element -> String in
            if let identifier = element.identifier, !identifier.isEmpty {
                return identifier
            }
            return synthesizeBaseId(element)
        }

        // Phase 2: disambiguate duplicates
        let counts = heistIds.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }

        var seen: [String: Int] = [:]
        for i in heistIds.indices {
            let base = heistIds[i]
            if let count = counts[base], count > 1 {
                let index = seen[base, default: 0] + 1
                seen[base] = index
                heistIds[i] = "\(base)_\(index)"
            }
        }

        return heistIds
    }

    func synthesizeBaseId(_ element: AccessibilityElement) -> String {
        let traitPrefix = Self.traitPriority.first { element.traits.contains($0.mask) }?.name
            ?? (element.label != nil ? HeistTrait.staticText.rawValue : "element")

        // Value is intentionally excluded — it changes on interaction (toggles,
        // sliders, checkboxes) and must not affect element identity.
        // Strip leading words that duplicate the trait prefix before slugifying:
        // "Switch Button Off" with prefix "switchButton" → slug of "Off" → "off"
        let labelForSlug = stripTraitPrefix(element.label, traitPrefix: traitPrefix)
            ?? element.label
        let slug = slugify(labelForSlug)
            ?? slugify(element.description)

        if let slug {
            return "\(traitPrefix)_\(slug)"
        }
        return traitPrefix
    }

    /// Strip leading words from text that duplicate the trait prefix.
    /// "Switch Button Off" with prefix "switchButton" → "Off"
    /// Returns nil if stripping would leave nothing (label IS the trait name).
    func stripTraitPrefix(_ text: String?, traitPrefix: String) -> String? {
        guard let text else { return nil }
        let prefixWords = traitPrefix
            .replacing(/([a-z])([A-Z])/, with: { "\($0.output.1) \($0.output.2)" })
            .lowercased()
            .split(separator: " ")
        let textWords = text.split(separator: " ", omittingEmptySubsequences: true)
        guard textWords.count > prefixWords.count else { return nil }
        for (prefixWord, textWord) in zip(prefixWords, textWords) {
            guard textWord.lowercased() == prefixWord else { return nil }
        }
        let remainder = textWords.dropFirst(prefixWords.count).joined(separator: " ")
        return remainder.isEmpty ? nil : remainder
    }

    func slugify(_ text: String?) -> String? {
        TheScore.slugify(text)
    }
    }
} // extension TheBagman

#endif // DEBUG
#endif // canImport(UIKit)
