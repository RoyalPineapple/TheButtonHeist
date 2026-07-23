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
    private var inflation: ElementInflation!

    override func setUp() async throws {
        let tripwire = TheTripwire()
        vault = TheVault(tripwire: tripwire)
        inflation = ElementInflation(
            vault: vault,
            safecracker: TheSafecracker(fingerprintsEnabled: false),
            tripwire: tripwire,
            exploration: ElementInflation.Exploration(
                settleForDiscovery: {},
                discoverTarget: { _ in nil },
                revealKnownTarget: { _ in nil },
                moveViewport: { _ in .unavailable() }
            )
        )
    }

    override func tearDown() async throws {
        vault.semanticObservationStream.stop()
        inflation = nil
        vault = nil
    }

    func testElementTargetResolvesAsElementMatch() async throws {
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (element(label: "Save"), "save_button"),
        ]))

        let resolution = vault.resolveTarget(try resolvedTarget(.label("Save")))

        guard case .resolved(.element(let match)) = resolution else {
            XCTFail("Expected an element match, got \(resolution)")
            return
        }
        XCTAssertEqual(match.heistId, "save_button")
    }

    func testContainerTargetResolvesAsContainerMatch() async throws {
        let path = TreePath([0])
        await installContainers([
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

    func testElementAmbiguityCarriesOnlyElementMatches() async throws {
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
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

    func testElementMissCarriesOnlyElementCandidates() async throws {
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
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

    func testContainerOrdinalMissCarriesOnlyContainerMatches() async throws {
        let firstPath = TreePath([0])
        let secondPath = TreePath([1])
        await installContainers([
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

    func testSemanticAdmissionRemovesTerminalOrdinalWhenSemanticTargetIsUnique() async throws {
        let scrollPath = TreePath([0])
        let selected = InterfaceTree.Element(
            heistId: "save_button",
            path: TreePath([0, 0]),
            scrollMembership: .init(containerPath: scrollPath, index: 4),
            element: element(label: "Save")
        )
        await installTree(
            elements: [selected],
            containers: [container(path: scrollPath, label: "Actions", identifier: "actions")]
        )
        let sourceTarget = try resolvedTarget(.target(.element(.label("Save")), ordinal: 0))
        let expectedTarget = try resolvedTarget(.element(.label("Save")))

        let decision = inflation.admitSemanticTarget(sourceTarget, selectedElement: selected)

        guard case .admitted(let admitted) = decision else {
            return XCTFail("Expected unique semantic target admission, got \(decision)")
        }
        XCTAssertEqual(admitted.target, expectedTarget)
        XCTAssertEqual(admitted.scrollContainerPath, scrollPath)
    }

    func testSemanticAdmissionRejectsOrdinalDependentDuplicate() async throws {
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (element(label: "Save", y: 0), "first_save"),
            (element(label: "Save", y: 50), "second_save"),
        ]))
        let sourceTarget = try resolvedTarget(.target(.element(.label("Save")), ordinal: 1))
        let selected = try XCTUnwrap(vault.interfaceElement(heistId: "second_save"))

        let decision = inflation.admitSemanticTarget(sourceTarget, selectedElement: selected)

        guard case .rejected(.ordinalDependent(let facts)) = decision else {
            return XCTFail("Expected ordinal-dependent rejection, got \(decision)")
        }
        XCTAssertEqual(facts.matchedCount, 2)
    }

    func testSemanticAdmissionRejectsAmbiguousTargetWithoutOrdinal() async throws {
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (element(label: "Save", y: 0), "first_save"),
            (element(label: "Save", y: 50), "second_save"),
        ]))
        let sourceTarget = try resolvedTarget(.element(.label("Save")))
        let selected = try XCTUnwrap(vault.interfaceElement(heistId: "first_save"))

        let decision = inflation.admitSemanticTarget(sourceTarget, selectedElement: selected)

        guard case .rejected(.ambiguous(let facts)) = decision else {
            return XCTFail("Expected ambiguous semantic rejection, got \(decision)")
        }
        XCTAssertEqual(facts.matchedCount, 2)
    }

    func testSemanticAdmissionRejectsMissingTarget() async throws {
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (element(label: "Cancel"), "cancel_button"),
        ]))
        let sourceTarget = try resolvedTarget(.element(.label("Save")))
        let selected = try XCTUnwrap(vault.interfaceElement(heistId: "cancel_button"))

        let decision = inflation.admitSemanticTarget(sourceTarget, selectedElement: selected)

        guard case .rejected(.notFound(let facts)) = decision else {
            return XCTFail("Expected missing semantic rejection, got \(decision)")
        }
        XCTAssertEqual(facts.reason, .noMatches)
    }

    func testSemanticAdmissionRejectsWitnessDifferentFromUniqueMatch() async throws {
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(elements: [
            (element(label: "Save"), "save_button"),
            (element(label: "Cancel"), "cancel_button"),
        ]))
        let sourceTarget = try resolvedTarget(.element(.label("Save")))
        let selected = try XCTUnwrap(vault.interfaceElement(heistId: "cancel_button"))

        let decision = inflation.admitSemanticTarget(sourceTarget, selectedElement: selected)

        XCTAssertSemanticAdmissionRejected(decision, as: .selectedElementMismatch)
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

    private func installContainers(_ containers: [InterfaceTree.Container]) async {
        await installTree(elements: [], containers: containers)
    }

    private func installTree(
        elements: [InterfaceTree.Element],
        containers: [InterfaceTree.Container] = []
    ) async {
        let tree = InterfaceTree(
            elements: Dictionary(uniqueKeysWithValues: elements.map { ($0.heistId, $0) }),
            containers: Dictionary(uniqueKeysWithValues: containers.map { ($0.path, $0) })
        )
        await vault.installObservationForTesting(InterfaceObservation.makeForTests(
            tree: tree,
            liveCapture: .makeForTests()
        ))
    }
}

private func XCTAssertSemanticAdmissionRejected(
    _ decision: ElementInflation.SemanticTargetAdmissionDecision,
    as expected: ElementInflation.SemanticTargetAdmissionRejection,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .rejected(let rejection) = decision else {
        return XCTFail("Expected semantic admission rejection, got \(decision)", file: file, line: line)
    }
    XCTAssertEqual(rejection, expected, file: file, line: line)
}
#endif // canImport(UIKit)
