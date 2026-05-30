#if canImport(UIKit)
import UIKit
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

private final class RotorActivationResultView: UIView {
    private(set) var activationCount = 0

    override func accessibilityActivate() -> Bool {
        activationCount += 1
        return true
    }
}

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
        stash.currentScreen = screen

        let resolvedHost = stash.resolveTarget(.matcher(ElementMatcher(identifier: "rotor_host"))).resolved
        guard let resolvedHost else {
            XCTFail("Expected rotor host to resolve")
            return
        }
        let liveHost = try XCTUnwrap(liveTarget(for: resolvedHost))

        let outcome = stash.performRotor(
            selection: .named("Errors"),
            continuation: .none,
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
        stash.currentScreen = screen

        let resolvedHost = stash.resolveTarget(.matcher(ElementMatcher(identifier: "system_rotor_host"))).resolved
        guard let resolvedHost else {
            XCTFail("Expected rotor host to resolve")
            return
        }
        let liveHost = try XCTUnwrap(liveTarget(for: resolvedHost))

        XCTAssertEqual(rotorHost.accessibilityCustomRotors?.first?.name, "")
        XCTAssertEqual(resolvedHost.element.customRotors.map { $0.name }, ["Links"])

        let outcome = stash.performRotor(
            selection: .named("Links"),
            continuation: .none,
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

    func testRotorResultElementCanBeActivatedByReturnedHeistId() async throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Activation Results"
        rotorHost.accessibilityIdentifier = "activation_rotor_host"

        let resultView = RotorActivationResultView(frame: CGRect(x: 20, y: 120, width: 280, height: 44))
        resultView.isAccessibilityElement = true
        resultView.accessibilityLabel = "Open returned action"
        resultView.accessibilityIdentifier = "rotor_activation_target"
        resultView.accessibilityTraits = .button

        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Primary Action") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: resultView, targetRange: nil)
            }
        ]

        viewController.view.addSubview(rotorHost)
        viewController.view.addSubview(resultView)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 32
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        defer {
            window.isHidden = true
        }

        let brains = TheBrains(tripwire: TheTripwire())
        let searchResult = await brains.executeCommand(.rotor(
            RotorTarget(
                elementTarget: .matcher(ElementMatcher(identifier: "activation_rotor_host")),
                selection: .named("Primary Action")
            )
        ))

        XCTAssertTrue(searchResult.success, searchResult.message ?? "rotor failed")
        guard case .rotor(let rotorResult)? = searchResult.payload,
              let foundElement = rotorResult.foundElement else {
            XCTFail("Expected rotor to return a found element")
            return
        }

        XCTAssertEqual(foundElement.identifier, "rotor_activation_target")

        let activateResult = await brains.executeCommand(.activate(.heistId(foundElement.heistId)))

        XCTAssertTrue(activateResult.success, activateResult.message ?? "activate failed")
        XCTAssertEqual(resultView.activationCount, 1)
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
        let searchResult = await brains.executeCommand(.rotor(
            RotorTarget(
                elementTarget: .matcher(ElementMatcher(identifier: "virtual_activation_rotor_host")),
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
        guard let screen = brains.refresh() else {
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
        brains.stash.currentScreen = Screen(
            semantic: SemanticScreen(elements: elements, containers: screen.semantic.containers),
            liveCapture: screen.liveCapture
        )

        let search = await brains.actions.executeRotor(
            RotorTarget(
                elementTarget: .matcher(ElementMatcher(identifier: "cached_rotor_host")),
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

    func testRotorContinuationRequiresVisibleCurrentItem() async throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Continuation Results"
        rotorHost.accessibilityIdentifier = "continuation_rotor_host"

        let resultView = UIView(frame: CGRect(x: 20, y: 120, width: 280, height: 44))
        resultView.isAccessibilityElement = true
        resultView.accessibilityLabel = "Visible rotor result"

        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Primary Action") { predicate in
                XCTAssertNil(predicate.currentItem.targetElement)
                return UIAccessibilityCustomRotorItemResult(targetElement: resultView, targetRange: nil)
            }
        ]

        viewController.view.addSubview(rotorHost)
        viewController.view.addSubview(resultView)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 35
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        defer {
            window.isHidden = true
        }

        let brains = TheBrains(tripwire: TheTripwire())
        let searchResult = await brains.executeCommand(.rotor(
            RotorTarget(
                elementTarget: .matcher(ElementMatcher(identifier: "continuation_rotor_host")),
                selection: .named("Primary Action"),
                continuation: .item("missing_current_item")
            )
        ))

        XCTAssertFalse(searchResult.success)
        XCTAssertEqual(searchResult.errorKind, .elementNotFound)
        XCTAssertTrue(searchResult.message?.contains("currentHeistId=\"missing_current_item\" is not available") == true)
    }

    func testRotorReturnsTextRangeResult() throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let textView = makeTextRangeRotorTextView()
        viewController.view.addSubview(textView)

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
        stash.currentScreen = screen

        let resolvedTextView = stash.resolveTarget(.matcher(ElementMatcher(identifier: "mentions_text"))).resolved
        guard let resolvedTextView else {
            XCTFail("Expected text view to resolve")
            return
        }
        let liveTextView = try XCTUnwrap(liveTarget(for: resolvedTextView))

        let firstOutcome = stash.performRotor(
            selection: .named("Mentions"),
            continuation: .none,
            direction: .next,
            on: liveTextView
        )

        guard case .succeeded(let firstHit) = firstOutcome,
              let firstRange = firstHit.textRange,
              let firstStart = firstRange.startOffset,
              let firstEnd = firstRange.endOffset else {
            XCTFail("Expected first text-range rotor result, got \(firstOutcome)")
            return
        }
        XCTAssertEqual(firstHit.screenElement?.element.identifier, "mentions_text")
        XCTAssertEqual(firstRange.text, "@maria")
        XCTAssertEqual(firstRange.rangeDescription, "[7..<13]")

        let secondOutcome = stash.performRotor(
            selection: .named("Mentions"),
            continuation: .textRange(
                try XCTUnwrap(firstHit.screenElement?.heistId),
                TextRangeReference(startOffset: firstStart, endOffset: firstEnd)
            ),
            direction: .next,
            on: liveTextView
        )

        guard case .succeeded(let secondHit) = secondOutcome,
              let secondRange = secondHit.textRange else {
            XCTFail("Expected second text-range rotor result, got \(secondOutcome)")
            return
        }
        XCTAssertEqual(secondRange.text, "@jules")
        XCTAssertEqual(secondRange.rangeDescription, "[22..<28]")
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
        stash.currentScreen = Screen(
            elements: [screenElement.heistId: screenElement],
            hierarchy: [.element(element, traversalIndex: 0)],
            containerStableIds: [:],
            heistIdByElement: [element: screenElement.heistId],
            elementRefs: [
                screenElement.heistId: .init(object: host, scrollView: nil)
            ],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        let outcome = stash.performRotor(
            selection: .named("Errors"),
            continuation: .none,
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

    private func makeTextRangeRotorTextView() -> UITextView {
        let textView = UITextView(frame: CGRect(x: 20, y: 40, width: 320, height: 120))
        textView.text = "Review @maria and ask @jules."
        textView.isEditable = false
        textView.isSelectable = true
        textView.isScrollEnabled = false
        textView.isAccessibilityElement = true
        textView.accessibilityLabel = "Mentions Text"
        textView.accessibilityIdentifier = "mentions_text"
        textView.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Mentions") { [weak textView] predicate in
                guard let textView else { return nil }
                let ranges = Self.mentionRanges(in: textView)
                guard !ranges.isEmpty else { return nil }
                let ordered = predicate.searchDirection == .next ? ranges : Array(ranges.reversed())
                if let currentRange = predicate.currentItem.targetRange,
                   let index = ordered.firstIndex(of: currentRange) {
                    let nextIndex = ordered.index(after: index)
                    guard nextIndex < ordered.endIndex else { return nil }
                    return UIAccessibilityCustomRotorItemResult(targetElement: textView, targetRange: ordered[nextIndex])
                }
                return UIAccessibilityCustomRotorItemResult(targetElement: textView, targetRange: ordered.first)
            }
        ]
        return textView
    }

    private static func mentionRanges(in textView: UITextView) -> [UITextRange] {
        let pattern = "@[A-Za-z]+"
        let fullRange = NSRange(textView.text.startIndex..., in: textView.text)
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
        return expression.matches(in: textView.text, range: fullRange).compactMap { match in
            guard let start = textView.position(from: textView.beginningOfDocument, offset: match.range.location),
                  let end = textView.position(from: start, offset: match.range.length) else {
                return nil
            }
            return textView.textRange(from: start, to: end)
        }
    }
}

#endif
