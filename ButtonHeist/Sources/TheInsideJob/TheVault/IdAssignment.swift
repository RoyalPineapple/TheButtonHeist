#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

/// Internal element identity. Lives only inside TheInsideJob — it is the
/// InterfaceObservation-keying / resolution / diff-pairing handle and never crosses the wire,
/// is never shown to the agent, and never appears in deliverables. Wire-facing
/// element references use `AccessibilityTarget` (predicate + ordinal) instead.
struct HeistId: RawRepresentable, Hashable, Sendable, Codable, Comparable, CustomStringConvertible, ExpressibleByStringLiteral {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    init(stringLiteral value: String) {
        rawValue = value
    }

    var description: String {
        rawValue
    }

    static func < (lhs: HeistId, rhs: HeistId) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        rawValue = try container.decode(String.self)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    var predicateSelectionElementId: PredicateSelectionElementId {
        PredicateSelectionElementId(rawValue: rawValue)
    }

    var traceElementIdentity: TraceElementIdentity {
        let digest = SHA256.hash(data: Data(rawValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        return TraceElementIdentity("heist-id:sha256:\(digest)")
    }
}

// MARK: - HeistId Assignment

/// Assigns deterministic heistIds to accessibility elements.
/// Pure value-in, value-out — no mutable state.
enum HeistIdAssignment {

    struct Input {
        let element: AccessibilityElement
        let duplicateOrder: DuplicateOrder?

        init(
            element: AccessibilityElement,
            duplicateOrder: DuplicateOrder? = nil
        ) {
            self.element = element
            self.duplicateOrder = duplicateOrder
        }
    }

    struct DuplicateOrder: Comparable {
        private let scrollContainerPath: TreePath
        private let scrollIndex: Int

        static func scrollMembership(containerPath: TreePath, index: Int) -> DuplicateOrder {
            DuplicateOrder(scrollContainerPath: containerPath, scrollIndex: index)
        }

        static func < (lhs: DuplicateOrder, rhs: DuplicateOrder) -> Bool {
            if lhs.scrollContainerPath != rhs.scrollContainerPath {
                return lhs.scrollContainerPath < rhs.scrollContainerPath
            }
            return lhs.scrollIndex < rhs.scrollIndex
        }
    }

    /// Assign deterministic `heistId` to each AccessibilityElement.
    /// Stable developer-provided identifiers take priority — they become the heistId directly.
    /// Identifiers containing UUIDs (SwiftUI runtime artifacts) are skipped in favor of synthesis.
    /// Synthesized IDs use `{trait}_{slug}` with label for the slug (value excluded for stability).
    /// Duplicates get `_1`, `_2` suffixes in input order — all instances, not just the second.
    /// Returns the heistId array, parallel to the input elements array.
    static func assign(_ elements: [AccessibilityElement]) -> [HeistId] {
        assign(elements.map { Input(element: $0) })
    }

    /// Assign deterministic `heistId` values while allowing the caller to provide
    /// stable order evidence for duplicate elements. Scroll-backed
    /// observations use scroll membership so a row keeps the same suffix when it
    /// moves between offscreen inventory and the visible parser hierarchy.
    static func assign(_ inputs: [Input]) -> [HeistId] {
        let baseIds = inputs.map { baseId(for: $0.element) }
        var heistIds = baseIds
        let counts = baseIds.reduce(into: [HeistId: Int]()) { $0[$1, default: 0] += 1 }
        var usedIds = Set(counts.compactMap { id, count in count == 1 ? id : nil })

        let duplicateIndexGroups = Dictionary(grouping: baseIds.indices, by: { baseIds[$0] })
            .values
            .filter { $0.count > 1 }
            .sorted { left, right in
                guard let leftIndex = left.min(),
                      let rightIndex = right.min()
                else { return false }
                return leftIndex < rightIndex
            }

        for indices in duplicateIndexGroups {
            var suffix = 1
            for index in orderedDuplicates(indices, inputs: inputs) {
                var id = HeistId(rawValue: "\(baseIds[index].rawValue)_\(suffix)")
                while usedIds.contains(id) {
                    suffix += 1
                    id = HeistId(rawValue: "\(baseIds[index].rawValue)_\(suffix)")
                }
                usedIds.insert(id)
                heistIds[index] = id
                suffix += 1
            }
        }

        return heistIds
    }

    private static func orderedDuplicates(
        _ indices: [Int],
        inputs: [Input]
    ) -> [Int] {
        guard indices.allSatisfy({ inputs[$0].duplicateOrder != nil }) else {
            return indices.sorted()
        }
        return indices.sorted { lhs, rhs in
            guard let left = inputs[lhs].duplicateOrder,
                  let right = inputs[rhs].duplicateOrder
            else {
                return lhs < rhs
            }
            return left == right ? lhs < rhs : left < right
        }
    }

    private static func baseId(for element: AccessibilityElement) -> HeistId {
        if let identifier = element.identifier, !identifier.isEmpty,
           isStableIdentifier(identifier) {
            return HeistId(rawValue: identifier)
        }
        return HeistId(rawValue: synthesizeBaseId(element))
    }

    static func synthesizeBaseId(_ element: AccessibilityElement) -> String {
        let traitSuffix = AccessibilityPolicy.synthesisPriorityMaskProjections
            .first { element.traits.contains($0.mask) }?
            .trait
            .rawValue
            ?? (element.label != nil ? HeistTrait.staticText.rawValue : "element")

        // Value is intentionally excluded — it changes on interaction (toggles,
        // sliders, checkboxes) and must not affect element identity.
        // Strip leading words that duplicate the trait suffix before slugifying:
        // "Switch Button Off" with suffix "switchButton" → slug of "Off" → "off"
        let labelForSlug = stripTraitSuffix(element.label, traitSuffix: traitSuffix)
            ?? element.label
        let slug = TheScore.slugify(labelForSlug)
            ?? TheScore.slugify(element.description)

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
            guard textWord.lowercased() == suffixWord else {
                return nil
            }
        }
        let remainder = textWords.dropFirst(suffixWords.count).joined(separator: " ")
        return remainder.isEmpty ? nil : remainder
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
