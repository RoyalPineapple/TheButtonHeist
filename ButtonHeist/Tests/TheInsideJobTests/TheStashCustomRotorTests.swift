#if canImport(UIKit)
import UIKit
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

private final class RotorActivationAccessibilityElement: UIAccessibilityElement {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

private final class RotorCustomActionHandler: NSObject {
    private(set) var actionCount = 0

    @objc func archive(_ action: UIAccessibilityCustomAction) -> Bool {
        actionCount += 1
        return true
    }
}

@MainActor
final class TheStashRotorTests: XCTestCase {

    private var stash: TheStash!

    override func setUp() async throws {
        try await super.setUp()
        stash = TheStash(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        stash = nil
        try await super.tearDown()
    }

    private func liveTarget(
        for screenElement: TheStash.ScreenElement
    ) -> TheStash.LiveActionTarget? {
        guard case .resolved(let liveTarget) = stash.resolveLiveActionTarget(for: screenElement) else {
            return nil
        }
        return liveTarget
    }

    func testRotorNextReturnsParsedLiveResultElement() throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Validation Results"
        rotorHost.accessibilityIdentifier = "rotor_host"

        let resultLabel = UILabel(frame: CGRect(x: 20, y: 120, width: 280, height: 44))
        resultLabel.text = "Missing amount"
        resultLabel.accessibilityLabel = "Missing amount"
        resultLabel.accessibilityIdentifier = "missing_amount"
        resultLabel.isAccessibilityElement = true

        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Errors") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: resultLabel, targetRange: nil)
            }
        ]

        viewController.view.addSubview(rotorHost)
        viewController.view.addSubview(resultLabel)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 30
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        defer {
            window.isHidden = true
        }

        guard let screen = stash.parse() else {
            XCTFail("Expected live parse result")
            return
        }
        stash.installScreenForTesting(screen)

        let resolvedHost = stash.resolveTarget(.predicate(ElementPredicate(identifier: "rotor_host"))).resolved
        guard let resolvedHost else {
            XCTFail("Expected rotor host to resolve")
            return
        }
        let liveHost = try XCTUnwrap(liveTarget(for: resolvedHost))

        let outcome = stash.performRotor(
            selection: .named("Errors"),
            direction: .next,
            on: liveHost
        )

        guard case .succeeded(let hit) = outcome else {
            XCTFail("Expected rotor to succeed, got \(outcome)")
            return
        }
        XCTAssertEqual(hit.rotor, "Errors")
        XCTAssertEqual(hit.screenElement?.element.identifier, "missing_amount")
        XCTAssertEqual(hit.screenElement?.element.label, "Missing amount")
        XCTAssertNil(hit.textRange)
    }

    func testSystemRotorCanBeInvokedByDisplayedName() throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Resources"
        rotorHost.accessibilityIdentifier = "system_rotor_host"

        let resultLabel = UILabel(frame: CGRect(x: 20, y: 120, width: 280, height: 44))
        resultLabel.text = "Open Docs"
        resultLabel.accessibilityLabel = "Open Docs"
        resultLabel.accessibilityIdentifier = "open_docs"
        resultLabel.isAccessibilityElement = true

        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(systemType: .link) { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: resultLabel, targetRange: nil)
            }
        ]

        viewController.view.addSubview(rotorHost)
        viewController.view.addSubview(resultLabel)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 31
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        defer {
            window.isHidden = true
        }

        guard let screen = stash.parse() else {
            XCTFail("Expected live parse result")
            return
        }
        stash.installScreenForTesting(screen)

        let resolvedHost = stash.resolveTarget(.predicate(ElementPredicate(identifier: "system_rotor_host"))).resolved
        guard let resolvedHost else {
            XCTFail("Expected rotor host to resolve")
            return
        }
        let liveHost = try XCTUnwrap(liveTarget(for: resolvedHost))

        XCTAssertEqual(rotorHost.accessibilityCustomRotors?.first?.name, "")
        XCTAssertEqual(resolvedHost.element.customRotors.map { $0.name }, ["Links"])

        let outcome = stash.performRotor(
            selection: .named("Links"),
            direction: .next,
            on: liveHost
        )

        guard case .succeeded(let hit) = outcome else {
            XCTFail("Expected rotor to succeed, got \(outcome)")
            return
        }
        XCTAssertEqual(hit.rotor, "Links")
        XCTAssertEqual(hit.screenElement?.element.identifier, "open_docs")
    }

    func testOutOfTreeRotorResultFailsInsteadOfCreatingHiddenContinuationState() async throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Virtual Activation Results"
        rotorHost.accessibilityIdentifier = "virtual_activation_rotor_host"

        let virtualResult = RotorActivationAccessibilityElement(accessibilityContainer: viewController.view as Any)
        virtualResult.accessibilityLabel = "Open virtual result"
        virtualResult.accessibilityTraits = .button
        virtualResult.accessibilityFrameInContainerSpace = CGRect(x: 20, y: 120, width: 280, height: 44)
        let customActionHandler = RotorCustomActionHandler()
        virtualResult.accessibilityCustomActions = [
            UIAccessibilityCustomAction(
                name: "Archive",
                target: customActionHandler,
                selector: #selector(RotorCustomActionHandler.archive(_:))
            )
        ]

        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Primary Action") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: virtualResult, targetRange: nil)
            }
        ]

        viewController.view.addSubview(rotorHost)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 33
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        defer {
            window.isHidden = true
        }

        let brains = TheBrains(tripwire: TheTripwire())
        brains.tripwire.startPulse()
        brains.startSemanticObservation()
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
        }
        let searchResult = await brains.executeRuntimeAction(.rotor(
            RotorTarget(
                elementTarget: .predicate(ElementPredicate(identifier: "virtual_activation_rotor_host")),
                selection: .named("Primary Action")
            )
        ))

        XCTAssertFalse(searchResult.success)
        XCTAssertEqual(searchResult.method, .rotor)
        XCTAssertTrue(
            searchResult.message?.contains("returned a target outside the parsed hierarchy") == true,
            searchResult.message ?? "<nil>"
        )
        XCTAssertNil(searchResult.payload)
        XCTAssertEqual(virtualResult.activationCount, 0)
        XCTAssertEqual(customActionHandler.actionCount, 0)
    }

    func testRotorResultDoesNotResolveCachedSemanticElementOutsideParsedHierarchy() async throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Cached Results"
        rotorHost.accessibilityIdentifier = "cached_rotor_host"

        let cachedResult = RotorActivationAccessibilityElement(accessibilityContainer: viewController.view as Any)
        cachedResult.accessibilityLabel = "Cached virtual result"
        cachedResult.accessibilityTraits = .button
        cachedResult.accessibilityFrameInContainerSpace = CGRect(x: 20, y: 120, width: 280, height: 44)

        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Cached Items") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: cachedResult, targetRange: nil)
            }
        ]

        viewController.view.addSubview(rotorHost)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 36
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        defer {
            window.isHidden = true
        }

        let brains = TheBrains(tripwire: TheTripwire())
        guard let screen = brains.stash.refreshLiveCapture() else {
            XCTFail("Expected live parse result")
            return
        }

        let cachedHeistId = "cached_virtual_result"
        var elements = screen.semantic.elements
        elements[cachedHeistId] = Screen.ScreenElement(
            heistId: cachedHeistId,
            contentSpaceOrigin: nil,
            element: AccessibilityElement.make(
                label: "Cached virtual result",
                identifier: cachedHeistId,
                traits: .button,
                frame: CGRect(x: 20, y: 120, width: 280, height: 44)
            )
        )
        brains.stash.installScreenForTesting(Screen(
            semantic: SemanticScreen(elements: elements, containers: screen.semantic.containers),
            liveCapture: screen.liveCapture
        ))

        let search = await brains.actions.executeRotor(
            RotorTarget(
                elementTarget: .predicate(ElementPredicate(identifier: "cached_rotor_host")),
                selection: .named("Cached Items")
            )
        )

        XCTAssertFalse(search.success)
        XCTAssertTrue(
            search.message?.contains("returned a target outside the parsed hierarchy") == true,
            search.message ?? "<nil>"
        )
        XCTAssertNil(search.payload)
        XCTAssertEqual(cachedResult.activationCount, 0)
    }

    func testRotorReportsMissingRotorName() throws {
        let host = UIAccessibilityElement(accessibilityContainer: NSObject())
        let frame = CGRect(x: 20, y: 40, width: 280, height: 44)
        host.accessibilityFrame = frame
        let element = AccessibilityElement.make(
            label: "Validation Results",
            identifier: "rotor_host",
            shape: .frame(AccessibilityRect(frame)),
            activationPoint: CGPoint(x: frame.midX, y: frame.midY),
            customRotors: [.init(name: "Warnings", resultMarkers: [], limit: .none)]
        )
        let screenElement = Screen.ScreenElement(
            heistId: "rotor_host",
            contentSpaceOrigin: nil,
            element: element
        )
        host.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Warnings") { _ in nil }
        ]
        stash.installScreenForTesting(Screen(
            elements: [screenElement.heistId: screenElement],
            hierarchy: [.element(element, traversalIndex: 0)],
            containerNames: [:],
            heistIdByElement: [element: screenElement.heistId],
            elementRefs: [
                screenElement.heistId: .init(object: host, scrollView: nil)
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        ))

        let outcome = stash.performRotor(
            selection: .named("Errors"),
            direction: .next,
            on: try XCTUnwrap(liveTarget(for: screenElement))
        )

        guard case .noSuchRotor(let available) = outcome else {
            XCTFail("Expected missing rotor, got \(outcome)")
            return
        }
        XCTAssertEqual(available, ["Warnings"])
    }

    private func requireForegroundWindowScene() throws -> UIWindowScene {
        guard let scene = UIApplication.shared.connectedScenes
            .first(where: { $0.activationState == .foregroundActive }) as? UIWindowScene
        else {
            throw XCTSkip("No foreground-active UIWindowScene available in test host")
        }
        return scene
    }
}

#endif
