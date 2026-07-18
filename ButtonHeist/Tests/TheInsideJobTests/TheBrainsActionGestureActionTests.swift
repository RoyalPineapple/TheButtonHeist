#if canImport(UIKit)
import ButtonHeistSupport
import ButtonHeistTestSupport
import XCTest
@testable import AccessibilitySnapshotParser
@_spi(ButtonHeistInternals) @testable import ThePlans
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsActionTests {

    func testExecuteTapOutsideWindowReportsGestureDispatchState() async throws {
        let result = await brains.actions.executeTap(
            try TapTarget(selection: .coordinate(ScreenPoint(x: -10_000, y: -10_000)))
                .resolve(in: .empty)
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .syntheticTap)
        XCTAssertDiagnostic(result.message, contains: [
            "syntheticTap failed",
            "point must be inside screen bounds",
            "observed (-10000, -10000)",
        ])
    }

    func testAccessibilityTargetedPointActionFailsWhenElementRemainsOffViewport() async throws {
        let stalePoint = CGPoint(x: 333, y: 777)
        let element = AccessibilityElement.make(
            label: "Below Fold",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 300, y: 750, width: 66, height: 54))),
            activationPoint: stalePoint
        )
        installScreen(offViewport: [.init(element, heistId: "below_fold_button")])

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            selection: .element(try AccessibilityTarget.label("Below Fold").resolve(in: .empty)),
            method: .syntheticTap,
            prepare: { $0 },
            complete: { point in
                dispatchedPoint = point
                return true
            }
        )

        XCTAssertFalse(result.success)
        XCTAssertNil(dispatchedPoint, "Off-viewport targets must not dispatch their stored activation point")
    }

    func testAccessibilityTargetedPointActionUsesAccessibilityCaptureActivationPoint() async throws {
        let capturePoint = CGPoint(x: 10, y: 20)
        let objectPoint = CGPoint(x: 123, y: 456)
        let heistId: HeistId = "live_button"
        let element = AccessibilityElement.make(
            label: "Live",
            traits: .button,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: 0, width: 40, height: 40))),
            activationPoint: capturePoint,
            usesDefaultActivationPoint: false
        )
        let liveObject = ActionGeometryView(activationPoint: objectPoint)
        liveObject.accessibilityFrame = CGRect(x: 100, y: 430, width: 46, height: 52)
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            selection: .element(try AccessibilityTarget.label("Live").resolve(in: .empty)),
            method: .syntheticTap,
            prepare: { $0 },
            complete: { point in
                dispatchedPoint = point
                return true
            }
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, capturePoint)
        XCTAssertNotEqual(dispatchedPoint, objectPoint)
    }

    func testElementUnitPointActionUsesElementFrameOverride() async throws {
        let frame = CGRect(x: 100, y: 200, width: 80, height: 40)
        let activationPoint = CGPoint(x: 140, y: 220)
        let element = AccessibilityElement.make(
            label: "Live",
            traits: .button,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: activationPoint
        )
        let liveObject = ActionGeometryView(activationPoint: activationPoint)
        liveObject.accessibilityFrame = frame
        installScreen(elements: [(element, "live_button")], objects: ["live_button": liveObject])

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            selection: .elementUnitPoint(
                try AccessibilityTarget.label("Live").resolve(in: .empty),
                UnitPoint(x: 0.25, y: 0.75)
            ),
            method: .syntheticTap,
            prepare: { $0 },
            complete: { point in
                dispatchedPoint = point
                return true
            }
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, CGPoint(x: 120, y: 230))
        XCTAssertNotEqual(dispatchedPoint, activationPoint)
    }

    func testRawCoordinatePointActionDispatchesUnchanged() async {
        let rawPoint = CGPoint(x: 222, y: 333)

        var dispatchedPoint: CGPoint?
        let result = await brains.actions.performPointAction(
            selection: .coordinate(ScreenPoint(x: 222, y: 333)),
            method: .syntheticTap,
            prepare: { $0 },
            complete: { point in
                dispatchedPoint = point
                return true
            }
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(dispatchedPoint, rawPoint)
    }

    func testExecuteRotorWithoutCustomRotorsReportsNextStep() async throws {
        let heistId: HeistId = "plain_rotor_host"
        let liveObject = UIView()
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Plain rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            selection: .named("Errors"),
            target: try AccessibilityTarget.label("Plain rotor host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertDiagnostic(result.message, contains: [
            "rotor failed",
            "attempted rotor=\"Errors\" direction=next",
            "availableRotors=[]",
            "observed customRotors=[]",
            "try target an element exposing custom rotors",
        ])
    }

    func testExecuteRotorDispatchesLiveRotorAction() async throws {
        let heistId: HeistId = "live_rotor_host"
        let liveObject = UIView()
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Live Rotor") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: liveObject, targetRange: nil)
            },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            selection: .named("Live Rotor"),
            target: try AccessibilityTarget.label("Rotor host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Rotor host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorUsesOnscreenAccessibilityGeometryAtViewportEdge() async throws {
        let heistId: HeistId = "edge_rotor_host"
        let frame = CGRect(x: 20, y: -20, width: 180, height: 44)
        let element = AccessibilityElement.make(
            label: "Edge Rotor Host",
            identifier: heistId.rawValue,
            traits: .staticText,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: CGPoint(x: frame.midX, y: 2),
            customRotors: [.init(name: "Live Rotor")]
        )
        let liveObject = UIView()
        liveObject.accessibilityFrame = frame
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Live Rotor") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: liveObject, targetRange: nil)
            },
        ]
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        let result = await brains.actions.executeRotor(
            selection: .named("Live Rotor"),
            target: try AccessibilityTarget.identifier("edge_rotor_host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Edge Rotor Host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorDoesNotRequireHostActivationPointOnscreen() async throws {
        let heistId: HeistId = "offscreen_rotor_host"
        let screenBounds = ScreenMetrics.current.bounds
        let frame = CGRect(x: 32, y: screenBounds.maxY - 8, width: 240, height: 44)
        let activationPoint = CGPoint(x: frame.midX, y: frame.midY)
        let element = AccessibilityElement.make(
            label: "Offscreen Rotor Host",
            identifier: heistId.rawValue,
            traits: .staticText,
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: activationPoint,
            customRotors: [.init(name: "Live Rotor")]
        )
        let liveObject = UIView()
        liveObject.accessibilityFrame = frame
        liveObject.accessibilityActivationPoint = activationPoint
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Live Rotor") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: liveObject, targetRange: nil)
            },
        ]
        installScreen(elements: [(element, heistId)], objects: [heistId: liveObject])

        let result = await brains.actions.executeRotor(
            selection: .named("Live Rotor"),
            target: try AccessibilityTarget.identifier("offscreen_rotor_host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Offscreen Rotor Host") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorScrollsViewportTowardResultActivationPoint() async throws {
        let hostHeistId: HeistId = "rotor_result_host"
        let resultHeistId: HeistId = "rotor_result_target"
        let scrollContainerPath = TreePath([0])
        let screenBounds = ScreenMetrics.current.bounds
        let scrollView = UIScrollView(frame: screenBounds)
        scrollView.contentSize = CGSize(width: screenBounds.width, height: screenBounds.height + 900)
        let scrollContainer = AccessibilityContainer(
            type: .none,
            scrollableContentSize: AccessibilitySize(scrollView.contentSize),
            frame: AccessibilityRect(screenBounds)
        )

        let hostFrame = CGRect(x: 32, y: 80, width: 240, height: 44)
        let hostElement = AccessibilityElement.make(
            label: "Rotor Host",
            identifier: hostHeistId.rawValue,
            traits: .staticText,
            shape: .frame(AccessibilityRect(hostFrame)),
            activationPoint: CGPoint(x: hostFrame.midX, y: hostFrame.midY),
            customRotors: [.init(name: "Live Rotor")]
        )
        let resultFrame = CGRect(x: 32, y: screenBounds.maxY + 240, width: 240, height: 44)
        let resultElement = AccessibilityElement.make(
            label: "Rotor Result",
            identifier: resultHeistId.rawValue,
            traits: .staticText,
            shape: .frame(AccessibilityRect(resultFrame)),
            activationPoint: CGPoint(x: resultFrame.midX, y: resultFrame.midY)
        )

        let resultObject = UIView()
        resultObject.accessibilityFrame = resultFrame
        resultObject.accessibilityActivationPoint = CGPoint(x: resultFrame.midX, y: resultFrame.midY)

        let hostObject = UIView()
        hostObject.accessibilityFrame = hostFrame
        hostObject.accessibilityActivationPoint = CGPoint(x: hostFrame.midX, y: hostFrame.midY)
        hostObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Live Rotor") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: resultObject, targetRange: nil)
            },
        ]

        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [
                hostHeistId: InterfaceTree.Element(
                    heistId: hostHeistId,
                    scrollMembership: .init(containerPath: scrollContainerPath, index: 0),
                    element: hostElement
                ),
                resultHeistId: InterfaceTree.Element(
                    heistId: resultHeistId,
                    scrollMembership: .init(containerPath: scrollContainerPath, index: 1),
                    element: resultElement
                ),
            ],
            hierarchy: [
                .container(scrollContainer, children: [
                    .element(hostElement, traversalIndex: 0),
                    .element(resultElement, traversalIndex: 1),
                ]),
            ],
            heistIdsByPath: [
                TreePath([0, 0]): hostHeistId,
                TreePath([0, 1]): resultHeistId,
            ],
            elementRefs: [
                hostHeistId: .init(object: hostObject, scrollView: scrollView),
                resultHeistId: .init(object: resultObject, scrollView: scrollView),
            ],
            containerRefsByPath: [scrollContainerPath: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [scrollContainerPath: .init(view: scrollView)]
        ))

        XCTAssertEqual(scrollView.contentOffset, .zero)

        let result = await brains.actions.executeRotor(
            selection: .named("Live Rotor"),
            target: try AccessibilityTarget.identifier(hostHeistId.rawValue).resolve(in: .empty),
            direction: .next
        )

        XCTAssertTrue(result.success, result.message ?? "rotor failed")
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertGreaterThan(scrollView.contentOffset.y, 0)
        XCTAssertTrue(result.message?.contains("Rotor 'Live Rotor' found Rotor Result") ?? false,
                      result.message ?? "missing rotor success message")
    }

    func testExecuteRotorNotFoundReportsAvailableRotorsAndNextStep() async throws {
        let heistId: HeistId = "rotor_host"
        let liveObject = UIView()
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Warnings") { _ in nil },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(
                label: "Rotor host",
                traits: .button,
                customRotors: [.init(name: "Warnings")]
            ),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            selection: .named("Errors"),
            target: try AccessibilityTarget.label("Rotor host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method.rawValue, ActionMethod.rotor.rawValue)
        XCTAssertDiagnostic(result.message, contains: [
            "rotor failed",
            "attempted rotor=\"Errors\" direction=next",
            "requestedRotor=\"Errors\"",
            "availableRotors=[\"Warnings\"]",
            "try use one of available rotors [\"Warnings\"]",
        ])
    }

    func testExecuteRotorDiagnosticsMergeLiveRotors() async throws {
        let heistId: HeistId = "rotor_host"
        let liveObject = UIView()
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Warnings") { _ in nil },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            selection: .named("Errors"),
            target: try AccessibilityTarget.label("Rotor host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertFalse(result.success)
        XCTAssertDiagnostic(result.message, contains: [
            "availableRotors=[\"Warnings\"]",
            "try use one of available rotors [\"Warnings\"]",
        ])
    }

    func testExecuteRotorDiagnosticsUseSystemRotorDisplayName() async throws {
        let heistId: HeistId = "rotor_host"
        let liveObject = UIView()
        liveObject.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(systemType: .link) { _ in nil },
        ]
        registerScreenElement(
            heistId: heistId,
            element: makeElement(label: "Rotor host", traits: .button),
            object: liveObject
        )

        let result = await brains.actions.executeRotor(
            selection: .named("Errors"),
            target: try AccessibilityTarget.label("Rotor host").resolve(in: .empty),
            direction: .next
        )

        XCTAssertFalse(result.success)
        XCTAssertDiagnostic(result.message, contains: [
            "availableRotors=[\"Links\"]",
            "try use one of available rotors [\"Links\"]",
        ])
    }

}

#endif
