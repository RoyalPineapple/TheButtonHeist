#if canImport(UIKit)
import UIKit
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

private final class RotorActivationAccessibilityElement: UIAccessibilityElement {
    private(set) var activationCount = 0

    convenience init(container: UIView) {
        self.init(accessibilityContainer: container)
    }

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
final class TheVaultCustomRotorTests: XCTestCase {

    private var vault: TheVault!
    private var hostedWindows: [UIWindow] = []

    override func setUp() async throws {
        try await super.setUp()
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        cleanupHostedWindows()
        vault = nil
        try await super.tearDown()
    }

    private func liveTarget(
        for treeElement: InterfaceTree.Element
    ) -> TheVault.LiveActionTarget? {
        guard case .resolved(let liveTarget) = vault.resolveLiveActionTarget(for: treeElement) else {
            return nil
        }
        return liveTarget
    }

    func testRotorNextReturnsParsedLiveResultElement() throws {
        let windowScene = try requireForegroundWindowScene()
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

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

        rootView.addSubview(rotorHost)
        rootView.addSubview(resultLabel)

        _ = hostWindow(
            in: windowScene,
            level: .alert + 30,
            rootView: rootView
        )

        guard let observation = vault.parse() else {
            XCTFail("Expected live parse result")
            return
        }
        vault.installObservationForTesting(observation)

        let resolvedHost = vault.resolveTarget(
            literalTarget(ElementPredicate.identifier("rotor_host"))
        ).resolvedElement
        guard let resolvedHost else {
            XCTFail("Expected rotor host to resolve")
            return
        }
        let liveHost = try XCTUnwrap(liveTarget(for: resolvedHost))

        let outcome = vault.performRotor(
            selection: .named("Errors"),
            direction: .next,
            on: liveHost
        )

        guard case .succeeded(let hit) = outcome else {
            XCTFail("Expected rotor to succeed, got \(outcome)")
            return
        }
        XCTAssertEqual(hit.rotor, "Errors")
        XCTAssertEqual(hit.treeElement?.element.identifier, "missing_amount")
        XCTAssertEqual(hit.treeElement?.element.label, "Missing amount")
        XCTAssertNil(hit.textRange)
    }

    func testSystemRotorCanBeInvokedByDisplayedName() throws {
        let windowScene = try requireForegroundWindowScene()
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

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

        rootView.addSubview(rotorHost)
        rootView.addSubview(resultLabel)

        _ = hostWindow(
            in: windowScene,
            level: .alert + 31,
            rootView: rootView
        )

        guard let observation = vault.parse() else {
            XCTFail("Expected live parse result")
            return
        }
        vault.installObservationForTesting(observation)

        let resolvedHost = vault.resolveTarget(
            literalTarget(ElementPredicate.identifier("system_rotor_host"))
        ).resolvedElement
        guard let resolvedHost else {
            XCTFail("Expected rotor host to resolve")
            return
        }
        let liveHost = try XCTUnwrap(liveTarget(for: resolvedHost))

        XCTAssertEqual(rotorHost.accessibilityCustomRotors?.first?.name, "")
        XCTAssertEqual(resolvedHost.element.customRotors.map { $0.name }, ["Links"])

        let outcome = vault.performRotor(
            selection: .named("Links"),
            direction: .next,
            on: liveHost
        )

        guard case .succeeded(let hit) = outcome else {
            XCTFail("Expected rotor to succeed, got \(outcome)")
            return
        }
        XCTAssertEqual(hit.rotor, "Links")
        XCTAssertEqual(hit.treeElement?.element.identifier, "open_docs")
    }

    func testOutOfTreeRotorResultFailsInsteadOfCreatingHiddenContinuationState() async throws {
        let windowScene = try requireForegroundWindowScene()
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Virtual Activation Results"
        rotorHost.accessibilityIdentifier = "virtual_activation_rotor_host"

        let virtualResult = RotorActivationAccessibilityElement(container: rootView)
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

        rootView.addSubview(rotorHost)

        _ = hostWindow(
            in: windowScene,
            level: .alert + 33,
            rootView: rootView
        )

        let brains = TheBrains(tripwire: TheTripwire())
        brains.tripwire.startPulse()
        brains.startSemanticObservation()
        defer {
            brains.stopSemanticObservation()
            brains.tripwire.stopPulse()
        }
        let searchResult = await brains.executeRuntimeAction(.rotor(
            selection: .named("Primary Action"),
            target: literalTarget(ElementPredicate.identifier("virtual_activation_rotor_host")),
            direction: .next
        ))

        XCTAssertFalse(searchResult.outcome.isSuccess)
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
        let rootView = UIView(frame: UIScreen.main.bounds)
        rootView.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Cached Results"
        rotorHost.accessibilityIdentifier = "cached_rotor_host"

        let cachedResult = RotorActivationAccessibilityElement(container: rootView)
        cachedResult.accessibilityLabel = "Cached virtual result"
        cachedResult.accessibilityTraits = .button
        cachedResult.accessibilityFrameInContainerSpace = CGRect(x: 20, y: 120, width: 280, height: 44)

        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Cached Items") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: cachedResult, targetRange: nil)
            }
        ]

        rootView.addSubview(rotorHost)

        _ = hostWindow(
            in: windowScene,
            level: .alert + 36,
            rootView: rootView
        )

        let brains = TheBrains(tripwire: TheTripwire())
        guard let observation = brains.vault.refreshLiveCapture() else {
            XCTFail("Expected live parse result")
            return
        }

        let cachedHeistId = HeistId(rawValue: "cached_virtual_result")
        var elements = observation.tree.elements
        elements[cachedHeistId] = InterfaceTree.Element(
            heistId: cachedHeistId,
            scrollMembership: nil,
            element: AccessibilityElement.make(
                label: "Cached virtual result",
                identifier: cachedHeistId.rawValue,
                traits: .button,
                frame: CGRect(x: 20, y: 120, width: 280, height: 44)
            )
        )
        brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: InterfaceTree(elements: elements, containers: observation.tree.containers),
            liveCapture: observation.liveCapture
        ))

        let search = await brains.actions.executeRotor(
            selection: .named("Cached Items"),
            target: literalTarget(ElementPredicate.identifier("cached_rotor_host")),
            direction: .next
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
        let treeElement = InterfaceTree.Element(
            heistId: "rotor_host",
            scrollMembership: nil,
            element: element
        )
        host.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Warnings") { _ in nil }
        ]
        vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [treeElement.heistId: treeElement],
            hierarchy: [.element(element, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): treeElement.heistId],
            elementRefs: [
                treeElement.heistId: .init(object: host, scrollView: nil)
            ],
            firstResponderHeistId: nil,
        ))

        let outcome = vault.performRotor(
            selection: .named("Errors"),
            direction: .next,
            on: try XCTUnwrap(liveTarget(for: treeElement))
        )

        guard case .noSuchRotor(let available) = outcome else {
            XCTFail("Expected missing rotor, got \(outcome)")
            return
        }
        XCTAssertEqual(available, ["Warnings"])
    }

    private func hostWindow(
        in scene: UIWindowScene,
        level: UIWindow.Level,
        rootView: UIView
    ) -> UIWindow {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = level
        window.frame = UIScreen.main.bounds
        rootView.frame = window.bounds
        rootView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        window.addSubview(rootView)
        window.isHidden = false
        hostedWindows.append(window)
        drainUIKitPresentationWork()
        return window
    }

    private func cleanupHostedWindows() {
        for window in hostedWindows.reversed() {
            window.layer.removeAllAnimations()
            window.subviews.forEach { $0.removeFromSuperview() }
            window.isHidden = true
        }
        hostedWindows.removeAll()
        drainUIKitPresentationWork()
    }

    private func drainUIKitPresentationWork() {
        for _ in 0..<3 {
            CATransaction.flush()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
        }
    }
}

#endif
