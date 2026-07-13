import ButtonHeistTestSupport
import Foundation
import Testing
import ThePlans
import TheScore
@testable import HeistDoctorCore

private let repairJSONReportFixture = HeistDoctorReport(suggestions: [
    HeistRepairSuggestion(
        stepPath: "$.body[0]",
        failureKind: .missingTarget,
        oldTarget: .predicate(ElementPredicateTemplate(label: "Delete")),
        oldResolvedElement: ElementSummary(
            description: "Delete",
            label: "Delete",
            value: nil,
            identifier: nil,
            hint: nil,
            traits: [.button],
            actions: [.activate],
            rotors: [],
            siblingText: ["Milk"],
            headerText: []
        ),
        newTarget: .predicate(ElementPredicateTemplate(label: "Remove")),
        newResolvedElement: ElementSummary(
            description: "Remove",
            label: "Remove",
            value: nil,
            identifier: nil,
            hint: nil,
            traits: [.button],
            actions: [.activate],
            rotors: [],
            siblingText: ["Milk"],
            headerText: []
        ),
        confidence: .medium,
        reasons: [
            .oldTargetResolvedInLastSuccessfulSnapshot,
            .suggestedMatcherResolvesExactlyOneElement,
        ],
        caveats: []
    ),
])

private let expectedRepairJSONReportJSON = """
{
  "status" : "alpha",
  "suggestions" : [
    {
      "caveats" : [

      ],
      "confidence" : "medium",
      "failureKind" : "missingTarget",
      "newResolvedElement" : {
        "actions" : [
          "activate"
        ],
        "description" : "Remove",
        "headerText" : [

        ],
        "label" : "Remove",
        "rotors" : [

        ],
        "siblingText" : [
          "Milk"
        ],
        "traits" : [
          "button"
        ]
      },
      "newTarget" : {
        "checks" : [
          {
            "kind" : "label",
            "match" : {
              "mode" : "exact",
              "value" : "Remove"
            }
          }
        ]
      },
      "oldResolvedElement" : {
        "actions" : [
          "activate"
        ],
        "description" : "Delete",
        "headerText" : [

        ],
        "label" : "Delete",
        "rotors" : [

        ],
        "siblingText" : [
          "Milk"
        ],
        "traits" : [
          "button"
        ]
      },
      "oldTarget" : {
        "checks" : [
          {
            "kind" : "label",
            "match" : {
              "mode" : "exact",
              "value" : "Delete"
            }
          }
        ]
      },
      "reasons" : [
        {
          "oldTargetResolvedInLastSuccessfulSnapshot" : {

          }
        },
        {
          "suggestedMatcherResolvesExactlyOneElement" : {

          }
        }
      ],
      "stepPath" : "$.body[0]"
    }
  ]
}
"""

@Suite struct HeistRepairSuggesterTests {
    @Test func `container-only targets are refused without element coercion`() {
        let target = AccessibilityTarget.container(.label("Checkout"))
        let interface = makeTestInterface(elements: [
            element(label: "Checkout", traits: [.button], actions: [.activate]),
        ])
        let request = request(
            passedEvidence(target: target, before: interface),
            failedEvidence(target: target, before: interface)
        )

        guard case .refused(let diagnosis) = HeistRepairSuggester.diagnosis(for: request) else {
            Issue.record("Expected container-only target refusal")
            return
        }

        #expect(diagnosis.refusal.stage == .evidenceEligibility)
        #expect(diagnosis.refusal.reason == .containerTargetUnsupported)
        #expect(diagnosis.refusal.message == "container-only targets are not repairable as accessibility elements")
    }

    @Test("Last success must resolve exactly once")
    func lastSuccessMustResolveExactlyOnce() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Remove", traits: [.button], actions: [.activate]),
            ])
        )

        #expect(HeistRepairSuggester.suggestions(for: HeistRepairRequest(lastSuccess: last, currentFailure: current)).isEmpty)
    }

    @Test("Last success missing target returns no suggestion")
    func lastSuccessMissingTargetReturnsNoSuggestion() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Archive", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ])
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Evidence must belong to the same failing step")
    func evidenceMustBelongToTheSameFailingStep() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            stepPath: "$.steps[0]",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            stepPath: "$.steps[1]",
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Remove", traits: [.button], actions: [.activate]),
            ])
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Incompatible heist fingerprints return no suggestion")
    func incompatibleHeistFingerprintsReturnNoSuggestion() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            heistFingerprint: "last-plan",
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ])
        )
        let current = failedEvidence(
            heistFingerprint: "different-plan",
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ])
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Current target that still resolves needs no target repair")
    func currentTargetThatStillResolvesNeedsNoTargetRepair() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let before = listInterface(rows: [
            ("Milk", "Delete"),
        ])
        let last = passedEvidence(
            target: target,
            before: before
        )
        let current = failedEvidence(
            target: target,
            before: before,
            expectation: ExpectationResult(met: false, predicate: nil, actual: "Expected item count to change")
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("No suggestion reason reports no target repair needed")
    func noSuggestionReasonReportsNoTargetRepairNeeded() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let before = listInterface(rows: [
            ("Milk", "Delete"),
        ])
        let last = passedEvidence(
            target: target,
            before: before
        )
        let current = failedEvidence(
            target: target,
            before: before
        )

        let reason = HeistRepairSuggester.noSuggestionReason(for: request(last, current))

        #expect(reason == "old target still resolves and supports the requested action; no target repair needed")
    }

    @Test("No suggestion reason reports missing target without a safe successor")
    func noSuggestionReasonReportsMissingTargetWithoutASafeSuccessor() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Checkout", traits: [.button], actions: [.activate]),
            ])
        )

        let reason = HeistRepairSuggester.noSuggestionReason(for: request(last, current))
        let expectedReason = "old target is missing in the current before snapshot; "
            + "no safe successor satisfied semantic continuity and unique-matcher requirements"

        #expect(reason == expectedReason)
    }

    @Test("Missing target suggests renamed equivalent using row context")
    func missingTargetSuggestsRenamedEquivalentUsingRowContext() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Archive"),
            ]),
            changeFacts: changeFacts(
                before: makeTestInterface(elements: [element(label: "Milk", traits: [.staticText])]),
                after: makeTestInterface(elements: [])
            )
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
                ("Bread", "Archive"),
            ])
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.failureKind == .missingTarget)
        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Remove")))
        #expect(suggestion.newResolvedElement.label == "Remove")
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
        #expect(suggestion.confidence == .medium)
        #expect(suggestion.reasons.contains(.scoring(.siblingRowContextPreserved)))
    }

    @Test func `diagnosis exposes validated suggestion pipeline`() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Archive"),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
                ("Bread", "Archive"),
            ])
        )

        let result = HeistRepairSuggester.diagnosis(for: request(last, current))
        guard case .suggested(let diagnosis) = result else {
            Issue.record("Expected suggested diagnosis")
            return
        }
        let suggestion = try #require(diagnosis.suggestions.first)
        let candidate = try #require(diagnosis.candidates.first)

        #expect(diagnosis.failureKind == .missingTarget)
        #expect(diagnosis.currentMatchCount == 0)
        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Remove")))
        #expect(candidate.source == .semanticContinuityScan)
        #expect(candidate.validation == .suggested(target: suggestion.newTarget, confidence: suggestion.confidence))
        #expect(HeistRepairSuggester.suggestions(for: request(last, current)) == diagnosis.suggestions)
        #expect(HeistRepairSuggester.noSuggestionReason(for: request(last, current)) == nil)
    }

    @Test func `diagnosis exposes typed candidate ranking refusal`() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Checkout", traits: [.button], actions: [.activate]),
            ])
        )

        let result = HeistRepairSuggester.diagnosis(for: request(last, current))
        guard case .refused(let diagnosis) = result else {
            Issue.record("Expected refused diagnosis")
            return
        }
        guard case .eligible(let context) = diagnosis.context else {
            Issue.record("Expected eligible refusal context")
            return
        }
        let refusal = diagnosis.refusal

        #expect(context.candidates.isEmpty)
        #expect(context.failureKind == .missingTarget)
        #expect(refusal.stage == .candidateRanking)
        #expect(refusal.reason == .noCandidateMetScoreThreshold)
        #expect(refusal.message == HeistRepairSuggester.noSuggestionReason(for: request(last, current)))
    }

    @Test("Missing target chooses renamed duplicate by neighbor context")
    func missingTargetChoosesRenamedDuplicateByNeighborContext() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
                ("Bread", "Remove"),
            ])
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.failureKind == .missingTarget)
        #expect(suggestion.newResolvedElement.label == "Remove")
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
        #expect(suggestion.reasons.contains(.scoring(.siblingRowContextPreserved)))
        #expect(resolvedCount(suggestion.newTarget, in: current.beforeSnapshot) == 1)
    }

    @Test("Missing target does not guess from the only compatible role")
    func missingTargetDoesNotGuessFromTheOnlyCompatibleRole() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Checkout", traits: [.button], actions: [.activate]),
            ])
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Missing target does not use traversal ordinal without matching neighbors")
    func missingTargetDoesNotUseTraversalOrdinalWithoutMatchingNeighbors() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Bread", "Remove"),
                ("Eggs", "Remove"),
            ])
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Missing target prefers contained label rename over broad screen context")
    func missingTargetPrefersContainedLabelRenameOverBroadScreenContext() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Checkout"))
        let last = passedEvidence(
            target: target,
            before: broadMenuInterface(primaryAction: "Checkout")
        )
        let current = failedEvidence(
            target: target,
            before: broadMenuInterface(primaryAction: "Go to Checkout")
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Go to Checkout")))
        #expect(suggestion.newResolvedElement.label == "Go to Checkout")
        #expect(suggestion.reasons.contains(.scoring(.labelSemanticRename)))
    }

    @Test("Missing target rejects broad screen context without semantic successor")
    func missingTargetRejectsBroadScreenContextWithoutSemanticSuccessor() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Checkout"))
        let last = passedEvidence(
            target: target,
            before: broadMenuInterface(primaryAction: "Checkout")
        )
        let current = failedEvidence(
            target: target,
            before: broadMenuInterface(primaryAction: nil)
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Ambiguous duplicate labels produce minimum disambiguating matcher")
    func ambiguousDuplicateLabelsProduceMinimumDisambiguatingMatcher() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Archive"),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
                ("Bread", "Delete"),
                ("Eggs", "Delete"),
                ("Coffee", "Delete"),
            ])
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.failureKind == .ambiguousTarget)
        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Delete", traits: [.button]), ordinal: 0))
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
        #expect(suggestion.confidence == .low)
        #expect(suggestion.caveats.contains(.ordinalDisambiguation))
        #expect(suggestion.reasons.contains(.scoring(.siblingRowContextPreserved)))
        #expect(resolvedCount(suggestion.newTarget, in: current.beforeSnapshot) == 1)
    }

    @Test("Wrong action capability blocks unsupported suggestions")
    func wrongActionCapabilityBlocksUnsupportedSuggestions() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Quantity"))
        let last = passedEvidence(
            actionIdentity: HeistRepairActionIdentity(commandType: .increment),
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", traits: [.adjustable], actions: [.increment, .decrement]),
            ])
        )
        let current = failedEvidence(
            actionIdentity: HeistRepairActionIdentity(commandType: .increment),
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", traits: [.staticText], actions: []),
            ])
        )

        #expect(HeistRepairSuggester.suggestions(for: request(last, current)).isEmpty)
    }

    @Test("Wrong action capability can suggest a compatible successor with lowered confidence")
    func wrongActionCapabilityCanSuggestACompatibleSuccessorWithLoweredConfidence() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Quantity"))
        let last = passedEvidence(
            actionIdentity: HeistRepairActionIdentity(commandType: .increment),
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", value: "1", traits: [.adjustable], actions: [.increment, .decrement]),
            ])
        )
        let current = failedEvidence(
            actionIdentity: HeistRepairActionIdentity(commandType: .increment),
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", value: "1", traits: [.staticText], actions: []),
                element(label: "Quantity stepper", value: "1", traits: [.adjustable], actions: [.increment, .decrement]),
            ])
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.failureKind == .wrongCapability)
        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Quantity stepper")))
        #expect(suggestion.confidence == .low)
        #expect(suggestion.reasons.contains(.scoring(.elementSupportsSameActionFamily)))
        #expect(resolvedCount(suggestion.newTarget, in: current.beforeSnapshot) == 1)
    }

    @Test("Suggested payload excludes geometry and runtime identifiers")
    func suggestedPayloadExcludesGeometryAndRuntimeIdentifiers() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let runtimeIdentifier = "view-A1B2C3D4-E5F6-7890-ABCD-EF1234567890"
        let last = passedEvidence(
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
            ])
        )
        let current = failedEvidence(
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
            ])
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

    @Test("JSON report encode shape stays stable")
    func jsonReportEncodeShapeStaysStable() throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        let data = try encoder.encode(repairJSONReportFixture)
        let json = try #require(String(data: data, encoding: .utf8))
        let probe = try JSONProbe(data: data).object()
        let decodedReport = try JSONDecoder().decode(HeistDoctorReport.self, from: data)

        #expect(json == expectedRepairJSONReportJSON)
        #expect(try probe.string("status") == HeistDoctorFeatureStatus.alpha.rawValue)
        try probe.assertRecursivelyMissingKeys(["featureStatus", "action" + "Kind"])
        #expect(decodedReport == repairJSONReportFixture)
    }

    @Test
    func `JSON report rejects legacy feature status key`() {
        let payload = """
        {
          "featureStatus" : "alpha",
          "suggestions" : []
        }
        """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistDoctorReport.self, from: Data(payload.utf8))
        }
    }

    @Test
    func `JSON report rejects unknown feature status`() {
        let payload = """
        {
          "status" : "beta",
          "suggestions" : []
        }
        """

        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(HeistDoctorReport.self, from: Data(payload.utf8))
        }
    }

    @Test("Candidate scoring rejects compatible-only successors without continuity")
    func candidateScoringRejectsCompatibleOnlySuccessorsWithoutContinuity() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Delete", traits: [.button], actions: [.activate]),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Checkout", traits: [.button], actions: [.activate]),
            ])
        )

        let ranked = rankedCandidates(last: last, current: current, failureKind: .missingTarget)

        #expect(ranked.isEmpty)
    }

    @Test("Candidate generation preserves tied best score order")
    func candidateGenerationPreservesTiedBestScoreOrder() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ])
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete item"),
                ("Milk", "Delete item"),
                ("Bread", "Archive"),
            ])
        )

        let ranked = rankedCandidates(last: last, current: current, failureKind: .missingTarget)
        let bestScore = try #require(ranked.first?.score)
        let tiedBest = ranked.prefix { $0.score == bestScore }

        #expect(tiedBest.count == 2)
        #expect(tiedBest.map(\.element.traversalIndex) == [1, 3])
        #expect(tiedBest.allSatisfy { $0.reasons.contains(.labelSemanticRename) })
        #expect(tiedBest.allSatisfy { $0.reasons.contains(.siblingRowContextPreserved) })
    }

    @Test("Ordered change facts explain value changes without requiring full after snapshot")
    func changeFactsExplainValueChangesWithoutRequiringFullAfterSnapshot() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Quantity"))
        let changed = element(label: "Quantity", value: "2", traits: [.staticText])
        let last = passedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Quantity", value: "1", traits: [.button], actions: [.activate]),
            ]),
            changeFacts: changeFacts(
                before: makeTestInterface(elements: [
                    element(label: "Quantity", value: "1", traits: [.button]),
                ]),
                after: makeTestInterface(elements: [changed])
            ),
            expectation: ExpectationResult(met: true, predicate: nil)
        )
        let current = failedEvidence(
            target: target,
            before: makeTestInterface(elements: [
                element(label: "Amount", value: "1", traits: [.button], actions: [.activate]),
            ]),
            changeFacts: [],
            expectation: ExpectationResult(met: false, predicate: nil, actual: "Quantity stayed 1")
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Amount")))
        #expect(suggestion.reasons.contains(.changeFact(.lastSuccess, .valueChange(old: "1", new: "2"))))
        #expect(suggestion.reasons.contains(.changeFact(.currentFailure, .noSemanticChange)))
        #expect(suggestion.reasons.contains(.lastSuccessfulExpectationMet))
        #expect(suggestion.reasons.contains(.currentFailureExpectationUnmet))
        #expect(suggestion.caveats.isEmpty)
    }

    @Test("Screen-boundary repair reasons preserve canonical fact order")
    func screenBoundaryRepairReasonsPreserveCanonicalFactOrder() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let oldScreen = makeTestInterface(elements: [
            element(label: "Delete", traits: [.button], actions: [.activate]),
        ])
        let newScreen = makeTestInterface(elements: [
            element(label: "Remove", traits: [.button], actions: [.activate]),
        ])
        let last = passedEvidence(
            target: target,
            before: oldScreen,
            changeFacts: changeFacts(
                before: oldScreen,
                after: newScreen,
                beforeScreenId: "cart",
                afterScreenId: "checkout"
            )
        )
        let current = failedEvidence(target: target, before: newScreen)

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)
        let factReasons = suggestion.reasons.compactMap { reason -> RepairChangeFactObservation? in
            guard case .changeFact(.lastSuccess, let observation) = reason else { return nil }
            return observation
        }

        #expect(factReasons == [
            .semanticElementsRemoved,
            .screenChange,
            .semanticElementsAdded,
        ])
    }

    @Test("Empty change facts mean no semantic change")
    func emptyChangeFactsMeanNoSemanticChange() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
        let last = passedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Delete"),
            ]),
            changeFacts: []
        )
        let current = failedEvidence(
            target: target,
            before: listInterface(rows: [
                ("Milk", "Remove"),
            ]),
            changeFacts: []
        )

        let suggestion = try #require(HeistRepairSuggester.suggestions(for: request(last, current)).first)

        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Remove")))
        #expect(suggestion.reasons.contains(.changeFact(.lastSuccess, .noSemanticChange)))
        #expect(suggestion.caveats.isEmpty)
    }

    @Test("Doctor derives suggestions from receipt pair")
    func doctorDerivesSuggestionsFromReceiptPair() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
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
        #expect(suggestion.newTarget == .predicate(ElementPredicateTemplate(label: "Remove")))
        #expect(suggestion.newResolvedElement.siblingText == ["Milk"])
    }

    @Test func `doctor repair evidence uses action evidence result meanings`() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Pay"))
        let before = makeTestInterface(elements: [
            element(label: "Pay", traits: [.button], actions: [.activate]),
        ])
        let dispatchAfter = makeTestInterface(elements: [
            element(label: "Processing", traits: [.staticText]),
        ])
        let expectationAfter = makeTestInterface(elements: [
            element(label: "Still Processing", traits: [.staticText]),
        ])
        let dispatchTrace = AccessibilityTrace(first: before).appending(dispatchAfter)
        let expectationTrace = AccessibilityTrace(first: dispatchAfter).appending(expectationAfter)
        let predicate = AccessibilityPredicate<RootContext>.changed(.screen())
        let failure = HeistFailureDetail(
            category: .expectation,
            contract: "action expectation is met",
            observed: "timed out waiting for checkout",
            expected: predicate.description
        )
        let step = HeistExecutionStepResult.failed(
            path: "$.body[0]",
            receiptKind: .action,
            durationMs: 1,
            intent: .action(command: .activate(target)),
            evidence: .expectation(
                command: .activate(target),
                dispatchResult: ActionResult.success(
                    method: .activate,
                    evidence: ActionResultSuccessEvidence(observation: .trace(makeTestTraceEvidence(dispatchTrace, completeness: .incomplete)))
                ),
                expectationResult: ActionResult.failure(
                    method: .wait,
                    errorKind: .timeout,
                    message: "wait timed out",
                    evidence: ActionResultFailureEvidence(observation: .trace(makeTestTraceEvidence(expectationTrace, completeness: .incomplete)))
                ),
                expectation: ExpectationResult(
                    met: false,
                    predicate: predicate,
                    actual: "timed out waiting for checkout"
                )
            ),
            failure: failure
        )

        let repairEvidence = try HeistDoctor.failedRepairEvidence(from: step)

        #expect(repairEvidence.beforeSnapshot == before)
        #expect(repairEvidence.changeFacts == dispatchTrace.changeFacts)
        #expect(repairEvidence.result.method == .activate)
        #expect(repairEvidence.result.errorKind == .timeout)
        #expect(repairEvidence.result.message == "timed out waiting for checkout")
        #expect(repairEvidence.result.expectation?.met == false)
    }

    @Test("Doctor returns an error when no safe successor exists")
    func doctorReturnsErrorWhenNoSafeSuccessorExists() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
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

    @Test func `doctor diagnosis returns typed refusal for valid receipt pair`() throws {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
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

        let result = try HeistDoctor.diagnosis(lastPass: lastPass, newFail: newFail)
        guard case .refused(let diagnosis) = result else {
            Issue.record("Expected refused diagnosis")
            return
        }
        let refusal = diagnosis.refusal

        #expect(refusal.stage == .candidateRanking)
        #expect(refusal.reason == .noCandidateMetScoreThreshold)
        #expect(refusal.message.contains("old target is missing"))
    }

    @Test("Doctor returns an error when no target repair is needed")
    func doctorReturnsErrorWhenNoTargetRepairIsNeeded() {
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
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
        let target = AccessibilityTarget.predicate(ElementPredicateTemplate(label: "Delete"))
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
        _ last: HeistPassedStepRepairEvidence,
        _ current: HeistFailedStepRepairEvidence
    ) -> HeistRepairRequest {
        HeistRepairRequest(lastSuccess: last, currentFailure: current)
    }

    private func rankedCandidates(
        last: HeistPassedStepRepairEvidence,
        current: HeistFailedStepRepairEvidence,
        failureKind: HeistRepairFailureKind
    ) -> [ScoredCandidate] {
        let lastScreen = RepairScreen(interface: last.beforeSnapshot)
        guard case .resolved(let oldResolved, _) = lastScreen.resolve(last.target) else {
            Issue.record("Expected last target to resolve once")
            return []
        }
        let currentScreen = RepairScreen(interface: current.beforeSnapshot)
        let actionFamily = RepairActionFamily(actionIdentity: current.actionIdentity)
        return RepairCandidateGenerator.rankedSuccessorCandidates(
            oldResolved: oldResolved,
            currentScreen: currentScreen,
            preferredCandidates: [],
            failureKind: failureKind,
            actionFamily: actionFamily,
            lastSuccess: last,
            currentFailure: current
        )
    }

    private func passedEvidence(
        heistFingerprint: String? = nil,
        stepPath: String = "$.steps[0]",
        actionIdentity: HeistRepairActionIdentity = HeistRepairActionIdentity(commandType: .activate),
        target: AccessibilityTarget,
        before: Interface,
        changeFacts: [AccessibilityTrace.ChangeFact] = [],
        expectation: ExpectationResult? = nil
    ) -> HeistPassedStepRepairEvidence {
        HeistPassedStepRepairEvidence(
            heistFingerprint: heistFingerprint,
            stepPath: stepPath,
            actionIdentity: actionIdentity,
            target: target,
            beforeSnapshot: before,
            changeFacts: changeFacts,
            result: RepairPassEvidence(
                method: method(for: actionIdentity),
                expectation: expectation
            )
        )
    }

    private func failedEvidence(
        heistFingerprint: String? = nil,
        stepPath: String = "$.steps[0]",
        actionIdentity: HeistRepairActionIdentity = HeistRepairActionIdentity(commandType: .activate),
        target: AccessibilityTarget,
        before: Interface,
        changeFacts: [AccessibilityTrace.ChangeFact] = [],
        expectation: ExpectationResult? = nil
    ) -> HeistFailedStepRepairEvidence {
        HeistFailedStepRepairEvidence(
            heistFingerprint: heistFingerprint,
            stepPath: stepPath,
            actionIdentity: actionIdentity,
            target: target,
            beforeSnapshot: before,
            changeFacts: changeFacts,
            result: RepairFailureEvidence(
                method: method(for: actionIdentity),
                errorKind: .elementNotFound,
                expectation: expectation
            )
        )
    }

    private func changeFacts(
        before: Interface,
        after: Interface,
        beforeScreenId: String? = nil,
        afterScreenId: String? = nil
    ) -> [AccessibilityTrace.ChangeFact] {
        AccessibilityTrace(capture: AccessibilityTrace.Capture(
            sequence: 1,
            interface: before,
            context: AccessibilityTrace.Context(screenId: beforeScreenId)
        ))
        .appending(after, context: AccessibilityTrace.Context(screenId: afterScreenId))
        .changeFacts
    }

    private func method(for actionIdentity: HeistRepairActionIdentity) -> ActionMethod? {
        switch actionIdentity.commandType {
        case .activate:
            return .activate
        case .increment:
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

    private func resolvedCount(_ target: AccessibilityTarget, in interface: Interface) -> Int {
        let elements = interface.projectedElements
        switch target {
        case .predicate(let predicate, let ordinal):
            guard let predicate = try? predicate.resolve(in: .empty) else { return 0 }
            let matches = elements.filter { $0.matches(predicate) }
            if let ordinal {
                return matches.indices.contains(ordinal) ? 1 : 0
            }
            return matches.count
        case .container, .ref, .within:
            return 0
        }
    }

    private func receipt(
        path: String,
        status: HeistExecutionStepStatus,
        target: AccessibilityTarget,
        before: Interface,
        after: Interface?,
        actionSucceeded: Bool
    ) -> HeistExecutionResult {
        let trace = after
            .map { AccessibilityTrace(first: before).appending($0) }
            ?? AccessibilityTrace(first: before)
        let actionResult = if actionSucceeded {
            ActionResult.success(
                method: .activate,
                evidence: ActionResultSuccessEvidence(observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete)))
            )
        } else {
            ActionResult.failure(
                method: .activate,
                errorKind: .elementNotFound,
                message: "No element matching \(target)",
                evidence: ActionResultFailureEvidence(observation: .trace(makeTestTraceEvidence(trace, completeness: .incomplete)))
            )
        }
        let evidence = HeistActionEvidence.dispatch(
            command: .activate(target),
            dispatchResult: actionResult
        )
        let step = status == .failed
            ? HeistExecutionStepResult.failed(
                path: path,
                receiptKind: .action,
                durationMs: 1,
                intent: .action(command: .activate(target)),
                evidence: evidence,
                failure: HeistFailureDetail(
                    category: .targetResolution,
                    contract: "action dispatch succeeds",
                    observed: "No element matching \(target)",
                    expected: target.description
                )
            )
            : HeistExecutionStepResult.passed(
                path: path,
                receiptKind: .action,
                durationMs: 1,
                intent: .action(command: .activate(target)),
                evidence: evidence
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
