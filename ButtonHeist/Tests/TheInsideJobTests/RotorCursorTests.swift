#if canImport(UIKit)
import UIKit
import XCTest

@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import ThePlans
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
final class RotorCursorTests: XCTestCase {
    private var stash: TheStash!

    override func setUp() async throws {
        try await super.setUp()
        stash = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        stash = nil
        try await super.tearDown()
    }

    func testContinuationReacquiresReplacementObjectBySemanticIdentityAfterReparse() throws {
        let hostHeistId: HeistId = "semantic_rotor_host"
        let resultHeistId: HeistId = "semantic_rotor_result"
        var initialHost: UIView? = UIView()
        var initialResult: UIView? = UIView()
        weak let releasedInitialResult = initialResult
        initialHost?.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Items") { _ in
                initialResult.map {
                    UIAccessibilityCustomRotorItemResult(targetElement: $0, targetRange: nil)
                }
            },
        ]
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: try XCTUnwrap(initialHost),
            resultHeistId: resultHeistId,
            resultObject: try XCTUnwrap(initialResult)
        )

        do {
            let outcome = stash.performRotor(
                selection: .named("Items"),
                direction: .next,
                on: try rotorLiveTarget(hostHeistId: hostHeistId)
            )
            guard case .succeeded = outcome else {
                return XCTFail("Expected initial rotor result, got \(outcome)")
            }
        }
        XCTAssertEqual(stash.rotorCursor?.selectionHeistId, resultHeistId)

        initialHost = nil
        initialResult = nil
        let replacementHost = UIView()
        let replacementResult = UIView()
        var receivedContinuationObject: NSObject?
        replacementHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Items") { predicate in
                receivedContinuationObject = predicate.currentItem.targetElement as? NSObject
                return UIAccessibilityCustomRotorItemResult(
                    targetElement: replacementResult,
                    targetRange: nil
                )
            },
        ]
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: replacementHost,
            resultHeistId: resultHeistId,
            resultObject: replacementResult
        )

        XCTAssertNil(releasedInitialResult)
        let outcome = stash.performRotor(
            selection: .named("Items"),
            direction: .next,
            on: try rotorLiveTarget(hostHeistId: hostHeistId)
        )

        guard case .succeeded = outcome else {
            return XCTFail("Expected replacement rotor result, got \(outcome)")
        }
        XCTAssertTrue(receivedContinuationObject === replacementResult)
    }

    func testUnavailableSemanticSelectionDoesNotRestartSearch() throws {
        let hostHeistId: HeistId = "unavailable_rotor_host"
        let resultHeistId: HeistId = "unavailable_rotor_result"
        let host = UIView()
        let result = UIView()
        host.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Items") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: result, targetRange: nil)
            },
        ]
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: host,
            resultHeistId: resultHeistId,
            resultObject: result
        )
        try expectSuccessfulStep(hostHeistId: hostHeistId, rotorName: "Items")

        let replacementHost = UIView()
        var searchCount = 0
        replacementHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Items") { _ in
                searchCount += 1
                return nil
            },
        ]
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: replacementHost,
            resultHeistId: resultHeistId,
            resultObject: nil
        )

        let outcome = stash.performRotor(
            selection: .named("Items"),
            direction: .next,
            on: try rotorLiveTarget(hostHeistId: hostHeistId)
        )

        guard case .currentItemUnavailable(let unavailableHeistId) = outcome else {
            return XCTFail("Expected unavailable continuation, got \(outcome)")
        }
        XCTAssertEqual(unavailableHeistId, resultHeistId.rawValue)
        XCTAssertEqual(searchCount, 0)
        XCTAssertNil(stash.rotorCursor)
    }

    func testScreenGenerationReplacementInvalidatesContinuation() throws {
        let hostHeistId: HeistId = "generation_rotor_host"
        let resultHeistId: HeistId = "generation_rotor_result"
        let host = UIView()
        let result = UIView()
        var searchCount = 0
        host.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Items") { _ in
                searchCount += 1
                return UIAccessibilityCustomRotorItemResult(targetElement: result, targetRange: nil)
            },
        ]
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: host,
            resultHeistId: resultHeistId,
            resultObject: result
        )
        try expectSuccessfulStep(hostHeistId: hostHeistId, rotorName: "Items")

        stash.semanticObservationStream.requireScreenReplacement()
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: host,
            resultHeistId: resultHeistId,
            resultObject: result
        )
        let outcome = stash.performRotor(
            selection: .named("Items"),
            direction: .next,
            on: try rotorLiveTarget(hostHeistId: hostHeistId)
        )

        guard case .continuationInvalidated = outcome else {
            return XCTFail("Expected invalidated continuation, got \(outcome)")
        }
        XCTAssertEqual(searchCount, 1)
        XCTAssertNil(stash.rotorCursor)
    }

    func testContinuationReconstructsTextRangeFromValueReference() throws {
        let hostHeistId: HeistId = "text_rotor_host"
        let resultHeistId: HeistId = "text_rotor_result"
        let host = UIView()
        let textField = UITextField()
        textField.text = "abcdef"
        let initialRange = try XCTUnwrap(textRange(in: textField, startOffset: 1, endOffset: 4))
        var receivedOffsets: TextRangeReference?
        var invocation = 0
        host.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Words") { predicate in
                invocation += 1
                if let range = predicate.currentItem.targetRange {
                    receivedOffsets = TextRangeReference(
                        startOffset: textField.offset(from: textField.beginningOfDocument, to: range.start),
                        endOffset: textField.offset(from: textField.beginningOfDocument, to: range.end)
                    )
                }
                return UIAccessibilityCustomRotorItemResult(
                    targetElement: textField,
                    targetRange: initialRange
                )
            },
        ]
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: host,
            resultHeistId: resultHeistId,
            resultObject: textField
        )

        try expectSuccessfulStep(hostHeistId: hostHeistId, rotorName: "Words")
        try expectSuccessfulStep(hostHeistId: hostHeistId, rotorName: "Words")

        XCTAssertEqual(invocation, 2)
        XCTAssertEqual(receivedOffsets, TextRangeReference(startOffset: 1, endOffset: 4))
        XCTAssertEqual(stash.rotorCursor?.textRange, TextRangeReference(startOffset: 1, endOffset: 4))
    }

    func testResultRangeThatCannotBecomeAValueCursorFailsExplicitly() throws {
        let hostHeistId: HeistId = "invalid_text_rotor_host"
        let resultHeistId: HeistId = "invalid_text_rotor_result"
        let host = UIView()
        let result = UIView()
        let rangeOwner = UITextField()
        rangeOwner.text = "abcdef"
        let range = try XCTUnwrap(textRange(in: rangeOwner, startOffset: 1, endOffset: 4))
        host.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Words") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: result, targetRange: range)
            },
        ]
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: host,
            resultHeistId: resultHeistId,
            resultObject: result
        )

        let outcome = stash.performRotor(
            selection: .named("Words"),
            direction: .next,
            on: try rotorLiveTarget(hostHeistId: hostHeistId)
        )

        guard case .continuationTextRangeUnavailable = outcome else {
            return XCTFail("Expected unreconstructable range failure, got \(outcome)")
        }
        XCTAssertNil(stash.rotorCursor)
    }

    func testClearingCursorMakesNextStepStartFresh() throws {
        let hostHeistId: HeistId = "cleared_rotor_host"
        let resultHeistId: HeistId = "cleared_rotor_result"
        let host = UIView()
        let result = UIView()
        var receivedCurrentItems: [NSObject?] = []
        host.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Items") { predicate in
                receivedCurrentItems.append(predicate.currentItem.targetElement as? NSObject)
                return UIAccessibilityCustomRotorItemResult(targetElement: result, targetRange: nil)
            },
        ]
        installRotorScreen(
            hostHeistId: hostHeistId,
            hostObject: host,
            resultHeistId: resultHeistId,
            resultObject: result
        )
        try expectSuccessfulStep(hostHeistId: hostHeistId, rotorName: "Items")

        stash.clearRotorCursor()
        try expectSuccessfulStep(hostHeistId: hostHeistId, rotorName: "Items")

        XCTAssertEqual(receivedCurrentItems.count, 2)
        XCTAssertNil(receivedCurrentItems[0])
        XCTAssertNil(receivedCurrentItems[1])
    }

    private func installRotorScreen(
        hostHeistId: HeistId,
        hostObject: NSObject,
        resultHeistId: HeistId,
        resultObject: NSObject?
    ) {
        let rotorNames = hostObject.accessibilityCustomRotors?.map(\.name) ?? []
        let hostElement = AccessibilityElement.make(
            label: "Rotor host",
            identifier: hostHeistId.rawValue,
            shape: .frame(AccessibilityRect(x: 20, y: 20, width: 200, height: 44)),
            activationPoint: CGPoint(x: 120, y: 42),
            customRotors: rotorNames.map { .init(name: $0) }
        )
        let resultElement = AccessibilityElement.make(
            label: "Rotor result",
            identifier: resultHeistId.rawValue,
            shape: .frame(AccessibilityRect(x: 20, y: 80, width: 200, height: 44)),
            activationPoint: CGPoint(x: 120, y: 102)
        )
        stash.installScreenForTesting(.makeForTests([
            .init(hostElement, heistId: hostHeistId, object: hostObject),
            .init(resultElement, heistId: resultHeistId, object: resultObject),
        ]))
    }

    private func rotorLiveTarget(hostHeistId: HeistId) throws -> TheStash.LiveActionTarget {
        let treeElement = try XCTUnwrap(stash.interfaceElement(heistId: hostHeistId))
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: treeElement) else {
            throw RotorCursorTestError.liveTargetUnavailable
        }
        return liveTarget
    }

    private func expectSuccessfulStep(hostHeistId: HeistId, rotorName: String) throws {
        let outcome = stash.performRotor(
            selection: .named(rotorName),
            direction: .next,
            on: try rotorLiveTarget(hostHeistId: hostHeistId)
        )
        guard case .succeeded = outcome else {
            throw RotorCursorTestError.unexpectedOutcome(String(describing: outcome))
        }
    }

    private func textRange(
        in input: UITextInput,
        startOffset: Int,
        endOffset: Int
    ) -> UITextRange? {
        guard let start = input.position(from: input.beginningOfDocument, offset: startOffset),
              let end = input.position(from: input.beginningOfDocument, offset: endOffset) else {
            return nil
        }
        return input.textRange(from: start, to: end)
    }
}

private enum RotorCursorTestError: Error {
    case liveTargetUnavailable
    case unexpectedOutcome(String)
}
#endif
