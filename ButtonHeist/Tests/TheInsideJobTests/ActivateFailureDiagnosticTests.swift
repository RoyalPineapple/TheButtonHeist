#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
final class ActivateFailureDiagnosticTests: XCTestCase {

    // MARK: - Helpers

    private let screenBounds = CGRect(x: 0, y: 0, width: 393, height: 852)

    private func makeElement(
        frame: CGRect = CGRect(x: 12, y: 400, width: 80, height: 40),
        activationPoint: CGPoint = CGPoint(x: 52, y: 420),
        traits: UIAccessibilityTraits = .button
    ) -> AccessibilityElement {
        .make(
            description: "",
            label: "Charge $16.99",
            traits: traits,
            shape: .frame(frame),
            activationPoint: activationPoint,
            usesDefaultActivationPoint: false,
            respondsToUserInteraction: false
        )
    }

    private func makeReceiver(
        receiverClass: String = "UIButton",
        receiverAxLabel: String? = nil,
        receiverAxIdentifier: String? = nil,
        interactionDisabledInChain: Bool = false,
        hiddenInChain: Bool = false,
        windowLevel: CGFloat = 0,
        isSwiftUIGestureContainer: Bool = false
    ) -> TheSafecracker.TapReceiverDiagnostic {
        TheSafecracker.TapReceiverDiagnostic(
            receiverClass: receiverClass,
            receiverAxLabel: receiverAxLabel,
            receiverAxIdentifier: receiverAxIdentifier,
            interactionDisabledInChain: interactionDisabledInChain,
            hiddenInChain: hiddenInChain,
            windowLevel: windowLevel,
            isSwiftUIGestureContainer: isSwiftUIGestureContainer
        )
    }

    // MARK: - Outcome Reporting

    func testRefusedOutcomeIncludesAccessibilityActivateLine() {
        let message = ActivateFailureDiagnostic.build(
            element: makeElement(),
            traitNames: ["button"],
            activateOutcome: .refused,
            tapAttempted: false,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertTrue(message.contains("accessibilityActivate: returned false"))
        XCTAssertFalse(message.contains("liveObject: deallocated"))
    }

    func testDeallocatedOutcomeIncludesLiveObjectLine() {
        let message = ActivateFailureDiagnostic.build(
            element: makeElement(),
            traitNames: ["button"],
            activateOutcome: .objectDeallocated,
            tapAttempted: false,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertTrue(message.contains("liveObject: deallocated"))
        XCTAssertFalse(message.contains("accessibilityActivate"))
    }

    // MARK: - Receiver Line

    func testTapReceiverLineIncludesClassAndLabel() {
        let receiver = makeReceiver(receiverClass: "UIButton", receiverAxLabel: "Charge $16.99")
        let message = ActivateFailureDiagnostic.build(
            element: makeElement(),
            traitNames: ["button"],
            activateOutcome: .refused,
            tapAttempted: true,
            tapReceiver: receiver,
            screenBounds: screenBounds
        )
        XCTAssertTrue(message.contains("syntheticTap.receiver: UIButton \"Charge $16.99\""))
    }

    func testTapReceiverFallsBackToIdentifierWhenLabelMissing() {
        let receiver = makeReceiver(receiverClass: "UIView", receiverAxLabel: nil, receiverAxIdentifier: "checkout-row")
        let message = ActivateFailureDiagnostic.build(
            element: makeElement(),
            traitNames: ["button"],
            activateOutcome: .refused,
            tapAttempted: true,
            tapReceiver: receiver,
            screenBounds: screenBounds
        )
        XCTAssertTrue(message.contains("syntheticTap.receiver: UIView (id: checkout-row)"))
    }

    func testInteractionDisabledFlagOnlyAppearsWhenTrue() {
        let enabledReceiver = makeReceiver(interactionDisabledInChain: false)
        let disabledReceiver = makeReceiver(interactionDisabledInChain: true)

        let enabledMsg = ActivateFailureDiagnostic.build(
            element: makeElement(), traitNames: ["button"],
            activateOutcome: .refused, tapAttempted: true,
            tapReceiver: enabledReceiver, screenBounds: screenBounds
        )
        let disabledMsg = ActivateFailureDiagnostic.build(
            element: makeElement(), traitNames: ["button"],
            activateOutcome: .refused, tapAttempted: true,
            tapReceiver: disabledReceiver, screenBounds: screenBounds
        )
        XCTAssertFalse(enabledMsg.contains("userInteractionEnabled: false"))
        XCTAssertTrue(disabledMsg.contains("syntheticTap.userInteractionEnabled: false"))
    }

    func testHiddenFlagOnlyAppearsWhenTrue() {
        let visibleReceiver = makeReceiver(hiddenInChain: false)
        let hiddenReceiver = makeReceiver(hiddenInChain: true)

        let visibleMsg = ActivateFailureDiagnostic.build(
            element: makeElement(), traitNames: ["button"],
            activateOutcome: .refused, tapAttempted: true,
            tapReceiver: visibleReceiver, screenBounds: screenBounds
        )
        let hiddenMsg = ActivateFailureDiagnostic.build(
            element: makeElement(), traitNames: ["button"],
            activateOutcome: .refused, tapAttempted: true,
            tapReceiver: hiddenReceiver, screenBounds: screenBounds
        )
        XCTAssertFalse(visibleMsg.contains("syntheticTap.hidden"))
        XCTAssertTrue(hiddenMsg.contains("syntheticTap.hidden: true"))
    }

    func testSwiftUIGestureContainerNoteAppearsOnlyForSwiftUI() {
        let uiKitReceiver = makeReceiver(isSwiftUIGestureContainer: false)
        let swiftUIReceiver = makeReceiver(receiverClass: "UIKitGestureContainer", isSwiftUIGestureContainer: true)

        let uiKitMsg = ActivateFailureDiagnostic.build(
            element: makeElement(), traitNames: ["button"],
            activateOutcome: .refused, tapAttempted: true,
            tapReceiver: uiKitReceiver, screenBounds: screenBounds
        )
        let swiftUIMsg = ActivateFailureDiagnostic.build(
            element: makeElement(), traitNames: ["button"],
            activateOutcome: .refused, tapAttempted: true,
            tapReceiver: swiftUIReceiver, screenBounds: screenBounds
        )
        XCTAssertFalse(uiKitMsg.contains("SwiftUI gesture container"))
        XCTAssertTrue(swiftUIMsg.contains("SwiftUI gesture container"))
    }

    func testNoTargetableWindowLineWhenReceiverIsNil() {
        let message = ActivateFailureDiagnostic.build(
            element: makeElement(),
            traitNames: ["button"],
            activateOutcome: .refused,
            tapAttempted: true,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertTrue(message.contains("syntheticTap: no targetable window at activation point"))
    }

    func testNoSyntheticTapLineWhenTapNotAttempted() {
        let message = ActivateFailureDiagnostic.build(
            element: makeElement(),
            traitNames: ["button"],
            activateOutcome: .refused,
            tapAttempted: false,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertFalse(message.contains("syntheticTap"))
    }

    // MARK: - On-Screen Reporting

    func testOnScreenLineOmittedWhenElementOnScreen() {
        let onScreenElement = makeElement(frame: CGRect(x: 12, y: 400, width: 80, height: 40))
        let message = ActivateFailureDiagnostic.build(
            element: onScreenElement,
            traitNames: ["button"],
            activateOutcome: .refused,
            tapAttempted: false,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertFalse(message.contains("onScreen:"))
    }

    func testOnScreenFalseLineWhenElementOffScreen() {
        let offScreenElement = makeElement(frame: CGRect(x: 12, y: 1000, width: 80, height: 40))
        let message = ActivateFailureDiagnostic.build(
            element: offScreenElement,
            traitNames: ["button"],
            activateOutcome: .refused,
            tapAttempted: false,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertTrue(message.contains("onScreen: false"))
        XCTAssertTrue(message.contains("screen: 393x852"))
    }

    // MARK: - Frame and Activation Point

    func testFrameAndActivationPointAlwaysIncluded() {
        let element = makeElement(
            frame: CGRect(x: 12, y: 400, width: 80, height: 40),
            activationPoint: CGPoint(x: 52, y: 420)
        )
        let message = ActivateFailureDiagnostic.build(
            element: element,
            traitNames: [],
            activateOutcome: .refused,
            tapAttempted: false,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertTrue(message.contains("frame: 12,400,80,40"))
        XCTAssertTrue(message.contains("activationPoint: 52,420"))
    }

    func testTraitsLineOmittedWhenEmpty() {
        let message = ActivateFailureDiagnostic.build(
            element: makeElement(traits: []),
            traitNames: [],
            activateOutcome: .refused,
            tapAttempted: false,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertFalse(message.contains("traits:"))
    }

    func testTraitsLineJoinedWithCommas() {
        let message = ActivateFailureDiagnostic.build(
            element: makeElement(),
            traitNames: ["button", "selected"],
            activateOutcome: .refused,
            tapAttempted: false,
            tapReceiver: nil,
            screenBounds: screenBounds
        )
        XCTAssertTrue(message.contains("traits: button,selected"))
    }
}

// MARK: - ActivateOutcome (TheStash)

@MainActor
final class ActivateOutcomeBehaviorTests: XCTestCase {

    func testActivateReturnsObjectDeallocatedWhenNoLiveObject() {
        // ScreenElement with weak object that's already nil — equivalent to cell-reuse.
        let element = AccessibilityElement(
            description: "", label: "x", value: nil, traits: [],
            identifier: nil, hint: nil, userInputLabels: nil,
            shape: .frame(.zero), activationPoint: .zero,
            usesDefaultActivationPoint: true, customActions: [],
            customContent: [], customRotors: [], accessibilityLanguage: nil,
            respondsToUserInteraction: false
        )
        let screenElement = TheStash.ScreenElement(
            heistId: "x", contentSpaceOrigin: nil, element: element,
            object: nil, scrollView: nil
        )
        let stash = TheStash(tripwire: TheTripwire())
        XCTAssertEqual(stash.activate(screenElement), .objectDeallocated)
    }
}

#endif
