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

        let resolvedHost = stash.resolveTarget(.matcher(ElementMatcher(identifier: "rotor_host"))).resolved?.screenElement
        guard let resolvedHost else {
            XCTFail("Expected rotor host to resolve")
            return
        }

        let outcome = stash.performRotor(
            RotorTarget(
                elementTarget: .heistId(resolvedHost.heistId),
                rotor: "Errors"
            ),
            direction: .next,
            on: resolvedHost
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
                rotor: "Primary Action"
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

    func testOutOfTreeRotorResultElementCanBeActivatedByReturnedHeistId() async throws {
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
                rotor: "Primary Action"
            )
        ))

        XCTAssertTrue(searchResult.success, searchResult.message ?? "rotor failed")
        guard case .rotor(let rotorResult)? = searchResult.payload,
              let foundElement = rotorResult.foundElement else {
            XCTFail("Expected rotor to return a found element")
            return
        }

        XCTAssertEqual(foundElement.label, "Open virtual result")
        XCTAssertTrue(foundElement.heistId.hasPrefix("rotor_result_"))

        let activateResult = await brains.executeCommand(.activate(.heistId(foundElement.heistId)))

        XCTAssertTrue(activateResult.success, activateResult.message ?? "activate failed")
        XCTAssertEqual(virtualResult.activationCount, 1)
    }

    func testRotorResultUsesKnownObjectIdentityWhenCached() async throws {
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
        var elements = screen.elements
        elements[cachedHeistId] = Screen.ScreenElement(
            heistId: cachedHeistId,
            contentSpaceOrigin: nil,
            element: AccessibilityElement.make(
                label: "Cached virtual result",
                identifier: cachedHeistId,
                traits: .button,
                frame: CGRect(x: 20, y: 120, width: 280, height: 44)
            ),
            object: cachedResult,
            scrollView: nil
        )
        brains.stash.currentScreen = Screen(
            elements: elements,
            hierarchy: screen.hierarchy,
            containerStableIds: screen.containerStableIds,
            heistIdByElement: screen.heistIdByElement,
            firstResponderHeistId: screen.firstResponderHeistId,
            scrollableContainerViews: screen.scrollableContainerViews
        )

        let search = await brains.actions.executeRotor(
            RotorTarget(
                elementTarget: .matcher(ElementMatcher(identifier: "cached_rotor_host")),
                rotor: "Cached Items"
            )
        )

        XCTAssertTrue(search.success, search.message ?? "rotor failed")
        guard case .rotor(let rotorResult)? = search.payload else {
            XCTFail("Expected rotor payload, got \(String(describing: search.payload))")
            return
        }
        XCTAssertEqual(rotorResult.foundElement?.heistId, cachedHeistId)

        let activate = await brains.executeCommand(.activate(.heistId(cachedHeistId)))

        XCTAssertTrue(activate.success, activate.message ?? "activate failed")
        XCTAssertEqual(cachedResult.activationCount, 1)
    }

    func testOutOfTreeRotorCanContinueNextAndPreviousFromReturnedHeistId() async throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Virtual Step Results"
        rotorHost.accessibilityIdentifier = "virtual_step_rotor_host"

        let firstResult = RotorActivationAccessibilityElement(accessibilityContainer: viewController.view as Any)
        firstResult.accessibilityLabel = "First virtual result"
        firstResult.accessibilityTraits = .button
        firstResult.accessibilityFrameInContainerSpace = CGRect(x: 20, y: 120, width: 280, height: 44)

        let secondResult = RotorActivationAccessibilityElement(accessibilityContainer: viewController.view as Any)
        secondResult.accessibilityLabel = "Second virtual result"
        secondResult.accessibilityTraits = .button
        secondResult.accessibilityFrameInContainerSpace = CGRect(x: 20, y: 180, width: 280, height: 44)

        let results = [firstResult, secondResult]
        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Virtual Steps") { predicate in
                let ordered = predicate.searchDirection == .next ? results : Array(results.reversed())
                if let current = predicate.currentItem.targetElement as? RotorActivationAccessibilityElement,
                   let index = ordered.firstIndex(where: { $0 === current }) {
                    let nextIndex = ordered.index(after: index)
                    guard nextIndex < ordered.endIndex else { return nil }
                    return UIAccessibilityCustomRotorItemResult(targetElement: ordered[nextIndex], targetRange: nil)
                }
                guard let first = ordered.first else { return nil }
                return UIAccessibilityCustomRotorItemResult(targetElement: first, targetRange: nil)
            }
        ]

        viewController.view.addSubview(rotorHost)

        let window = UIWindow(windowScene: windowScene)
        window.windowLevel = .alert + 34
        window.rootViewController = viewController
        window.frame = UIScreen.main.bounds
        window.isHidden = false
        defer {
            window.isHidden = true
        }

        let brains = TheBrains(tripwire: TheTripwire())
        let firstSearch = await brains.executeCommand(.rotor(
            RotorTarget(
                elementTarget: .matcher(ElementMatcher(identifier: "virtual_step_rotor_host")),
                rotor: "Virtual Steps"
            )
        ))

        guard case .rotor(let firstRotorResult)? = firstSearch.payload,
              let firstElement = firstRotorResult.foundElement else {
            XCTFail("Expected first rotor result")
            return
        }
        XCTAssertEqual(firstElement.label, "First virtual result")

        let nextSearch = await brains.executeCommand(.rotor(
            RotorTarget(
                elementTarget: .matcher(ElementMatcher(identifier: "virtual_step_rotor_host")),
                rotor: "Virtual Steps",
                currentHeistId: firstElement.heistId
            )
        ))

        guard case .rotor(let nextRotorResult)? = nextSearch.payload,
              let nextElement = nextRotorResult.foundElement else {
            XCTFail("Expected next rotor result")
            return
        }
        XCTAssertEqual(nextElement.label, "Second virtual result")

        let previousSearch = await brains.executeCommand(.rotor(
            RotorTarget(
                elementTarget: .matcher(ElementMatcher(identifier: "virtual_step_rotor_host")),
                rotor: "Virtual Steps",
                direction: .previous,
                currentHeistId: nextElement.heistId
            )
        ))

        guard case .rotor(let previousRotorResult)? = previousSearch.payload,
              let previousElement = previousRotorResult.foundElement else {
            XCTFail("Expected previous rotor result")
            return
        }
        XCTAssertEqual(previousElement.label, "First virtual result")
    }

    func testOutOfTreeRotorResultExpiresAfterUnrelatedCommand() async throws {
        let windowScene = try requireForegroundWindowScene()
        let viewController = UIViewController()
        viewController.view.backgroundColor = .white

        let rotorHost = UIView(frame: CGRect(x: 20, y: 40, width: 280, height: 44))
        rotorHost.isAccessibilityElement = true
        rotorHost.accessibilityLabel = "Virtual Activation Results"
        rotorHost.accessibilityIdentifier = "expiring_virtual_activation_rotor_host"

        let virtualResult = RotorActivationAccessibilityElement(accessibilityContainer: viewController.view as Any)
        virtualResult.accessibilityLabel = "Open expiring virtual result"
        virtualResult.accessibilityTraits = .button
        virtualResult.accessibilityFrameInContainerSpace = CGRect(x: 20, y: 120, width: 280, height: 44)

        rotorHost.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Primary Action") { _ in
                UIAccessibilityCustomRotorItemResult(targetElement: virtualResult, targetRange: nil)
            }
        ]

        viewController.view.addSubview(rotorHost)

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
                elementTarget: .matcher(ElementMatcher(identifier: "expiring_virtual_activation_rotor_host")),
                rotor: "Primary Action"
            )
        ))

        guard case .rotor(let rotorResult)? = searchResult.payload,
              let foundElement = rotorResult.foundElement else {
            XCTFail("Expected rotor to return a found element")
            return
        }

        let unrelatedResult = await brains.executeCommand(.increment(.heistId("not_the_rotor_result")))
        XCTAssertFalse(unrelatedResult.success)

        let activateResult = await brains.executeCommand(.activate(.heistId(foundElement.heistId)))

        XCTAssertFalse(activateResult.success)
        XCTAssertEqual(activateResult.errorKind, .elementNotFound)
        XCTAssertEqual(virtualResult.activationCount, 0)
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

        let resolvedTextView = stash.resolveTarget(.matcher(ElementMatcher(identifier: "mentions_text"))).resolved?.screenElement
        guard let resolvedTextView else {
            XCTFail("Expected text view to resolve")
            return
        }

        let firstOutcome = stash.performRotor(
            RotorTarget(
                elementTarget: .heistId(resolvedTextView.heistId),
                rotor: "Mentions"
            ),
            direction: .next,
            on: resolvedTextView
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
            RotorTarget(
                elementTarget: .heistId(resolvedTextView.heistId),
                rotor: "Mentions",
                currentHeistId: firstHit.screenElement?.heistId,
                currentTextRange: TextRangeReference(startOffset: firstStart, endOffset: firstEnd)
            ),
            direction: .next,
            on: resolvedTextView
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
        let host = NSObject()
        let element = AccessibilityElement.make(
            label: "Validation Results",
            identifier: "rotor_host",
            customRotors: [.init(name: "Warnings", resultMarkers: [], limit: .none)]
        )
        let screenElement = Screen.ScreenElement(
            heistId: "rotor_host",
            contentSpaceOrigin: nil,
            element: element,
            object: host,
            scrollView: nil
        )
        host.accessibilityCustomRotors = [
            UIAccessibilityCustomRotor(name: "Warnings") { _ in nil }
        ]

        let outcome = stash.performRotor(
            RotorTarget(
                elementTarget: .heistId("rotor_host"),
                rotor: "Errors"
            ),
            direction: .next,
            on: screenElement
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
