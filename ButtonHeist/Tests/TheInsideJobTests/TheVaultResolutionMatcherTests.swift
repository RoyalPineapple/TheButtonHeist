#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheVaultResolutionTests {

    // MARK: - Matcher Resolution

    func testMatcherResolvesUniqueElement() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard let resolved = result.resolvedElement else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save")
    }

    func testPredicateTargetResolvesExactScreenElement() {
        let save = element(label: "Save", traits: .button)
        let cancel = element(label: "Cancel", traits: .button)
        register(save, heistId: "button_save", index: 0)
        register(cancel, heistId: "button_cancel", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Cancel")))
        guard let resolved = result.resolvedElement else {
            XCTFail("Expected .resolved, got \(result)")
            return
        }
        XCTAssertEqual(resolved.heistId, "button_cancel")
        XCTAssertEqual(resolved.element.label, "Cancel")
    }

    func testNestedScopedTargetResolvesDescendantOfContainerLabels() throws {
        let checkoutContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Checkout", value: nil), identifier: nil,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let cartContainer = AccessibilityContainer(
            type: .semanticGroup(label: "Cart", value: nil), identifier: nil,
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let checkoutActions = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "checkout_actions",
            frame: .zero
        )
        let cartActions = AccessibilityContainer(
            type: .semanticGroup(label: "Actions", value: nil), identifier: "cart_actions",
            frame: .zero
        )
        let checkoutPay = element(label: "Pay", traits: .button)
        let cartPay = element(label: "Pay", traits: .button)
        let checkoutPath = TreePath([0, 0, 0])
        let cartPath = TreePath([1, 0, 0])
        bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [
                "checkout_pay": InterfaceTree.Element(
                    heistId: "checkout_pay",
                    path: checkoutPath,
                    scrollMembership: nil,
                    element: checkoutPay
                ),
                "cart_pay": InterfaceTree.Element(
                    heistId: "cart_pay",
                    path: cartPath,
                    scrollMembership: nil,
                    element: cartPay
                ),
            ],
            hierarchy: [
                .container(checkoutContainer, children: [
                    .container(checkoutActions, children: [.element(checkoutPay, traversalIndex: 0)]),
                ]),
                .container(cartContainer, children: [
                    .container(cartActions, children: [.element(cartPay, traversalIndex: 1)]),
                ]),
            ],
            heistIdsByPath: [
                checkoutPath: "checkout_pay",
                cartPath: "cart_pay",
            ],
            firstResponderHeistId: nil
        ))

        let result = bagman.resolveTarget(try resolvedTarget(
            .within(
                container: .label("Checkout"),
                .within(container: .identifier("checkout_actions"), .label("Pay"))
            )
        ))

        XCTAssertEqual(result.resolvedElement?.heistId, "checkout_pay")
    }

    func testScopedTargetResolutionUsesInterfaceTreeScrollMembership() throws {
        let containerPath = TreePath([30])
        let staleElementPath = TreePath([2])
        let container = AccessibilityContainer(
            type: .semanticGroup(label: "Order Entry", value: nil), identifier: "order_entry_container",
            frame: AccessibilityRect(CGRect(x: 0, y: 0, width: 320, height: 480))
        )
        let reviewSale = element(label: "Review Sale", identifier: "review_sale", traits: .button)
        let observation = InterfaceObservation.makeForTests(
            tree: InterfaceTree(
                elements: [
                    "review_sale": InterfaceTree.Element(
                        heistId: "review_sale",
                        path: staleElementPath,
                        scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: 0),
                        element: reviewSale
                    ),
                ],
                containers: [
                    containerPath: InterfaceTree.Container(
                        container: container,
                        path: containerPath,
                        containerName: "order_entry_container",
                        contentFrame: nil
                    ),
                ]
            ),
            liveCapture: LiveCapture.makeForTests()
        )
        bagman.installObservationForTesting(observation)
        let target = AccessibilityTarget.within(
            container: .identifier("order_entry_container"),
            .identifier("review_sale")
        )
        let resolvedTarget = try resolvedTarget(target)

        XCTAssertEqual(bagman.resolveTarget(resolvedTarget).resolvedElement?.heistId, "review_sale")
    }

    func testMatcherAmbiguousReturnsCandidates() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        let matches = try? XCTUnwrap(facts.elementMatches)
        let candidates = matches?.candidateDescriptions ?? []
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.matchedCount, 2)
        XCTAssertEqual(candidates.count, 2)
        XCTAssertTrue(diagnostics.contains("2 elements match"))
    }

    func testMatcherAmbiguousCandidatesIncludeDetails() {
        let save1 = element(label: "Save", value: "draft", identifier: "save1")
        let save2 = element(label: "Save", value: "final", identifier: "save2")
        register(save1, heistId: "save1", index: 0)
        register(save2, heistId: "save2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        let matches = try? XCTUnwrap(facts.elementMatches)
        let candidates = matches?.candidateDescriptions ?? []
        XCTAssertEqual(matches?.exactMatches[0].element.identifier, "save1")
        XCTAssertEqual(matches?.exactMatches[1].element.identifier, "save2")
        XCTAssertTrue(candidates[0].contains("id=save1"))
        XCTAssertTrue(candidates[1].contains("id=save2"))
        // Candidates are described by their predicate fields (label/identifier/value),
        // not by an agent-facing heistId — that concept was removed.
        XCTAssertTrue(candidates[0].contains("\"Save\""))
        XCTAssertTrue(candidates[0].contains("value=draft"))
        XCTAssertTrue(candidates[0].contains("visible"))
    }

    func testMatcherNoMatchReturnsNotFound() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Cancel")))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("No match for"))
        XCTAssertTrue(diagnostics.contains("Next:"))
        XCTAssertTrue(diagnostics.contains("exact label"))
    }

    func testMatcherNearMissDiagnostics() throws {
        let element = element(label: "Save", value: "draft")
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(try resolvedTarget(
            AccessibilityTarget.label("Save").and(.value("final"))
        ))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("near miss"), "Should show near-miss: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("value"), "Should identify value as divergent field")
    }

    func testMatcherNearMissIncludesOffscreenKnownElement() {
        let visible = element(label: "Visible", traits: .button)
        let offscreen = element(label: "Long List", traits: .button)
        register(visible, heistId: "button_visible", index: 0)
        registerOffScreen(offscreen, heistId: "long_list_button")

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Long")))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("Long List"), "Should suggest off-viewport candidate: \(diagnostics)")
        // The near-miss names the candidate by its label predicate, not by an
        // agent-facing heistId — that concept was removed.
        XCTAssertTrue(diagnostics.contains("label=\"Long List\""), "Should describe candidate by label predicate: \(diagnostics)")
        XCTAssertTrue(diagnostics.contains("offscreen"))
        XCTAssertTrue(diagnostics.contains("unreachable"))
    }

    // MARK: - TargetResolution Algebra

    func testMissingTargetIsNotFound() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("nope")))
        guard case .notFound = result else {
            return XCTFail("Expected .notFound, got \(result)")
        }
    }

    func testDuplicateTargetsAreAmbiguous() {
        let save1 = element(label: "Save")
        let save2 = element(label: "Save")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .ambiguous = result else {
            return XCTFail("Expected .ambiguous, got \(result)")
        }
    }

    func testDiagnosticsEmptyForResolved() {
        let element = element(label: "OK", traits: .button)
        register(element, heistId: "button_ok", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("OK")))
        XCTAssertEqual(result.diagnostics, "")
    }

    // MARK: - Ambiguous Matcher Diagnostics

    func testAmbiguousMatcherReturnsDiagnostics() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        XCTAssertTrue(result.diagnostics.contains("2 elements match"), "Should return ambiguous message: \(result.diagnostics)")
    }

    func testEmptyScreenReturnsCompactSummary() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Anything")))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("interface hierarchy is empty"))
        XCTAssertTrue(diagnostics.contains("Next:"))
    }

    // MARK: - Ordinal Selection

    func testOrdinalSelectsNthMatch() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        let save3 = element(label: "Save", value: "archive")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)
        register(save3, heistId: "button_save_3", index: 2)

        let result0 = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 0))
        XCTAssertEqual(result0.resolvedElement?.element.value, "draft")

        let result1 = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 1))
        XCTAssertEqual(result1.resolvedElement?.element.value, "final")

        let result2 = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 2))
        XCTAssertEqual(result2.resolvedElement?.element.value, "archive")
    }

    func testOrdinalOutOfBoundsReturnsNotFound() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 5))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: 5, matchCount: 2))
        XCTAssertTrue(diagnostics.contains("ordinal 5 requested"))
        XCTAssertTrue(diagnostics.contains("2 matches"))
        XCTAssertTrue(diagnostics.contains("Next:"))
        XCTAssertTrue(diagnostics.contains("ordinal 0...1"))
    }

    func testOrdinalNilPreservesAmbiguousBehavior() {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        register(save1, heistId: "button_save_1", index: 0)
        register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.matchedCount, 2)
        XCTAssertTrue(diagnostics.contains("2 elements match"))
        XCTAssertTrue(diagnostics.contains("ordinal"), "Should hint about ordinal usage")
    }

    func testAmbiguousMatchedCountIsExactBeyondDisplayedCandidateLimit() {
        for index in 0..<12 {
            register(
                element(label: "Duplicate", value: "\(index)"),
                heistId: HeistId(rawValue: "duplicate_\(index)"),
                index: index
            )
        }

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Duplicate")))
        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected .ambiguous, got \(result)")
            return
        }
        XCTAssertEqual(facts.matchedCount, 12)
        XCTAssertEqual(facts.elementMatches?.exactMatches.count, 12)
        XCTAssertTrue(result.diagnostics.contains("10+ elements match"))
        XCTAssertTrue(result.diagnostics.contains("... and more"))
    }

    func testOrdinalZeroOnSingleMatchSucceeds() {
        let element = element(label: "Save", traits: .button)
        register(element, heistId: "button_save", index: 0)

        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Save"), ordinal: 0))
        XCTAssertNotNil(result.resolvedElement)
        XCTAssertEqual(result.resolvedElement?.element.label, "Save")
    }

    func testOrdinalZeroOnNoMatchReturnsNotFound() {
        let result = bagman.resolveTarget(literalTarget(ElementPredicate.label("Nonexistent"), ordinal: 0))
        guard case .notFound(let facts) = result else {
            XCTFail("Expected .notFound, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: 0, matchCount: 0))
        XCTAssertTrue(diagnostics.contains("ordinal 0 requested"))
        XCTAssertTrue(diagnostics.contains("0 matches"))
        XCTAssertTrue(diagnostics.contains("Next:"))
    }

}

private extension TheVault.TargetElementMatches {
    var candidateDescriptions: [String] {
        exactMatches.map {
            TargetResolutionDiagnostics.elementCandidateDescription(
                $0,
                visibleHeistIds: visibleHeistIds
            )
        }
    }
}

#endif
