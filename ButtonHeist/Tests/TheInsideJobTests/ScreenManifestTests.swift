#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
import ButtonHeistSupport
import ButtonHeistTestSupport
@testable import TheInsideJob
import ThePlans
import TheScore

@MainActor
final class ScreenManifestTests: XCTestCase {

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

    func testEmptyManifest() {
        let manifest = Navigation.ScreenManifest()
        XCTAssertTrue(manifest.pendingScrollPaths.isEmpty)
        XCTAssertTrue(manifest.exploredScrollPaths.isEmpty)
        XCTAssertEqual(manifest.scrollCount, 0)
        XCTAssertEqual(manifest.maxScrollsPerContainer, Navigation.ScreenManifest.maxScrollsPerContainer)
        XCTAssertEqual(manifest.maxScrollsPerDiscovery, Navigation.ScreenManifest.maxScrollsPerDiscovery)
    }

    func testManifestAcceptsPerPassScrollLimits() {
        let manifest = Navigation.ScreenManifest(
            maxScrollsPerContainer: 25,
            maxScrollsPerDiscovery: 40
        )

        XCTAssertEqual(manifest.maxScrollsPerContainer, 25)
        XCTAssertEqual(manifest.maxScrollsPerDiscovery, 40)
    }

    func testRecordScrollAttemptCountsAttemptsAndFlagsDiscoveryCap() {
        var manifest = Navigation.ScreenManifest(
            maxScrollsPerContainer: 10,
            maxScrollsPerDiscovery: 2
        )
        let path = TreePath([0])

        XCTAssertNil(manifest.recordScrollAttempt(in: path))
        XCTAssertNil(manifest.recordScrollAttempt(in: path))
        XCTAssertEqual(manifest.recordScrollAttempt(in: path), .discoveryScrollLimit)

        XCTAssertEqual(manifest.scrollCount, 2)
        XCTAssertTrue(manifest.discoveryLimitHit)
    }

    // MARK: - markExplored

    func testMarkExploredMovesFromPendingToExplored() {
        var manifest = Navigation.ScreenManifest()
        let container = makeScrollableContainer()
        let path = TreePath([0])
        manifest.addPendingContainers([semanticContainer(container, path: path)])

        XCTAssertFalse(manifest.pendingScrollPaths.isEmpty)

        manifest.markExplored(path)

        XCTAssertTrue(manifest.pendingScrollPaths.isEmpty)
        XCTAssertTrue(manifest.exploredScrollPaths.contains(path))
    }

    func testMarkOmittedMovesFromPendingToOmittedOnly() {
        var manifest = Navigation.ScreenManifest()
        let container = makeScrollableContainer()
        let path = TreePath([0])
        manifest.addPendingContainers([semanticContainer(container, path: path)])

        manifest.markOmitted(path, reason: .containerScrollLimit)

        XCTAssertFalse(manifest.pendingScrollPaths.contains(path))
        XCTAssertFalse(manifest.exploredScrollPaths.contains(path))
        XCTAssertEqual(manifest.omittedScrollPathReasons[path], [.containerScrollLimit])
    }

    func testOmittedContainerIsNotReaddedToPending() {
        var manifest = Navigation.ScreenManifest()
        let container = makeScrollableContainer()
        let path = TreePath([0])

        manifest.markOmitted(path, reason: .containerScrollLimit)
        manifest.addPendingContainers([semanticContainer(container, path: path)])

        XCTAssertFalse(manifest.pendingScrollPaths.contains(path))
        XCTAssertEqual(manifest.omittedScrollPathReasons[path], [.containerScrollLimit])
    }

    // MARK: - addPendingContainers

    func testAddPendingContainersSkipsAlreadyExplored() {
        var manifest = Navigation.ScreenManifest()
        let container = makeScrollableContainer()
        let path = TreePath([0])
        manifest.markExplored(path)
        manifest.addPendingContainers([semanticContainer(container, path: path)])

        XCTAssertTrue(manifest.pendingScrollPaths.isEmpty,
                      "An already-explored container must not be re-added to pending")
    }

    func testAddPendingContainersAddsNewContainers() {
        var manifest = Navigation.ScreenManifest()
        let containerA = makeScrollableContainer(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let containerB = makeScrollableContainer(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        manifest.addPendingContainers([
            semanticContainer(containerA, path: TreePath([0])),
            semanticContainer(containerB, path: TreePath([1])),
        ])

        XCTAssertEqual(manifest.pendingScrollPaths.count, 2)
    }

    func testEqualContainersAtDifferentPathsHaveIndependentExplorationState() {
        var manifest = Navigation.ScreenManifest(maxScrollsPerContainer: 1, maxScrollsPerDiscovery: 10)
        let container = makeScrollableContainer()
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        manifest.addPendingContainers([
            semanticContainer(container, path: firstPath),
            semanticContainer(container, path: secondPath),
        ])

        XCTAssertNil(manifest.recordScrollAttempt(in: firstPath))
        XCTAssertEqual(manifest.recordScrollAttempt(in: firstPath), .containerScrollLimit)
        XCTAssertNil(manifest.recordScrollAttempt(in: secondPath))

        manifest.markExplored(firstPath)

        XCTAssertTrue(manifest.exploredScrollPaths.contains(firstPath))
        XCTAssertFalse(manifest.exploredScrollPaths.contains(secondPath))
        XCTAssertFalse(manifest.pendingScrollPaths.contains(firstPath))
        XCTAssertTrue(manifest.pendingScrollPaths.contains(secondPath))
    }

    // MARK: - Diagnostics

    func testDiscoveryDiagnosticsReportOmittedContainersAndNextAction() throws {
        var manifest = Navigation.ScreenManifest(
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

        manifest.markOmitted(TreePath([0]), reason: .discoveryScrollLimit)

        let diagnostics = try XCTUnwrap(
            manifest.interfaceDiagnostics(for: screen, includedElementCount: 12).discovery
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

    // MARK: - Scroll Container Scan Machine

    func testScrollContainerScanMachineTransitionScenarios() throws {
        let terminal = Navigation.ScrollTraversalTerminal.foundHeistId("save")
        let scenarios: [StateMachineTestScenario<Navigation.ScrollContainerScanMachine>] = [
            StateMachineTestScenario(
                "forward exhaustion starts backward scan after restore",
                initialState: .idle,
                steps: [
                    StateMachineTestStep(
                        "begin forward scan",
                        event: .begin,
                        expected: .changed(to: .scanning(.forward), effects: [.run(.forward)])
                    ),
                    StateMachineTestStep(
                        "forward scan exhausts",
                        event: .scanCompleted(.exhausted),
                        expected: .changed(to: .restoring(.beforeBackwardScan), effects: [.restore])
                    ),
                    StateMachineTestStep(
                        "restore starts backward scan",
                        event: .restoreCompleted,
                        expected: .changed(to: .scanning(.back), effects: [.run(.back)])
                    ),
                ]
            ),
            StateMachineTestScenario(
                "backward exhaustion restores before completion",
                initialState: .scanning(.back),
                steps: [
                    StateMachineTestStep(
                        "backward scan exhausts",
                        event: .scanCompleted(.exhausted),
                        expected: .changed(to: .restoring(.beforeCompletion), effects: [.restore])
                    ),
                    StateMachineTestStep(
                        "restore completes scan",
                        event: .restoreCompleted,
                        expected: .changed(to: .finished(.completed), effects: [.finish(.completed)])
                    ),
                ]
            ),
            StateMachineTestScenario(
                "limit hit restores before omission",
                initialState: .scanning(.forward),
                steps: [
                    StateMachineTestStep(
                        "scan reaches container limit",
                        event: .scanCompleted(.limitHit(.containerScrollLimit)),
                        expected: .changed(
                            to: .restoring(.beforeOmission(.containerScrollLimit)),
                            effects: [.restore]
                        )
                    ),
                    StateMachineTestStep(
                        "restore reports omission",
                        event: .restoreCompleted,
                        expected: .changed(
                            to: .finished(.omitted(.containerScrollLimit)),
                            effects: [.finish(.omitted(.containerScrollLimit))]
                        )
                    ),
                ]
            ),
            StateMachineTestScenario(
                "terminal result finishes without restore",
                initialState: .scanning(.forward),
                steps: [
                    StateMachineTestStep(
                        "scan finds terminal result",
                        event: .scanCompleted(.terminal(terminal)),
                        expected: .changed(
                            to: .finished(.terminal(terminal)),
                            effects: [.finish(.terminal(terminal))]
                        )
                    ),
                ]
            ),
        ]

        for scenario in scenarios {
            try runStateMachineScenario(scenario, machine: Navigation.ScrollContainerScanMachine())
        }
    }

    // MARK: - maxScrollsPerContainer

    func testMaxScrollsPerContainerIsReasonable() {
        XCTAssertGreaterThan(Navigation.ScreenManifest.maxScrollsPerContainer, 0)
        XCTAssertEqual(Navigation.ScreenManifest.maxScrollsPerContainer, 200)
        XCTAssertGreaterThan(Navigation.ScreenManifest.maxScrollsPerDiscovery, 0)
        XCTAssertEqual(Navigation.ScreenManifest.maxScrollsPerDiscovery, 200)
    }
}

#endif
