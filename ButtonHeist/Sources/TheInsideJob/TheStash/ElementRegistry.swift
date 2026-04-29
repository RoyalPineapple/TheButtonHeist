#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

extension TheStash {

    /// The element registry — tracks all known elements, their viewport visibility,
    /// and reverse lookup indices.
    ///
    /// Invariants enforced by API:
    /// - viewportIds is always a subset of elements.keys
    /// - reverseIndex is rebuilt in sync with viewportIds
    struct ElementRegistry {

    /// Persistent element registry keyed by heistId. Lives for the screen's duration.
    var elements: [String: ScreenElement] = [:]

    /// HeistIds currently visible in the device viewport — rebuilt each refresh cycle.
    var viewportIds: Set<String> = []

    /// HeistId of the element whose live object is currently first responder, if any.
    /// Rebuilt each refresh cycle — no view hierarchy walk needed.
    var firstResponderHeistId: String?

    /// Reverse index: AccessibilityElement → heistId for the current visible set.
    var reverseIndex: [AccessibilityElement: String] = [:]

    // MARK: - Mutation

    /// Upsert elements into the registry from a parse result.
    mutating func apply(
        parsedElements: [AccessibilityElement],
        heistIds: [String],
        contexts: [AccessibilityElement: ElementContext]
    ) {
        var resolvedPairs: [(AccessibilityElement, String)] = []

        for (parsedElement, baseHeistId) in zip(parsedElements, heistIds) {
            let context = contexts[parsedElement]
            let heistId = resolveHeistId(baseHeistId, contentSpaceOrigin: context?.contentSpaceOrigin)
            resolvedPairs.append((parsedElement, heistId))
            if var existing = elements[heistId] {
                existing.element = parsedElement
                existing.object = context?.object
                existing.scrollView = context?.scrollView
                existing.contentSpaceOrigin = context?.contentSpaceOrigin ?? existing.contentSpaceOrigin
                elements[heistId] = existing
            } else {
                elements[heistId] = ScreenElement(
                    heistId: heistId,
                    contentSpaceOrigin: context?.contentSpaceOrigin,
                    element: parsedElement,
                    object: context?.object,
                    scrollView: context?.scrollView
                )
            }
        }

        reverseIndex = Dictionary(
            resolvedPairs.map { ($0.0, $0.1) },
            uniquingKeysWith: { _, latest in latest }
        )

        viewportIds = Set(resolvedPairs.map(\.1))
    }

    private func resolveHeistId(_ baseHeistId: String, contentSpaceOrigin: CGPoint?) -> String {
        guard let contentSpaceOrigin,
              let existing = elements[baseHeistId],
              let existingOrigin = existing.contentSpaceOrigin,
              !Self.sameOrigin(existingOrigin, contentSpaceOrigin) else {
            return baseHeistId
        }
        return "\(baseHeistId)_at_\(Int(contentSpaceOrigin.x.rounded()))_\(Int(contentSpaceOrigin.y.rounded()))"
    }

    private static func sameOrigin(_ lhs: CGPoint, _ rhs: CGPoint) -> Bool {
        abs(lhs.x - rhs.x) < 0.5 && abs(lhs.y - rhs.y) < 0.5
    }

    /// Clear everything — suspend or full reset.
    mutating func clear() {
        elements.removeAll()
        viewportIds.removeAll()
        reverseIndex.removeAll()
        firstResponderHeistId = nil
    }

    /// Clear screen-level state on screen change.
    mutating func clearScreen() {
        elements.removeAll()
        reverseIndex.removeAll()
    }

    /// Prune elements not in the given set (post-explore cleanup).
    mutating func prune(keeping seen: Set<String>) {
        elements = elements.filter { seen.contains($0.key) }
    }
    }

    /// Per-element context gathered during the hierarchy walk.
    struct ElementContext {
        let contentSpaceOrigin: CGPoint?
        weak var scrollView: UIScrollView?
        weak var object: NSObject?
    }
} // extension TheStash

#endif // DEBUG
#endif // canImport(UIKit)
