#if canImport(UIKit)
#if DEBUG
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

/// Test-only `Screen` factory.
///
/// Replaces the per-file `installScreen` / `seedScreen` /
/// `installScreenWithOffViewportEntry` helpers that all rebuilt the same
/// `Screen` value from a list of `(AccessibilityElement, heistId)` pairs.
///
/// Known-only entries live in `Screen.elements` (so target resolution sees
/// them) but are not present in the live hierarchy — modeling an element
/// retained from a previous exploration that has since scrolled out of view.
extension Screen {

    /// An entry that is registered but is not in the live hierarchy. Used to
    /// simulate known semantic state without a real scrollable container.
    struct OffViewportEntry {
        let element: AccessibilityElement
        let heistId: String
        let contentSpaceOrigin: CGPoint?

        init(_ element: AccessibilityElement, heistId: String, contentSpaceOrigin: CGPoint? = nil) {
            self.element = element
            self.heistId = heistId
            self.contentSpaceOrigin = contentSpaceOrigin
        }
    }

    /// Build a `Screen` from a flat list of `(element, heistId)` pairs. The
    /// hierarchy is constructed from the live pairs in order; known-only
    /// entries are added to `elements` but not to `hierarchy`.
    static func makeForTests(
        elements liveElements: [(element: AccessibilityElement, heistId: String)] = [],
        objects: [String: NSObject?] = [:],
        offViewport: [OffViewportEntry] = [],
        firstResponderHeistId: String? = nil
    ) -> Screen {
        var screenElements: [String: ScreenElement] = [:]
        var hierarchy: [AccessibilityHierarchy] = []
        var heistIdByElement: [AccessibilityElement: String] = [:]
        for (index, pair) in liveElements.enumerated() {
            screenElements[pair.heistId] = ScreenElement(
                heistId: pair.heistId,
                contentSpaceOrigin: nil,
                element: pair.element,
                object: objects[pair.heistId] ?? nil,
                scrollView: nil
            )
            hierarchy.append(.element(pair.element, traversalIndex: index))
            heistIdByElement[pair.element] = pair.heistId
        }
        for entry in offViewport {
            screenElements[entry.heistId] = ScreenElement(
                heistId: entry.heistId,
                contentSpaceOrigin: entry.contentSpaceOrigin,
                element: entry.element,
                object: nil,
                scrollView: nil
            )
        }
        return Screen(
            elements: screenElements,
            hierarchy: hierarchy,
            containerStableIds: [:],
            heistIdByElement: heistIdByElement,
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViews: [:]
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
