#if canImport(UIKit)
import XCTest
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob

@MainActor
final class ScreenManifestTests: XCTestCase {

    // MARK: - Helpers

    private func makeContainer(
        label: String? = nil,
        frame: CGRect = .zero
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .semanticGroup(label: label, value: nil, identifier: nil),
            frame: frame
        )
    }

    private func makeScrollableContainer(
        contentSize: CGSize = CGSize(width: 375, height: 2000),
        frame: CGRect = .zero
    ) -> AccessibilityContainer {
        AccessibilityContainer(
            type: .scrollable(contentSize: contentSize),
            frame: frame
        )
    }

    // MARK: - Initial State

    func testEmptyManifest() {
        let manifest = TheBagman.ScreenManifest()
        XCTAssertEqual(manifest.elementCount, 0)
        XCTAssertTrue(manifest.isComplete)
        XCTAssertEqual(manifest.scrollCount, 0)
        XCTAssertEqual(manifest.skippedContainers, 0)
    }

    // MARK: - recordVisibleElements

    func testRecordVisibleElementsAddsNewIds() {
        var manifest = TheBagman.ScreenManifest()
        manifest.recordVisibleElements(["id-a", "id-b"])

        XCTAssertEqual(manifest.elementCount, 2)
        XCTAssertTrue(manifest.contains("id-a"))
        XCTAssertTrue(manifest.contains("id-b"))
    }

    func testRecordVisibleElementsSkipsDuplicates() {
        var manifest = TheBagman.ScreenManifest()
        manifest.recordVisibleElements(["id-a", "id-b"])
        manifest.recordVisibleElements(["id-b", "id-c"])

        XCTAssertEqual(manifest.elementCount, 3)
    }

    func testRecordVisibleElementsWithContainer() {
        var manifest = TheBagman.ScreenManifest()
        let container = makeScrollableContainer()
        manifest.recordVisibleElements(["id-a"], container: container)

        XCTAssertTrue(manifest.contains("id-a"))
        XCTAssertEqual(manifest.elementContainers["id-a"], container)
    }

    func testRecordVisibleElementsWithoutContainer() {
        var manifest = TheBagman.ScreenManifest()
        manifest.recordVisibleElements(["id-a"])

        XCTAssertTrue(manifest.contains("id-a"))
        XCTAssertTrue(manifest.elementContainers.keys.contains("id-a"), "Key should exist in map")
        let container = manifest.elementContainers["id-a"].flatMap { $0 }
        XCTAssertNil(container, "Container value should be nil when none provided")
    }

    // MARK: - markExplored

    func testMarkExploredRemovesFromPending() {
        var manifest = TheBagman.ScreenManifest()
        let container = makeScrollableContainer()
        manifest.addPendingContainers([container])

        XCTAssertFalse(manifest.isComplete)

        manifest.markExplored(container)

        XCTAssertTrue(manifest.isComplete)
        XCTAssertTrue(manifest.exploredContainers.contains(container))
        XCTAssertTrue(manifest.pendingContainers.isEmpty)
    }

    // MARK: - addPendingContainers

    func testAddPendingContainersSkipsExplored() {
        var manifest = TheBagman.ScreenManifest()
        let container = makeScrollableContainer()
        manifest.markExplored(container)
        manifest.addPendingContainers([container])

        XCTAssertTrue(manifest.pendingContainers.isEmpty)
    }

    func testAddPendingContainersAddsNewContainers() {
        var manifest = TheBagman.ScreenManifest()
        let containerA = makeScrollableContainer(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        let containerB = makeScrollableContainer(frame: CGRect(x: 0, y: 100, width: 100, height: 100))
        manifest.addPendingContainers([containerA, containerB])

        XCTAssertEqual(manifest.pendingContainers.count, 2)
        XCTAssertFalse(manifest.isComplete)
    }

    // MARK: - isComplete

    func testIsCompleteWhenAllPendingExplored() {
        var manifest = TheBagman.ScreenManifest()
        let container = makeScrollableContainer()
        manifest.addPendingContainers([container])

        XCTAssertFalse(manifest.isComplete)

        manifest.markExplored(container)

        XCTAssertTrue(manifest.isComplete)
    }

    // MARK: - contains

    func testContainsReturnsFalseForUnknownId() {
        let manifest = TheBagman.ScreenManifest()
        XCTAssertFalse(manifest.contains("nonexistent"))
    }

    // MARK: - maxScrollsPerContainer

    func testMaxScrollsPerContainerIsReasonable() {
        XCTAssertGreaterThan(TheBagman.ScreenManifest.maxScrollsPerContainer, 0)
        XCTAssertEqual(TheBagman.ScreenManifest.maxScrollsPerContainer, 200)
    }
}

#endif
