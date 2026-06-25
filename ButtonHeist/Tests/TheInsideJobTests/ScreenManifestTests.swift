#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
import TheScore

@MainActor
final class ScreenManifestTests: XCTestCase {

    // MARK: - Helpers

    private func makeScrollableContainer(
        contentSize: CGSize = CGSize(width: 375, height: 2000),
        frame: CGRect = .zero
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(contentSize)),
            frame: AccessibilityRect(frame)
        )
    }

    // MARK: - Initial State

    func testEmptyManifest() {
        let manifest = Navigation.ScreenManifest()
        XCTAssertTrue(manifest.pendingContainers.isEmpty)
        XCTAssertTrue(manifest.exploredContainers.isEmpty)
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
        let container = makeScrollableContainer()

        XCTAssertNil(manifest.recordScrollAttempt(in: container))
        XCTAssertNil(manifest.recordScrollAttempt(in: container))
        XCTAssertEqual(manifest.recordScrollAttempt(in: container), .discoveryScrollLimit)

        XCTAssertEqual(manifest.scrollCount, 2)
        XCTAssertTrue(manifest.discoveryLimitHit)
    }

    // MARK: - markExplored

    func testMarkExploredMovesFromPendingToExplored() {
        var manifest = Navigation.ScreenManifest()
        let container = makeScrollableContainer()
        manifest.addPendingContainers([container])

        XCTAssertFalse(manifest.pendingContainers.isEmpty)

        manifest.markExplored(container)

        XCTAssertTrue(manifest.pendingContainers.isEmpty)
        XCTAssertTrue(manifest.exploredContainers.contains(container))
    }

    // MARK: - addPendingContainers

    func testAddPendingContainersSkipsAlreadyExplored() {
        var manifest = Navigation.ScreenManifest()
        let container = makeScrollableContainer()
        manifest.markExplored(container)
        manifest.addPendingContainers([container])

        XCTAssertTrue(manifest.pendingContainers.isEmpty,
                      "An already-explored container must not be re-added to pending")
    }

    func testAddPendingContainersAddsNewContainers() {
        var manifest = Navigation.ScreenManifest()
        let containerA = makeScrollableContainer(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let containerB = makeScrollableContainer(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        manifest.addPendingContainers([containerA, containerB])

        XCTAssertEqual(manifest.pendingContainers.count, 2)
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
        let screen = Screen(
            elements: [:],
            hierarchy: [.container(container, children: [])],
            containerNames: [container: "main_scroll"],
            heistIdByElement: [:],
            firstResponderHeistId: nil,
            scrollableContainerViews: [:]
        )

        manifest.markOmitted(container, reason: .discoveryScrollLimit)

        let diagnostics = try XCTUnwrap(
            manifest.interfaceDiagnostics(for: screen, includedElementCount: 12).discovery
        )
        let omitted = try XCTUnwrap(diagnostics.omittedContainers.first)

        XCTAssertEqual(diagnostics.state, "limited")
        XCTAssertEqual(diagnostics.reasonCodes, ["scroll-attempt-budget"])
        XCTAssertEqual(diagnostics.includedElementCount, 12)
        XCTAssertEqual(diagnostics.maxScrollsPerDiscovery, 5)
        XCTAssertEqual(diagnostics.maxScrollsPerContainer, 3)
        XCTAssertEqual(diagnostics.omittedScrollableContainerCount, 1)
        XCTAssertEqual(omitted.containerName, "main_scroll")
        XCTAssertEqual(omitted.reasonCodes, ["scroll-attempt-budget"])
        XCTAssertEqual(omitted.scrollAxis, .vertical)
        XCTAssertEqual(omitted.contentHeight, 2_000)
        XCTAssertTrue(diagnostics.nextAction?.contains("maxScrollsPerDiscovery") == true)
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
