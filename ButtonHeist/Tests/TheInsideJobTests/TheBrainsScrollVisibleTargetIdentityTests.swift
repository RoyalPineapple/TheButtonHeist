#if canImport(UIKit)
import ButtonHeistSupport
import XCTest
import ThePlans
import UIKit
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@_spi(ButtonHeistInternals) @testable import TheScore

@MainActor
extension TheBrainsScrollTests {

    func testScrollToVisibleVisibleAmbiguousMatcherFailsClosed() async throws {
        let first = makeElement(label: "Duplicate", traits: .button)
        let second = makeElement(label: "Duplicate", traits: .button)
        let firstEntry = InterfaceTree.Element(
            heistId: "duplicate_1",
            scrollMembership: nil,
            element: first
        )
        let secondEntry = InterfaceTree.Element(
            heistId: "duplicate_2",
            scrollMembership: nil,
            element: second
        )
        await brains.vault.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [
                firstEntry.heistId: firstEntry,
                secondEntry.heistId: secondEntry,
            ],
            hierarchy: [
                .element(first, traversalIndex: 0),
                .element(second, traversalIndex: 1),
            ],
            heistIdsByPath: [
                TreePath([0]): firstEntry.heistId,
                TreePath([1]): secondEntry.heistId,
            ],
            firstResponderHeistId: nil,
        ))

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .label("Duplicate"))
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertTrue(
            result.message?.contains("element inflation failed [ambiguous]") ?? false,
            "Expected classified ambiguity diagnostic, got \(String(describing: result.message))"
        )
        XCTAssertTrue(
            result.message?.contains("2 elements match") ?? false,
            "Expected ambiguity diagnostic, got \(String(describing: result.message))"
        )
    }

    func testScrollToVisiblePreservesVisibleMatcherOrdinalOutOfRange() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        rootView.addSubview(makeButton(label: "Save", frame: CGRect(x: 40, y: 120, width: 260, height: 44)))

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)

        let result = await brains.navigation.executeScrollToVisible(
            target: try resolvedScrollToVisibleTarget(
                ScrollToVisibleTarget(target: .target(.label("Save"), ordinal: 3))
            )
        )

        XCTAssertFalse(result.success)
        XCTAssertEqual(result.method, .scrollToVisible)
        XCTAssertTrue(
            result.message?.contains("ordinal 3 requested") ?? false,
            "Expected ordinal diagnostic, got \(String(describing: result.message))"
        )
    }

    func testScrollToVisibleFailsWhenAdmittedIdentityBecomesAmbiguous() async throws {
        let rootView = UIView()
        rootView.backgroundColor = .white
        let scrollView = AccessibilityRevealingScrollView(frame: CGRect(x: 0, y: 0, width: 320, height: 400))
        scrollView.contentSize = CGSize(width: 320, height: 1_600)
        let firstTarget = makeAccessibleView(label: "Jump Target", frame: CGRect(x: 40, y: 900, width: 240, height: 44))
        let secondTarget = makeAccessibleView(label: "Jump Target", frame: CGRect(x: 40, y: 960, width: 240, height: 44))
        scrollView.revealedElements = [firstTarget, secondTarget]
        scrollView.updateAccessibilityVisibility()
        scrollView.addSubview(firstTarget)
        scrollView.addSubview(secondTarget)
        rootView.addSubview(scrollView)

        let window = try installModalWindow(rootView: rootView)
        defer {
            window.rootViewController?.view.accessibilityViewIsModal = false
            window.isHidden = true
        }
        await brains.tripwire.yieldFrames(3)
        let scrollContainerPath = TreePath([0])
        let liveScreen = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [
                .container(
                    makeScrollableContainer(contentSize: scrollView.contentSize, frame: scrollView.frame),
                    children: []
                ),
            ],
            containerRefsByPath: [scrollContainerPath: .init(object: scrollView)],
            firstResponderHeistId: nil,
            scrollableContainerViewsByPath: [scrollContainerPath: .init(view: scrollView)]
        )
        await brains.vault.installObservationForTesting(liveScreen)
        let prematureResolution = brains.vault.resolveTarget(
            literalTarget(ResolvedElementPredicate.label("Jump Target"), ordinal: 0)
        )
        guard case .notFound = prematureResolution else {
            XCTFail("Parser exposed offscreen scroll content before semantic reveal: \(prematureResolution)")
            return
        }

        let interfaceElement = makeElement(
            label: "Jump Target",
            traits: .button,
            shape: .frame(AccessibilityRect(firstTarget.frame))
        )
        let knownEntry = InterfaceTree.Element(
            heistId: "known_reveal_target",
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: scrollContainerPath, index: nil),
            observedScrollContentActivationPoint: observedContentActivationPoint(CGPoint(
                x: firstTarget.frame.midX,
                y: firstTarget.frame.midY
            ), ownerPath: scrollContainerPath),
            element: interfaceElement
        )
        let knownScreen = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [knownEntry.heistId: knownEntry],
                containers: liveScreen.tree.containers
            ),
            liveCapture: liveScreen.liveCapture
        )
        await brains.vault.installObservationForTesting(knownScreen)
        brains.navigation.elementInflation.exploration.discoverTarget = { _ in nil }

        let result = await brains.navigation.elementInflation.inflate(
            for: try resolvedTarget(.label("Jump Target")),
            method: .scrollToVisible
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected uncommitted live identities to fail closed, got \(result)")
        }
        XCTAssertEqual(failure.failedStep, .ambiguous)
        XCTAssertEqual(failure.failureKind, .targetUnavailable)
        XCTAssertTrue(failure.message.contains("[ambiguous]"))
    }

}

#endif
