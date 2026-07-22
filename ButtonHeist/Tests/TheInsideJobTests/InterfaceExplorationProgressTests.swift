#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
@testable import TheInsideJob
import ThePlans
import TheScore

@MainActor
final class InterfaceExplorationProgressTests: XCTestCase {

    // MARK: - Helpers

    private func makeScrollableContainer(
        contentSize: CGSize = CGSize(width: 375, height: 2000),
        frame: CGRect = .zero
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(contentSize),
            frame: AccessibilityRect(frame)
        )
    }

    private func semanticContainer(
        _ container: AccessibilityContainer,
        path: TreePath,
        containerName: ContainerName? = nil
    ) -> InterfaceTree.Container {
        InterfaceTree.Container(
            container: container,
            path: path,
            containerName: containerName,
            contentFrame: container.frame.cgRect
        )
    }

    // MARK: - Initial State

    func testEmptyProgress() {
        let progress = Navigation.InterfaceExplorationProgress()
        XCTAssertTrue(progress.pendingScrollPaths.isEmpty)
        XCTAssertTrue(progress.exploredScrollPaths.isEmpty)
        XCTAssertEqual(progress.scrollCount, 0)
        XCTAssertEqual(progress.maxScrollsPerContainer, Navigation.InterfaceExplorationProgress.maxScrollsPerContainer)
        XCTAssertEqual(progress.maxScrollsPerDiscovery, Navigation.InterfaceExplorationProgress.maxScrollsPerDiscovery)
    }

    func testProgressAcceptsPerPassScrollLimits() {
        let progress = Navigation.InterfaceExplorationProgress(
            maxScrollsPerContainer: 25,
            maxScrollsPerDiscovery: 40
        )

        XCTAssertEqual(progress.maxScrollsPerContainer, 25)
        XCTAssertEqual(progress.maxScrollsPerDiscovery, 40)
    }

    func testRecordScrollAttemptCountsAttemptsAndFlagsDiscoveryCap() {
        var progress = Navigation.InterfaceExplorationProgress(
            maxScrollsPerContainer: 10,
            maxScrollsPerDiscovery: 2
        )
        let path = TreePath([0])

        XCTAssertNil(progress.recordScrollAttempt(in: path))
        XCTAssertNil(progress.recordScrollAttempt(in: path))
        XCTAssertEqual(progress.recordScrollAttempt(in: path), .discoveryScrollLimit)

        XCTAssertEqual(progress.scrollCount, 2)
        XCTAssertEqual(progress.limitReasons, [.discoveryScrollLimit])
    }

    // MARK: - markExplored

    func testMarkExploredMovesFromPendingToExplored() {
        var progress = Navigation.InterfaceExplorationProgress()
        let container = makeScrollableContainer()
        let path = TreePath([0])
        progress.addPendingContainers([semanticContainer(container, path: path)])

        XCTAssertFalse(progress.pendingScrollPaths.isEmpty)

        progress.markExplored(path)

        XCTAssertTrue(progress.pendingScrollPaths.isEmpty)
        XCTAssertTrue(progress.exploredScrollPaths.contains(path))
    }

    func testMarkOmittedMovesFromPendingToOmittedOnly() {
        var progress = Navigation.InterfaceExplorationProgress()
        let container = makeScrollableContainer()
        let path = TreePath([0])
        progress.addPendingContainers([semanticContainer(container, path: path)])

        progress.markOmitted(path, reason: .containerScrollLimit)

        XCTAssertFalse(progress.pendingScrollPaths.contains(path))
        XCTAssertFalse(progress.exploredScrollPaths.contains(path))
        XCTAssertEqual(progress.omittedScrollPathReasons[path], [.containerScrollLimit])
    }

    func testOmittedContainerIsNotReaddedToPending() {
        var progress = Navigation.InterfaceExplorationProgress()
        let container = makeScrollableContainer()
        let path = TreePath([0])

        progress.markOmitted(path, reason: .containerScrollLimit)
        progress.addPendingContainers([semanticContainer(container, path: path)])

        XCTAssertFalse(progress.pendingScrollPaths.contains(path))
        XCTAssertEqual(progress.omittedScrollPathReasons[path], [.containerScrollLimit])
    }

    // MARK: - addPendingContainers

    func testAddPendingContainersSkipsAlreadyExplored() {
        var progress = Navigation.InterfaceExplorationProgress()
        let container = makeScrollableContainer()
        let path = TreePath([0])
        progress.markExplored(path)
        progress.addPendingContainers([semanticContainer(container, path: path)])

        XCTAssertTrue(progress.pendingScrollPaths.isEmpty,
                      "An already-explored container must not be re-added to pending")
    }

    func testAddPendingContainersAddsNewContainers() {
        var progress = Navigation.InterfaceExplorationProgress()
        let containerA = makeScrollableContainer(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let containerB = makeScrollableContainer(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        progress.addPendingContainers([
            semanticContainer(containerA, path: TreePath([0])),
            semanticContainer(containerB, path: TreePath([1])),
        ])

        XCTAssertEqual(progress.pendingScrollPaths.count, 2)
    }

    func testEqualContainersAtDifferentPathsHaveIndependentExplorationState() {
        var progress = Navigation.InterfaceExplorationProgress(maxScrollsPerContainer: 1, maxScrollsPerDiscovery: 10)
        let container = makeScrollableContainer()
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        progress.addPendingContainers([
            semanticContainer(container, path: firstPath),
            semanticContainer(container, path: secondPath),
        ])

        XCTAssertNil(progress.recordScrollAttempt(in: firstPath))
        XCTAssertEqual(progress.recordScrollAttempt(in: firstPath), .containerScrollLimit)
        XCTAssertNil(progress.recordScrollAttempt(in: secondPath))

        progress.markExplored(firstPath)

        XCTAssertTrue(progress.exploredScrollPaths.contains(firstPath))
        XCTAssertFalse(progress.exploredScrollPaths.contains(secondPath))
        XCTAssertFalse(progress.pendingScrollPaths.contains(firstPath))
        XCTAssertTrue(progress.pendingScrollPaths.contains(secondPath))
    }

    // MARK: - Diagnostics

    func testDiscoveryDiagnosticsReportOmittedContainersAndNextAction() throws {
        var progress = Navigation.InterfaceExplorationProgress(
            maxScrollsPerContainer: 3,
            maxScrollsPerDiscovery: 5
        )
        let container = makeScrollableContainer(
            contentSize: CGSize(width: 320, height: 2_000),
            frame: CGRect(x: 0, y: 0, width: 320, height: 400)
        )
        let screen = InterfaceObservation.makeForTests(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNamesByPath: [TreePath([0]): "main_scroll"],
            firstResponderHeistId: nil,
        )

        progress.markOmitted(TreePath([0]), reason: .discoveryScrollLimit)

        let diagnostics = try XCTUnwrap(
            progress.interfaceDiagnostics(for: screen, includedElementCount: 12).discovery
        )
        let omitted = try XCTUnwrap(diagnostics.omittedContainers.first)

        XCTAssertEqual(diagnostics.state, .limited)
        XCTAssertEqual(diagnostics.reasonCodes, [.discoveryScrollLimit])
        XCTAssertEqual(diagnostics.includedElementCount, 12)
        XCTAssertEqual(diagnostics.maxScrollsPerDiscovery, 5)
        XCTAssertEqual(diagnostics.maxScrollsPerContainer, 3)
        XCTAssertEqual(diagnostics.omittedScrollableContainerCount, 1)
        XCTAssertEqual(omitted.containerName, "main_scroll")
        XCTAssertEqual(omitted.reasonCodes, [.discoveryScrollLimit])
        XCTAssertEqual(omitted.scrollAxis, .vertical)
        XCTAssertEqual(omitted.contentHeight, 2_000)
        XCTAssertTrue(diagnostics.nextAction?.contains("maxScrollsPerDiscovery") == true)
    }

    // MARK: - maxScrollsPerContainer

    func testMaxScrollsPerContainerIsReasonable() {
        XCTAssertEqual(Navigation.InterfaceExplorationProgress.maxScrollsPerContainer, 200)
        XCTAssertEqual(Navigation.InterfaceExplorationProgress.maxScrollsPerDiscovery, 200)
    }
}

#endif
