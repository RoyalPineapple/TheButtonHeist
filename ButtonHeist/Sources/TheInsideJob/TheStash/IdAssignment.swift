#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - HeistId Assignment

extension TheStash {

    /// Assigns deterministic heistIds to accessibility elements.
    /// Pure value-in, value-out — no mutable state.
    enum IdAssignment {

    /// Assign deterministic `heistId` to each AccessibilityElement.
    /// Stable developer-provided identifiers take priority — they become the heistId directly.
    /// Identifiers containing UUIDs (SwiftUI runtime artifacts) are skipped in favor of synthesis.
    /// Synthesized IDs use `{trait}_{slug}` with label for the slug (value excluded for stability).
    /// Duplicates get `_1`, `_2` suffixes in traversal order — all instances, not just the second.
    /// Returns the heistId array, parallel to the input elements array.
    static func assign(_ elements: [AccessibilityElement]) -> [String] {
        // Phase 1: generate base IDs
        var heistIds = elements.map { element -> String in
            if let identifier = element.identifier, !identifier.isEmpty,
               isStableIdentifier(identifier) {
                return identifier
            }
            return synthesizeBaseId(element)
        }

        // Phase 2: disambiguate duplicates
        let counts = heistIds.reduce(into: [String: Int]()) { $0[$1, default: 0] += 1 }

        var seen: [String: Int] = [:]
        for index in heistIds.indices {
            let base = heistIds[index]
            if let count = counts[base], count > 1 {
                let suffix = seen[base, default: 0] + 1
                seen[base] = suffix
                heistIds[index] = "\(base)_\(suffix)"
            }
        }

        return heistIds
    }

    static func synthesizeBaseId(_ element: AccessibilityElement) -> String {
        let traitSuffix = AccessibilityPolicy.synthesisPriorityWithMasks
            .first { element.traits.contains($0.mask) }?.name
            ?? (element.label != nil ? HeistTrait.staticText.rawValue : "element")

        // Value is intentionally excluded — it changes on interaction (toggles,
        // sliders, checkboxes) and must not affect element identity.
        // Strip leading words that duplicate the trait suffix before slugifying:
        // "Switch Button Off" with suffix "switchButton" → slug of "Off" → "off"
        let labelForSlug = stripTraitSuffix(element.label, traitSuffix: traitSuffix)
            ?? element.label
        let slug = slugify(labelForSlug)
            ?? slugify(element.description)

        if let slug {
            return "\(slug)_\(traitSuffix)"
        }
        return traitSuffix
    }

    /// Strip leading words from text that duplicate the trait suffix used in the heistId.
    /// "Switch Button Off" with suffix "switchButton" → "Off"
    /// Returns nil if stripping would leave nothing (label IS the trait name).
    static func stripTraitSuffix(_ text: String?, traitSuffix: String) -> String? {
        guard let text else { return nil }
        let suffixWords = traitSuffix
            .replacing(/([a-z])([A-Z])/, with: { "\($0.output.1) \($0.output.2)" })
            .lowercased()
            .split(separator: " ")
        let textWords = text.split(separator: " ", omittingEmptySubsequences: true)
        guard textWords.count > suffixWords.count else { return nil }
        for (suffixWord, textWord) in zip(suffixWords, textWords) {
            guard textWord.lowercased() == suffixWord else { return nil }
        }
        let remainder = textWords.dropFirst(suffixWords.count).joined(separator: " ")
        return remainder.isEmpty ? nil : remainder
    }

    static func slugify(_ text: String?) -> String? {
        TheScore.slugify(text)
    }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
