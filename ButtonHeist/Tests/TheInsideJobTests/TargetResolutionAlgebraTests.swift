#if canImport(UIKit)
import UIKit
import XCTest

import ThePlans
@testable import TheInsideJob
@testable import TheScore

@testable import AccessibilitySnapshotParser

@MainActor
final class TargetResolutionAlgebraTests: XCTestCase {

    private var vault: TheVault!

    override func setUp() async throws {
        vault = TheVault(tripwire: TheTripwire())
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        vault = nil
    }

    func testElementTargetResolvesAsElementMatch() throws {
        vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (element(label: "Save"), "save_button"),
        ]))

        let resolution = vault.resolveTarget(try resolvedTarget(.label("Save")))

        guard case .resolved(.element(let match)) = resolution else {
            XCTFail("Expected an element match, got \(resolution)")
            return
        }
        XCTAssertEqual(match.heistId, "save_button")
    }

    func testContainerTargetResolvesAsContainerMatch() throws {
        let path = TreePath([0])
        installContainers([
            container(path: path, label: "Actions", identifier: "actions"),
        ])

        let resolution = vault.resolveTarget(try resolvedTarget(
            .container(.identifier("actions"))
        ))

        guard case .resolved(.container(let match)) = resolution else {
            XCTFail("Expected a container match, got \(resolution)")
            return
        }
        XCTAssertEqual(match.path, path)
    }

    func testElementAmbiguityCarriesOnlyElementMatches() throws {
        vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (element(label: "Save", y: 0), "first_save"),
            (element(label: "Save", y: 50), "second_save"),
        ]))

        let resolution = vault.resolveTarget(try resolvedTarget(.label("Save")))

        guard case .ambiguous(let facts) = resolution,
              case .elements(let matches) = facts.matchSet else {
            XCTFail("Expected element ambiguity, got \(resolution)")
            return
        }
        XCTAssertEqual(matches.exactMatches.map(\.heistId), ["first_save", "second_save"])
        XCTAssertEqual(facts.matchedCount, 2)
    }

    func testElementMissCarriesOnlyElementCandidates() throws {
        vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (element(label: "Cancel"), "cancel_button"),
        ]))

        let resolution = vault.resolveTarget(try resolvedTarget(.label("Save")))

        guard case .notFound(let facts) = resolution,
              case .elements(let matches) = facts.matchSet else {
            XCTFail("Expected an element miss, got \(resolution)")
            return
        }
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertEqual(matches.candidates.map(\.heistId), ["cancel_button"])
        XCTAssertTrue(matches.exactMatches.isEmpty)
    }

    func testContainerOrdinalMissCarriesOnlyContainerMatches() throws {
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        installContainers([
            container(path: firstPath, label: "Actions", identifier: "primary"),
            container(path: secondPath, label: "Actions", identifier: "secondary"),
        ])
        let predicate = ContainerPredicate.matching(
            .type(.semanticGroup),
            .semantic(.label("Actions"))
        )

        let resolution = vault.resolveTarget(try resolvedTarget(
            .container(predicate, ordinal: 3)
        ))

        guard case .notFound(let facts) = resolution,
              case .containers(let matches) = facts.matchSet else {
            XCTFail("Expected container ordinal miss, got \(resolution)")
            return
        }
        XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: 3, matchCount: 2))
        XCTAssertEqual(matches.exactMatches.map(\.path), [firstPath, secondPath])
    }

    private func resolvedTarget(_ target: AccessibilityTarget) throws -> ResolvedAccessibilityTarget {
        try target.resolve(in: .empty)
    }

    private func element(label: String, y: CGFloat = 0) -> AccessibilityElement {
        .make(
            label: label,
            shape: .frame(AccessibilityRect(CGRect(x: 0, y: y, width: 100, height: 44)))
        )
    }

    private func container(
        path: TreePath,
        label: String,
        identifier: String
    ) -> InterfaceTree.Container {
        InterfaceTree.Container(
            container: AccessibilityContainer(
                type: .semanticGroup(label: label, value: nil),
                identifier: identifier,
                frame: AccessibilityRect(CGRect(
                    x: 0,
                    y: CGFloat(path.indices.first ?? 0),
                    width: 200,
                    height: 80
                ))
            ),
            path: path,
            containerName: nil,
            contentFrame: nil
        )
    }

    private func installContainers(_ containers: [InterfaceTree.Container]) {
        let tree = InterfaceTree(
            elements: [:],
            containers: Dictionary(uniqueKeysWithValues: containers.map { ($0.path, $0) })
        )
        vault.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: tree,
            liveCapture: .makeForTests()
        ))
    }
}
#endif // canImport(UIKit)
