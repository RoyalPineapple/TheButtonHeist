#if canImport(UIKit)
#if DEBUG
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import ThePlans
@testable import TheScore

/// Test-only `Screen` factory.
///
/// Replaces the per-file `installScreen` / `seedScreen` /
/// `installScreenWithOffViewportEntry` helpers that all rebuilt the same
/// `Screen` value from a list of `(AccessibilityElement, heistId)` pairs.
///
/// Known-only entries live in `Screen.semantic.elements` (so target resolution
/// sees them) but are not present in the live hierarchy — modeling an element
/// retained from a previous exploration that has since scrolled out of view.
extension Screen {

    /// An entry that is registered but is not in the live hierarchy. Used to
    /// simulate known semantic state without a real scrollable container.
    struct OffViewportEntry {
        let element: AccessibilityElement
        let heistId: HeistId
        let scrollContentLocation: ScrollContentLocation?

        init(
            _ element: AccessibilityElement,
            heistId: HeistId,
            contentSpaceOrigin: CGPoint? = nil,
            scrollContainer: ContainerName = "test_scroll"
        ) {
            self.element = element
            self.heistId = heistId
            self.scrollContentLocation = contentSpaceOrigin.map {
                ScrollContentLocation(origin: $0, scrollContainer: scrollContainer)
            }
        }
    }

    /// Build a `Screen` from a flat list of `(element, heistId)` pairs. The
    /// hierarchy is constructed from the live pairs in order; known-only
    /// entries are added to `elements` but not to `hierarchy`.
    static func makeForTests(
        elements liveElements: [(element: AccessibilityElement, heistId: HeistId)] = [],
        objects: [HeistId: NSObject?] = [:],
        offViewport: [OffViewportEntry] = [],
        firstResponderHeistId: HeistId? = nil
    ) -> Screen {
        var screenElements: [HeistId: ScreenElement] = [:]
        var hierarchy: [AccessibilityHierarchy] = []
        var heistIdByElement: [AccessibilityElement: HeistId] = [:]
        var elementRefs: [HeistId: ElementRef] = [:]
        for (index, pair) in liveElements.enumerated() {
            screenElements[pair.heistId] = ScreenElement(
                heistId: pair.heistId,
                contentSpaceOrigin: nil,
                element: pair.element
            )
            elementRefs[pair.heistId] = ElementRef(
                object: objects[pair.heistId] ?? nil,
                scrollView: nil
            )
            hierarchy.append(.element(pair.element, traversalIndex: index))
            heistIdByElement[pair.element] = pair.heistId
        }
        for entry in offViewport {
            screenElements[entry.heistId] = ScreenElement(
                heistId: entry.heistId,
                scrollContentLocation: entry.scrollContentLocation,
                element: entry.element
            )
        }
        return Screen(
            elements: screenElements,
            hierarchy: hierarchy,
            containerNames: [:],
            heistIdByElement: heistIdByElement,
            elementRefs: elementRefs,
            firstResponderHeistId: firstResponderHeistId,
            scrollableContainerViews: [:]
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
