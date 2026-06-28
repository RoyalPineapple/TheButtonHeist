#if canImport(UIKit)
import Testing
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import TheScore

@MainActor
@Suite("LiveCapture")
struct LiveCaptureTests {

    @Test func `rejects duplicate live HeistIds before indexing`() {
        let first = AccessibilityElement.make(label: "First", traits: .button)
        let second = AccessibilityElement.make(label: "Second", traits: .button)
        let snapshot = LiveCapture.Snapshot(
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
            heistIdsByPath: [
                TreePath([0]): "shared_button",
                TreePath([1]): "shared_button",
            ]
        )

        do {
            _ = try LiveCapture.LiveElementTable(
                validating: snapshot,
                dispatchReferences: .empty
            )
            Issue.record("Expected duplicate live HeistId validation to fail")
        } catch let error as LiveCapture.LiveElementTableValidationError {
            #expect(error == .duplicateHeistId(
                heistId: "shared_button",
                firstPath: TreePath([0]),
                duplicatePath: TreePath([1])
            ))
            #expect(
                error.description == """
                LiveElementIndex cannot index duplicate live HeistId "shared_button" \
                at paths [0] and [1]; live HeistIds must be unique before building lookup indexes.
                """
            )
        } catch {
            Issue.record("Expected LiveElementTableValidationError, got \(error)")
        }
    }

    @Test func `valid live captures keep lookup behavior`() {
        let save = AccessibilityElement.make(label: "Save", traits: .button)
        let cancel = AccessibilityElement.make(label: "Cancel", traits: .button)
        let saveObject = NSObject()
        let saveScrollView = UIScrollView()
        let capture = LiveCapture(
            hierarchy: [
                .element(save, traversalIndex: 10),
                .element(cancel, traversalIndex: 0),
            ],
            heistIdsByPath: [
                TreePath([0]): "save_button",
                TreePath([1]): "cancel_button",
            ],
            elementRefs: [
                "save_button": LiveCapture.ElementRef(
                    object: saveObject,
                    scrollView: saveScrollView
                ),
            ],
            firstResponderHeistId: "save_button"
        )

        #expect(capture.heistIds == ["cancel_button", "save_button"])
        #expect(capture.contains(heistId: "save_button"))
        #expect(capture.heistId(for: save) == "save_button")
        #expect(capture.heistId(for: cancel) == "cancel_button")
        #expect(capture.heistId(forPath: TreePath([0])) == "save_button")
        #expect(capture.element(for: "cancel_button") == cancel)
        #expect(capture.object(for: "save_button") === saveObject)
        #expect(capture.heistId(matching: saveObject) == "save_button")
        #expect(capture.scrollView(for: "save_button") === saveScrollView)
        #expect(capture.orderedElementEntries().map(\.heistId) == ["cancel_button", "save_button"])
        #expect(capture.firstResponderHeistId == "save_button")
    }
}

#endif
