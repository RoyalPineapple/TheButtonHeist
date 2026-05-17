#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class ScreenManifestTests: XCTestCase {

    // MARK: - Helpers

    private func makeScrollableContainer(
        contentSize: CGSize = CGSize(width: 375, height: 2000),
        frame: CGRect = .zero
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .scrollable(contentSize: AccessibilitySize(contentSize)),
            frame: frame
        )
    }

    // MARK: - Initial State

    func testEmptyManifest() {
        let manifest = Navigation.ScreenManifest()
        XCTAssertTrue(manifest.pendingContainers.isEmpty)
        XCTAssertTrue(manifest.exploredContainers.isEmpty)
        XCTAssertEqual(manifest.scrollCount, 0)
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

    // MARK: - maxScrollsPerContainer

    func testMaxScrollsPerContainerIsReasonable() {
        XCTAssertGreaterThan(Navigation.ScreenManifest.maxScrollsPerContainer, 0)
        XCTAssertEqual(Navigation.ScreenManifest.maxScrollsPerContainer, 200)
    }
}

#endif
