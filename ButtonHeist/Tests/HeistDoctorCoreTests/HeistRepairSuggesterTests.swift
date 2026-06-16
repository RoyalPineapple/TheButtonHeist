import Foundation
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

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

    @Test("Last success missing target returns no suggestion")
    func lastSuccessMissingTargetReturnsNoSuggestion() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Archive", traits: [.button], actions: [.activate]),
            ]),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ]),
            succeeded: false
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
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

    @Test("Incompatible heist fingerprints return no suggestion")
    func incompatibleHeistFingerprintsReturnNoSuggestion() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            heistFingerprint: "last-plan",
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ]),
            succeeded: true
        )
        let current = evidence(
            heistFingerprint: "different-plan",
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ]),
            succeeded: false
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Current target that still resolves needs no target repair")
    func currentTargetThatStillResolvesNeedsNoTargetRepair() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let before = listInterface(rows: [
            ("Milk", "Delete"),
        ])
        let last = evidence(
            target: target,
            before: before,
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: before,
            succeeded: false,
            expectation: ExpectationResult(met: false, predicate: nil, actual: "Expected item count to change")
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

    @Test("Missing target chooses renamed duplicate by neighbor context")
    func missingTargetChoosesRenamedDuplicateByNeighborContext() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ]),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
                ("Bread", "Remove"),
            ]),
            succeeded: false
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.failureKind == .missingTarget)
        #expect(suggestion.newResolvedElement.label == "Remove")
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
        #expect(suggestion.reasons.contains("Sibling row context is preserved."))
        #expect(resolvedCount(suggestion.newTarget, in: current.beforeSnapshot) == 1)
    }

    @Test("Missing target does not guess from the only compatible role")
    func missingTargetDoesNotGuessFromTheOnlyCompatibleRole() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ]),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Checkout", traits: [.button], actions: [.activate]),
            ]),
            succeeded: false
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Missing target does not use traversal ordinal without matching neighbors")
    func missingTargetDoesNotUseTraversalOrdinalWithoutMatchingNeighbors() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let last = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ]),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: listInterface(rows: [
                ("Bread", "Remove"),
                ("Eggs", "Remove"),
            ]),
            succeeded: false
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Missing target prefers contained label rename over broad screen context")
    func missingTargetPrefersContainedLabelRenameOverBroadScreenContext() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Checkout"))
        let last = evidence(
            target: target,
            before: broadMenuInterface(primaryAction: "Checkout"),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: broadMenuInterface(primaryAction: "Go to Checkout"),
            succeeded: false
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Go to Checkout")))
        #expect(suggestion.newResolvedElement.label == "Go to Checkout")
        #expect(suggestion.reasons.contains("Label is a close semantic rename."))
    }

    @Test("Missing target rejects broad screen context without semantic successor")
    func missingTargetRejectsBroadScreenContextWithoutSemanticSuccessor() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Checkout"))
        let last = evidence(
            target: target,
            before: broadMenuInterface(primaryAction: "Checkout"),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: broadMenuInterface(primaryAction: nil),
            succeeded: false
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
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
        #expect(suggestion.reasons.contains("Sibling row context is preserved."))
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
            before: makeTestInterface(nodes: [
                testContainer(makeTestAccessibilityContainer(), children: [
                    testElement(element(label: "Milk", traits: [.staticText])),
                    testElement(element(
                        label: "Delete",
                        identifier: runtimeIdentifier,
                        traits: [.button],
                        actions: [.activate]
                    )),
                ]),
            ]),
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: makeTestInterface(nodes: [
                testContainer(makeTestAccessibilityContainer(), children: [
                    testElement(element(label: "Milk", traits: [.staticText])),
                    testElement(element(
                        label: "Remove",
                        identifier: runtimeIdentifier,
                        traits: [.button],
                        actions: [.activate]
                    )),
                ]),
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
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ]),
            afterDelta: nil,
            afterSnapshot: afterSnapshot,
            succeeded: true
        )
        let current = evidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ]),
            afterDelta: nil,
            afterSnapshot: nil,
            succeeded: false
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Remove")))
        #expect(suggestion.caveats.contains("Last successful evidence used a full after snapshot because compact diff was unavailable."))
    }

    @Test("Doctor derives suggestions from receipt pair")
    func doctorDerivesSuggestionsFromReceiptPair() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let lastPass = receipt(
            path: "$.body[0]",
            status: .passed,
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Archive"),
            ]),
            after: makeTestInterface(elements: [
                element(label: "Bread", traits: [.staticText]),
                element(label: "Archive", traits: [.button], actions: [.activate]),
            ]),
            actionSucceeded: true
        )
        let newFail = receipt(
            path: "$.body[0]",
            status: .failed,
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
                ("Bread", "Archive"),
            ]),
            after: nil,
            actionSucceeded: false
        )

        let suggestion = try #require(HeistDoctor.suggestions(lastPass: lastPass, newFail: newFail).first)

        #expect(suggestion.stepPath == "$.body[0]")
        #expect(suggestion.failureKind == .missingTarget)
        #expect(suggestion.newTarget == .predicate(ElementPredicate(label: "Remove")))
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
    }

    @Test("Doctor returns an error when no safe successor exists")
    func doctorReturnsErrorWhenNoSafeSuccessorExists() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let lastPass = receipt(
            path: "$.body[0]",
            status: .passed,
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ]),
            after: nil,
            actionSucceeded: true
        )
        let newFail = receipt(
            path: "$.body[0]",
            status: .failed,
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Checkout", traits: [.button], actions: [.activate]),
            ]),
            after: nil,
            actionSucceeded: false
        )

        let reason = noSafeSuggestionReason(lastPass: lastPass, newFail: newFail, expectedPath: "$.body[0]")

        #expect(reason.contains("old target is missing"))
        #expect(reason.contains("semantic continuity"))
    }

    @Test("Doctor returns an error when no target repair is needed")
    func doctorReturnsErrorWhenNoTargetRepairIsNeeded() {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let before = listInterface(rows: [
            ("Milk", "Delete"),
        ])
        let lastPass = receipt(
            path: "$.body[0]",
            status: .passed,
            target: target,
            before: before,
            after: nil,
            actionSucceeded: true
        )
        let newFail = receipt(
            path: "$.body[0]",
            status: .failed,
            target: target,
            before: before,
            after: nil,
            actionSucceeded: false
        )

        let reason = noSafeSuggestionReason(lastPass: lastPass, newFail: newFail, expectedPath: "$.body[0]")

        #expect(reason.contains("old target still resolves"))
        #expect(reason.contains("no target repair needed"))
    }

    @Test("Doctor suggestions do not mutate receipts")
    func doctorSuggestionsDoNotMutateReceipts() throws {
        let target = ElementTarget.predicate(ElementPredicate(label: "Delete"))
        let lastPass = receipt(
            path: "$.body[0]",
            status: .passed,
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ]),
            after: makeTestInterface(elements: [
                element(label: "Done", traits: [.staticText]),
            ]),
            actionSucceeded: true
        )
        let newFail = receipt(
            path: "$.body[0]",
            status: .failed,
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ]),
            after: nil,
            actionSucceeded: false
        )
        let originalLastPass = lastPass
        let originalNewFail = newFail

        _ = try HeistDoctor.suggestions(lastPass: lastPass, newFail: newFail)

        #expect(lastPass == originalLastPass)
        #expect(newFail == originalNewFail)
    }

    private func noSafeSuggestionReason(
        lastPass: HeistExecutionResult,
        newFail: HeistExecutionResult,
        expectedPath: String
    ) -> String {
        do {
            _ = try HeistDoctor.suggestions(lastPass: lastPass, newFail: newFail)
            Issue.record("Expected no safe suggestion error")
            return ""
        } catch let error as HeistDoctorError {
            guard case .noSafeSuggestion(let path, let reason) = error else {
                Issue.record("Expected no safe suggestion error, got \(error)")
                return ""
            }
            #expect(error.errorDescription == error.description)
            #expect(path == expectedPath)
            return reason
        } catch {
            Issue.record("Expected HeistDoctorError, got \(error)")
            return ""
        }
    }

    private func request(
        _ last: HeistStepRepairEvidence,
        _ current: HeistStepRepairEvidence
    ) -> HeistRepairRequest {
        HeistRepairRequest(lastSuccess: last, currentFailure: current)
    }

    private func evidence(
        heistFingerprint: String? = nil,
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
            heistFingerprint: heistFingerprint,
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

    private func broadMenuInterface(primaryAction: String?) -> Interface {
        let itemLabels = [
            "Greek Salad",
            "Margherita Pizza",
            "Garlic Bread",
            "Hummus & Pita",
            "Rice Pilaf",
            "Roasted Vegetables",
            "Tiramisu",
            "Items, 2",
            "Subtotal, US$23.50",
            "Tax (8%), US$1.88",
            "Total, US$25.38",
        ]
        let elements = [
            element(label: "Menu", traits: [.header]),
        ] + itemLabels.map { label in
            element(label: label, traits: [.button], actions: [.activate])
        } + [
            primaryAction.map { element(label: $0, traits: [.button], actions: [.activate]) },
        ].compactMap { $0 }

        return makeTestInterface(elements: elements)
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

    private func receipt(
        path: String,
        status: HeistExecutionStepStatus,
        target: ElementTarget,
        before: Interface,
        after: Interface?,
        actionSucceeded: Bool
    ) -> HeistExecutionResult {
        let trace = after
            .map { AccessibilityTrace(first: before).appending($0) }
            ?? AccessibilityTrace(first: before)
        let step = HeistExecutionStepResult(
            path: path,
            kind: .action,
            status: status,
            durationMs: 1,
            intent: .action(command: "activate", target: target.description),
            evidence: .action(HeistActionEvidence(
                command: .activate(.target(target)),
                actionResult: ActionResult(
                    success: actionSucceeded,
                    method: .activate,
                    message: actionSucceeded ? nil : "No element matching \(target)",
                    errorKind: actionSucceeded ? nil : .elementNotFound,
                    accessibilityTrace: trace
                )
            )),
            failure: status == .failed
                ? HeistFailureDetail(
                    category: .targetResolution,
                    contract: "action dispatch succeeds",
                    observed: "No element matching \(target)",
                    expected: target.description
                )
                : nil
        )
        return HeistExecutionResult(
            steps: [step],
            durationMs: 1,
            abortedAtPath: status == .failed ? path : nil
        )
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
