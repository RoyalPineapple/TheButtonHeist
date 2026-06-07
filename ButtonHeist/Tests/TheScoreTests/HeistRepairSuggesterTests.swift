import Foundation
import Testing
@testable import TheScore

@Suite struct HeistRepairSuggesterTests {

    @Test("Last success must resolve exactly once")
    func lastSuccessMustResolveExactlyOnce() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ]),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Remove", traits: [.button], actions: [.activate]),
            ]),
            succeeded: false
        )

        #expect(HeistRepairSuggester.suggestions(for: HeistRepairRequest(lastSuccess: last, currentFailure: current)).isEmpty)
    }

    @Test("Evidence must belong to the same failing step")
    func evidenceMustBelongToTheSameFailingStep() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            stepPath: "$.steps[0]",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ]),
            succeeded: true
        )
        let current = evidence(
            stepPath: "$.steps[1]",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Remove", traits: [.button], actions: [.activate]),
            ]),
            succeeded: false
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Missing target suggests renamed equivalent using row context")
    func missingTargetSuggestsRenamedEquivalentUsingRowContext() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Archive"),
            ]),
            afterDelta: .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: 1,
                edits: ElementEdits(removed: [element(label: "Milk", traits: [.staticText])])
            )),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
                ("Bread", "Archive"),
            ]),
            succeeded: false
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.failureKind == .missingTarget)
        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Remove")))
        #expect(suggestion.newResolvedElement.label == "Remove")
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
        #expect(suggestion.confidence == .medium)
        #expect(suggestion.reasons.contains("Sibling row context is preserved."))
    }

    @Test("Ambiguous duplicate labels produce minimum disambiguating matcher")
    func ambiguousDuplicateLabelsProduceMinimumDisambiguatingMatcher() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Archive"),
            ]),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Delete"),
                ("Eggs", "Delete"),
                ("Coffee", "Delete"),
            ]),
            succeeded: false
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.failureKind == .ambiguousTarget)
        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Delete", traits: [.button]), ordinal: 0))
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
        #expect(suggestion.confidence == .low)
        #expect(suggestion.caveats.contains("Suggested matcher uses ordinal as last-resort disambiguation."))
        #expect(resolvedCount(suggestion.newTarget, in: current.beforeSnapshot) == 1)
    }

    @Test("Wrong action capability blocks unsupported suggestions")
    func wrongActionCapabilityBlocksUnsupportedSuggestions() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Quantity"))
        let last = evidence(
            actionKind: "increment",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", traits: [.adjustable], actions: [.increment, .decrement]),
            ]),
            succeeded: true
        )
        let current = evidence(
            actionKind: "increment",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", traits: [.staticText], actions: []),
            ]),
            succeeded: false
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Wrong action capability can suggest a compatible successor with lowered confidence")
    func wrongActionCapabilityCanSuggestACompatibleSuccessorWithLoweredConfidence() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Quantity"))
        let last = evidence(
            actionKind: "increment",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", value: "1", traits: [.adjustable], actions: [.increment, .decrement]),
            ]),
            succeeded: true
        )
        let current = evidence(
            actionKind: "increment",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", value: "1", traits: [.staticText], actions: []),
                element(label: "Quantity stepper", value: "1", traits: [.adjustable], actions: [.increment, .decrement]),
            ]),
            succeeded: false
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.failureKind == .wrongCapability)
        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Quantity stepper")))
        #expect(suggestion.confidence == .low)
        #expect(suggestion.reasons.contains("Element supports the same action family."))
        #expect(resolvedCount(suggestion.newTarget, in: current.beforeSnapshot) == 1)
    }

    @Test("Suggested payload excludes geometry and runtime identifiers")
    func suggestedPayloadExcludesGeometryAndRuntimeIdentifiers() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let runtimeIdentifier = "view-A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let last = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", identifier: runtimeIdentifier, traits: [.button], actions: [.activate]),
            ]),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Remove", identifier: runtimeIdentifier, traits: [.button], actions: [.activate]),
            ]),
            succeeded: false
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)
        let data = try JSONEncoder().encode(suggestion)
        let json = try #require(String(data: data, encoding: .utf8))

        #expect(!json.contains("frameX"))
        #expect(!json.contains("frameY"))
        #expect(!json.contains("activationPoint"))
        #expect(!json.contains("capture"))
        #expect(!json.contains("containerHandle"))
        #expect(!json.contains(runtimeIdentifier))
        #expect(suggestion.newResolvedElement.identifier == nil)
        #expect(resolvedCount(suggestion.newTarget, in: current.beforeSnapshot) == 1)
    }

    @Test("After diff explains value changes without requiring full after snapshot")
    func afterDiffExplainsValueChangesWithoutRequiringFullAfterSnapshot() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Quantity"))
        let changed = element(label: "Quantity", value: "2", traits: [.staticText])
        let last = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", value: "1", traits: [.button], actions: [.activate]),
            ]),
            afterDelta: .elementsChanged(AccessibilityTrace.ElementsChanged(
                elementCount: 1,
                edits: ElementEdits(updated: [
                    ElementUpdate(element: changed, changes: [
                        PropertyChange(property: .value, old: "1", new: "2"),
                    ]),
                ])
            )),
            afterSnapshot: nil,
            succeeded: true,
            expectation: ExpectationResult(met: true, predicate: nil)
        )
        let current = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Amount", value: "1", traits: [.button], actions: [.activate]),
            ]),
            afterDelta: .noChange(AccessibilityTrace.NoChange(elementCount: 1)),
            afterSnapshot: nil,
            succeeded: false,
            expectation: ExpectationResult(met: false, predicate: nil, actual: "Quantity stayed 1")
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Amount")))
        #expect(suggestion.reasons.contains("Last successful after diff observed value change from 1 to 2."))
        #expect(suggestion.reasons.contains("Current failure after diff observed no semantic change."))
        #expect(suggestion.reasons.contains("Last successful result met its expectation."))
        #expect(suggestion.reasons.contains("Current failure result did not meet its expectation."))
        #expect(suggestion.caveats.isEmpty)
    }

    @Test("Full after snapshot is optional escalation when compact diff is absent")
    func fullAfterSnapshotIsOptionalEscalationWhenCompactDiffIsAbsent() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let afterSnapshot = makeTestInterface(elements: [
            element(label: "Done", traits: [.staticText]),
        ])
        let last = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ]),
            afterDelta: nil,
            afterSnapshot: afterSnapshot,
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Remove", traits: [.button], actions: [.activate]),
            ]),
            afterDelta: nil,
            afterSnapshot: nil,
            succeeded: false
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Remove")))
        #expect(suggestion.caveats.contains("Last successful evidence used a full after snapshot because compact diff was unavailable."))
    }

    private func request(
        _ last: HeistStepRepairEvidence,
        _ current: HeistStepRepairEvidence
    ) -> HeistRepairRequest {
        HeistRepairRequest(lastSuccess: last, currentFailure: current)
    }

    private func evidence(
        stepPath: String = "$.steps[0]",
        actionKind: String = "activate",
        target: ElementTarget,
        before: Interface,
        afterDelta: AccessibilityTrace.Delta? = nil,
        afterSnapshot: Interface? = nil,
        succeeded: Bool,
        expectation: ExpectationResult? = nil
    ) -> HeistStepRepairEvidence {
        HeistStepRepairEvidence(
            stepPath: stepPath,
            actionKind: actionKind,
            target: target,
            beforeSnapshot: before,
            afterDelta: afterDelta,
            afterSnapshot: afterSnapshot,
            result: HeistStepRepairResult(
                succeeded: succeeded,
                method: method(for: actionKind),
                errorKind: succeeded ? nil : .elementNotFound,
                expectation: expectation
            )
        )
    }

    private func method(for actionKind: String) -> ActionMethod? {
        switch actionKind {
        case "activate":
            return .activate
        case "increment":
            return .increment
        default:
            return nil
        }
    }

    private func listInterface(rows: [(String, String)]) -> Interface {
        makeTestInterface(nodes: rows.map { title, action in
            testContainer(makeTestAccessibilityContainer(), children: [
                testElement(element(label: title, traits: [.staticText])),
                testElement(element(label: action, traits: [.button], actions: [.activate])),
            ])
        })
    }

    private func resolvedCount(_ target: ElementTarget, in interface: Interface) -> Int {
        let elements = interface.projectedElements
        switch target {
        case .predicate(let predicate, let ordinal):
            let matches = elements.filter { $0.matches(predicate) }
            if let ordinal {
                return matches.indices.contains(ordinal) ? 1 : 0
            }
            return matches.count
        }
    }

    private func element(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = [],
        actions: [ElementAction] = [],
        frameX: Double = 0,
        frameY: Double = 0
    ) -> HeistElement {
        HeistElement(
            description: label ?? "element",
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: 100,
            frameHeight: 44,
            actions: actions
        )
    }
}
