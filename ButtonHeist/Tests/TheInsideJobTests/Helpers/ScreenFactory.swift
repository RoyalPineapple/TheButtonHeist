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

    struct TestEntry {
        let element: AccessibilityElement
        let heistId: HeistId
        let object: NSObject?

        init(
            _ element: AccessibilityElement,
            heistId: HeistId,
            object: NSObject? = nil
        ) {
            self.element = element
            self.heistId = heistId
            self.object = object
        }

        init(
            label: String = "Element",
            heistId: HeistId? = nil,
            value: String? = nil,
            identifier: String? = nil,
            traits: UIAccessibilityTraits = .none,
            frame: CGRect = CGRect(x: 0, y: 0, width: 100, height: 44),
            object: NSObject? = nil
        ) {
            self.init(
                AccessibilityElement.make(
                    label: label,
                    value: value,
                    identifier: identifier,
                    traits: traits,
                    frame: frame
                ),
                heistId: heistId ?? HeistId(rawValue: label),
                object: object
            )
        }
    }

    /// An entry that is registered but is not in the live hierarchy. Used to
    /// simulate known semantic state without a real scrollable container.
    struct OffViewportEntry {
        let element: AccessibilityElement
        let heistId: HeistId
        let scrollMembership: ScrollMembership?

        init(
            _ element: AccessibilityElement,
            heistId: HeistId,
            scrollContainerPath: TreePath? = nil,
            scrollIndex: Int? = nil
        ) {
            self.element = element
            self.heistId = heistId
            self.scrollMembership = scrollContainerPath.map {
                ScrollMembership(containerPath: $0, index: scrollIndex)
            }
        }
    }

    /// Build a `Screen` from a flat list of `(element, heistId)` pairs. The
    /// hierarchy is constructed from the live pairs in order; known-only
    /// entries are added to `elements` but not to `hierarchy`.
    static func makeForTests(
        _ entries: [TestEntry],
        offViewport: [OffViewportEntry] = [],
        firstResponderHeistId: HeistId? = nil
    ) -> Screen {
        makeForTests(
            elements: entries.map { (element: $0.element, heistId: $0.heistId) },
            objects: Dictionary(uniqueKeysWithValues: entries.map { ($0.heistId, $0.object) }),
            offViewport: offViewport,
            firstResponderHeistId: firstResponderHeistId
        )
    }

    static func makeForTests(
        elements liveElements: [(element: AccessibilityElement, heistId: HeistId)] = [],
        objects: [HeistId: NSObject?] = [:],
        offViewport: [OffViewportEntry] = [],
        firstResponderHeistId: HeistId? = nil
    ) -> Screen {
        var screenElements: [HeistId: ScreenElement] = [:]
        var hierarchy: [AccessibilityHierarchy] = []
        var heistIdsByPath: [TreePath: HeistId] = [:]
        var elementRefs: [HeistId: ElementRef] = [:]
        for (index, pair) in liveElements.enumerated() {
            screenElements[pair.heistId] = ScreenElement(
                heistId: pair.heistId,
                scrollMembership: nil,
                element: pair.element
            )
            elementRefs[pair.heistId] = ElementRef(
                object: objects[pair.heistId] ?? nil,
                scrollView: nil
            )
            hierarchy.append(.element(pair.element, traversalIndex: index))
            heistIdsByPath[TreePath([index])] = pair.heistId
        }
        for entry in offViewport {
            screenElements[entry.heistId] = ScreenElement(
                heistId: entry.heistId,
                scrollMembership: entry.scrollMembership,
                element: entry.element
            )
        }
        return Screen(
            elements: screenElements,
            hierarchy: hierarchy,
            heistIdsByPath: heistIdsByPath,
            elementRefs: elementRefs,
            firstResponderHeistId: firstResponderHeistId,
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
