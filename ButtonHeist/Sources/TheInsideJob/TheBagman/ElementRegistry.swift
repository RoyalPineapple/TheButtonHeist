#if canImport(UIKit)
#if DEBUG
import UIKit
import AccessibilitySnapshotParser
import TheScore

extension TheBagman {

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

    /// Reverse index: AccessibilityElement → heistId for the current visible set.
    var reverseIndex: [AccessibilityElement: String] = [:]

    // MARK: - Mutation

    /// Upsert elements into the registry from a parse result.
    mutating func apply(
        parsedElements: [AccessibilityElement],
        heistIds: [String],
        contexts: [AccessibilityElement: ElementContext]
    ) {
        reverseIndex = Dictionary(
            zip(parsedElements, heistIds).map { ($0, $1) },
            uniquingKeysWith: { _, latest in latest }
        )

        for (parsedElement, heistId) in zip(parsedElements, heistIds) {
            let context = contexts[parsedElement]
            if var existing = elements[heistId] {
                existing.element = parsedElement
                existing.object = context?.object
                existing.scrollView = context?.scrollView
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

        viewportIds = Set(heistIds)
    }

    /// Clear everything — suspend or full reset.
    mutating func clear() {
        elements.removeAll()
        viewportIds.removeAll()
        reverseIndex.removeAll()
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
} // extension TheBagman

#endif // DEBUG
#endif // canImport(UIKit)
