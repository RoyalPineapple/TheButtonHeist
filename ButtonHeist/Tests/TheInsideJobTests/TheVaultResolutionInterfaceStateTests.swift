#if canImport(UIKit)
import XCTest
import ThePlans
@testable import AccessibilitySnapshotParser
@testable import TheInsideJob
@testable import TheScore

@MainActor
extension TheVaultResolutionTests {

    // MARK: - Known Semantic State

    /// Matcher-based resolution reads the committed semantic state. Viewport
    /// reachability is handled later by action execution.
    func testMatcherResolvesKnownEntryOutsideLiveHierarchy() async throws {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        await register(onScreen, heistId: "button_visible", index: 0)
        await registerOffScreen(offScreen, heistId: "long_list_button")

        let result = bagman.resolveTarget(try resolvedTarget(
            AccessibilityTarget.element(.label("Long List"), traits: [.button])
        ))
        guard case .resolved(.element(let target)) = result else {
            XCTFail("Expected interface-tree match, got \(result)")
            return
        }
        XCTAssertEqual(target.heistId, "long_list_button")
    }

    func testScopedHeistIdsSeparateVisibleFromKnownUnion() async {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        await register(onScreen, heistId: "button_visible", index: 0)
        await registerOffScreen(offScreen, heistId: "long_list_button")

        XCTAssertEqual(bagman.ids(in: .viewport), ["button_visible"])
        XCTAssertEqual(bagman.ids(in: .interface), ["button_visible", "long_list_button"])
        XCTAssertEqual(bagman.viewportElementIDs, bagman.ids(in: .viewport))
        XCTAssertEqual(bagman.interfaceElementIDs, bagman.ids(in: .interface))
    }

    func testScopedInterfaceElementRequiresViewportScopeForCurrentCapture() async {
        let onScreen = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Long List", traits: .button)
        await register(onScreen, heistId: "button_visible", index: 0)
        await registerOffScreen(offScreen, heistId: "long_list_button")

        XCTAssertNotNil(bagman.treeElement(heistId: "button_visible", in: .viewport))
        XCTAssertNil(bagman.treeElement(heistId: "long_list_button", in: .viewport))
        XCTAssertNotNil(bagman.treeElement(heistId: "long_list_button", in: .interface))
    }

    func testResolveVisibleTargetFailsClosedForAmbiguousMatcher() async {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        await register(save1, heistId: "button_save_1", index: 0)
        await register(save2, heistId: "button_save_2", index: 1)

        let result = bagman.resolveVisibleTarget(literalTarget(ResolvedElementPredicate.label("Save")))

        guard case .ambiguous(let facts) = result else {
            XCTFail("Expected visible ambiguity, got \(result)")
            return
        }
        XCTAssertEqual(facts.elementMatches?.exactMatches.count, 2)
        XCTAssertEqual(facts.resolutionScope, .viewport)
        let diagnostics = result.diagnostics
        XCTAssertTrue(diagnostics.contains("2 elements match"))
    }

    func testResolveVisibleTargetPreservesExplicitOrdinalOutOfRange() async {
        let save = element(label: "Save", traits: .button)
        await register(save, heistId: "button_save", index: 0)

        let result = bagman.resolveVisibleTarget(literalTarget(ResolvedElementPredicate.label("Save"), ordinal: 4))

        guard case .notFound(let facts) = result else {
            XCTFail("Expected ordinal miss, got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .ordinalOutOfRange(requested: 4, matchCount: 1))
        XCTAssertEqual(facts.resolutionScope, .viewport)
        XCTAssertTrue(diagnostics.contains("ordinal 4 requested"))
        XCTAssertTrue(diagnostics.contains("1 match"))
    }

    func testResolveVisibleTargetRequiresLiveHierarchy() async {
        let visible = element(label: "Visible", traits: .button)
        let offScreen = element(label: "Below Fold", traits: .button)
        await register(visible, heistId: "button_visible", index: 0)
        await registerOffScreen(offScreen, heistId: "below_fold_button")

        let knownResult = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Below Fold")))
        XCTAssertEqual(knownResult.resolvedElement?.heistId, "below_fold_button")

        let visibleResult = bagman.resolveVisibleTarget(literalTarget(ResolvedElementPredicate.label("Below Fold")))
        guard case .notFound(let facts) = visibleResult else {
            XCTFail("Expected visible miss, got \(visibleResult)")
            return
        }
        let diagnostics = visibleResult.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertEqual(facts.resolutionScope, .viewport)
        XCTAssertTrue(diagnostics.contains("No match for"))
        XCTAssertTrue(diagnostics.contains("scope: viewport"), "Should identify failed resolution scope: \(diagnostics)")
    }

    func testOffViewportEntryWithStaleObjectIsNotDispatchableUntilInViewport() async {
        let offScreen = element(label: "Below Fold", traits: .button)
        let object = UIAccessibilityElement(accessibilityContainer: NSObject())
        object.accessibilityFrame = CGRect(x: 0, y: 0, width: 100, height: 44)
        object.accessibilityActivationPoint = CGPoint(x: 50, y: 22)
        let scrollView = UIScrollView()
        let containerPath = TreePath([0])
        let elementPath = TreePath([0, 0])
        let scrollContainer = AccessibilityContainer(
            type: .none, scrollableContentSize: AccessibilitySize(width: 320, height: 1_000),
            frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 480)
        )
        let entry = InterfaceTree.Element(
            heistId: "below_fold_button",
            path: elementPath,
            scrollMembership: InterfaceTree.ScrollMembership(containerPath: containerPath, index: nil),
            element: offScreen
        )

        await bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.container(scrollContainer, children: [])],
            firstResponderHeistId: nil,
        ))

        guard let resolved = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Below Fold"))).resolvedElement else {
            XCTFail("Off-viewport entry should still resolve")
            return
        }
        XCTAssertEqual(resolved.heistId, "below_fold_button")
        XCTAssertNil(bagman.treeElement(heistId: "below_fold_button", in: .viewport))
        guard case .objectUnavailable = bagman.resolveLiveActionTarget(for: resolved) else {
            XCTFail("Off-viewport target should not have a live action target")
            return
        }

        await bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.container(scrollContainer, children: [.element(offScreen, traversalIndex: 0)])],
            heistIdsByPath: [elementPath: entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: object, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
        ))

        let refreshed = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Below Fold"))).resolvedElement
        XCTAssertNotNil(bagman.treeElement(heistId: "below_fold_button", in: .viewport))
        guard let refreshed,
              case .resolved(let liveTarget) = bagman.resolveLiveActionTarget(for: refreshed) else {
            XCTFail("Expected refreshed visible target to have live action geometry")
            return
        }
        XCTAssertTrue(AccessibilityActionDispatcher().increment(liveTarget))
    }

    func testLiveGeometryRejectsUnusableAccessibilityCaptureFrame() async {
        let visible = AccessibilityElement.make(
            label: "Visible",
            traits: .button,
            shape: .frame(.zero),
            activationPoint: CGPoint(x: 50, y: 22)
        )
        let object = UIAccessibilityElement(accessibilityContainer: NSObject())
        object.accessibilityFrame = CGRect(x: 0, y: 0, width: 100, height: 44)
        object.accessibilityActivationPoint = CGPoint(x: 50, y: 22)
        let scrollView = UIScrollView()
        let entry = InterfaceTree.Element(
            heistId: "button_visible",
            scrollMembership: nil,
            element: visible
        )
        await bagman.installObservationForTesting(InterfaceObservation.makeForTests(
            elements: [entry.heistId: entry],
            hierarchy: [.element(visible, traversalIndex: 0)],
            heistIdsByPath: [TreePath([0]): entry.heistId],
            elementRefs: [
                entry.heistId: .init(object: object, scrollView: scrollView)
            ],
            firstResponderHeistId: nil,
        ))

        guard let resolved = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Visible"))).resolvedElement else {
            XCTFail("Expected visible target to resolve")
            return
        }
        guard case .geometryUnavailable = bagman.resolveLiveActionTarget(for: resolved) else {
            XCTFail("Expected unusable accessibility capture frame to be rejected as missing live geometry")
            return
        }
    }

    func testResolveTargetFindsKnownMatcherOutsideLiveHierarchy() async {
        let offScreen = element(label: "Below Fold", traits: .button)
        await registerOffScreen(offScreen, heistId: "below_fold_button")

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Below Fold"))).resolvedElement)
    }

    func testResolveTargetFindsLivePredicateInViewport() async {
        let element = element(label: "Visible", traits: .button)
        await register(element, heistId: "visible_button", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Visible"))).resolvedElement)
    }

    func testResolveTargetHonorsExplicitOrdinal() async {
        let save1 = element(label: "Save", value: "draft")
        let save2 = element(label: "Save", value: "final")
        await register(save1, heistId: "button_save_1", index: 0)
        await register(save2, heistId: "button_save_2", index: 1)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Save"), ordinal: 1)).resolvedElement)
        guard case .notFound = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Save"), ordinal: 2)) else {
            XCTFail("Expected out-of-range ordinal to fail closed")
            return
        }
    }

    func testRegisteredElementResolvesWithoutMarkPresented() async {
        let element = element(label: "Combobox", traits: .button)
        await register(element, heistId: "button_combobox", index: 0)

        // Element resolves immediately — no markPresented gate
        let result = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Combobox")))
        XCTAssertNotNil(result.resolvedElement)
    }

}

@MainActor
extension TheVaultResolutionTests {

    // MARK: - Direct InterfaceTree Resolution

    func testDirectInterfaceTreeResolutionPreservesOrdinalsAndDiagnostics() async throws {
        await installMatchingScreen()

        enum ExpectedResolution {
            case resolved(HeistId)
            case ambiguous([HeistId])
            case notFound
            case ordinalOutOfRange(requested: Int, matches: [HeistId])
        }

        struct ResolutionCase {
            let name: String
            let target: ResolvedAccessibilityTarget
            let expected: ExpectedResolution
        }

        let cases = [
            ResolutionCase(
                name: "unique",
                target: literalTarget(ResolvedElementPredicate.label("Done")),
                expected: .resolved("done_button")
            ),
            ResolutionCase(
                name: "ambiguous",
                target: literalTarget(ResolvedElementPredicate.label("Delete")),
                expected: .ambiguous(["delete_first", "delete_second"])
            ),
            ResolutionCase(
                name: "not found",
                target: literalTarget(ResolvedElementPredicate.label("Missing")),
                expected: .notFound
            ),
            ResolutionCase(
                name: "ordinal select",
                target: literalTarget(ResolvedElementPredicate.label("Delete"), ordinal: 1),
                expected: .resolved("delete_second")
            ),
            ResolutionCase(
                name: "ordinal out of range",
                target: literalTarget(ResolvedElementPredicate.label("Delete"), ordinal: 2),
                expected: .ordinalOutOfRange(
                    requested: 2,
                    matches: ["delete_first", "delete_second"]
                )
            ),
        ]

        for testCase in cases {
            let resolution = bagman.resolveTarget(testCase.target)

            switch testCase.expected {
            case .resolved(let expectedId):
                let resolved = try XCTUnwrap(resolution.resolvedElement, testCase.name)
                XCTAssertEqual(resolved.heistId, expectedId, testCase.name)
            case .ambiguous(let expectedIds):
                guard case .ambiguous(let facts) = resolution else {
                    return XCTFail("Expected ambiguous for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(facts.matchedCount, expectedIds.count, testCase.name)
                XCTAssertEqual(facts.elementMatches?.exactMatches.map(\.heistId), expectedIds, testCase.name)
            case .notFound:
                guard case .notFound(let facts) = resolution else {
                    return XCTFail("Expected notFound for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(facts.reason, .noMatches, testCase.name)
                XCTAssertTrue(facts.elementMatches?.exactMatches.isEmpty == true, testCase.name)
            case .ordinalOutOfRange(let requested, let expectedMatches):
                guard case .notFound(let facts) = resolution else {
                    return XCTFail("Expected notFound for \(testCase.name), got \(resolution)")
                }
                XCTAssertEqual(
                    facts.reason,
                    .ordinalOutOfRange(requested: requested, matchCount: expectedMatches.count),
                    testCase.name
                )
                XCTAssertEqual(facts.elementMatches?.exactMatches.map(\.heistId), expectedMatches, testCase.name)
            }
        }
    }

    // MARK: - Exact Default and Explicit Broad Matches

    /// A partial label must return `.notFound`; broad matching is explicit.
    func testSubstringPartialLabelReturnsNotFound() async {
        let save = element(label: "Save Draft", traits: .button)
        await register(save, heistId: "button_save_draft", index: 0)

        let result = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Save")))
        guard case .notFound(let facts) = result else {
            XCTFail("Substring partial must not auto-resolve to exact-or-miss; got \(result)")
            return
        }
        let diagnostics = result.diagnostics
        XCTAssertEqual(facts.reason, .noMatches)
        XCTAssertTrue(diagnostics.contains("Save Draft"),
                      "Diagnostic should surface the available interface evidence: \(diagnostics)")
        XCTAssertFalse(diagnostics.contains("contains-match suggestion"), diagnostics)
    }

    /// A contains predicate is an authored broad match, useful for migrating
    /// KIF `usingLabelContaining` call sites without weakening exact literals.
    func testExplicitContainsLabelResolves() async throws {
        let save = element(label: "Save Draft", traits: .button)
        await register(save, heistId: "button_save_draft", index: 0)

        let result = bagman.resolveTarget(try resolvedTarget(.label(.contains("Save"))))
        guard let resolved = result.resolvedElement else {
            XCTFail("Explicit contains predicate should resolve, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save Draft")
    }

    /// Exact equality (after case-insensitive comparison) still resolves.
    func testExactLabelCaseInsensitiveResolves() async {
        let save = element(label: "Save", traits: .button)
        await register(save, heistId: "button_save", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Save"))).resolvedElement)
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("save"))).resolvedElement)
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("SAVE"))).resolvedElement)
    }

    /// Typography folding still works under exact-or-miss: a label with a smart
    /// apostrophe resolves against an ASCII apostrophe matcher.
    func testTypographyFoldingPreservedUnderExactSemantics() async {
        let dontSkip = element(label: "Don\u{2019}t skip", traits: .button)
        await register(dontSkip, heistId: "button_dont_skip", index: 0)

        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Don't skip"))).resolvedElement)
    }

    /// When two labels share a partial substring, exact must win outright
    /// (no ambiguity). This was Finding 5's regression case.
    func testExactMatchWinsOverPartialSiblings() async {
        let save = element(label: "Save")
        let saveDraft = element(label: "Save Draft")
        await register(save, heistId: "button_save", index: 0)
        await register(saveDraft, heistId: "button_save_draft", index: 1)

        let result = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Save")))
        guard let resolved = result.resolvedElement else {
            XCTFail("Exact match should resolve uniquely, got \(result)")
            return
        }
        XCTAssertEqual(resolved.element.label, "Save")
    }

    /// Near-miss surface for absent semantics: a substring-only match must not
    /// be considered present.
    func testResolveTargetReportsAbsentForSubstringOnlyMatch() async {
        let save = element(label: "Save Draft", traits: .button)
        await register(save, heistId: "button_save_draft", index: 0)

        // "Save" is a substring of "Save Draft" but not equal, so semantic
        // resolution must not report it as present.
        guard case .notFound = bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Save"))) else {
            XCTFail("Expected substring-only matcher to miss")
            return
        }
        // Exact label still resolves to present.
        XCTAssertNotNil(bagman.resolveTarget(literalTarget(ResolvedElementPredicate.label("Save Draft"))).resolvedElement)
    }

    /// Server-side and client-side matchers must agree on the same input.
    /// Regression for Finding 4 (matcher contract drift).
    func testServerAndClientMatchersAgreeOnSameInput() async throws {
        let element = element(label: "Save Draft", value: "x", identifier: "save_btn", traits: .button)
        let matcher = try resolvedPredicate(
            AccessibilityTarget.element(.label("Save Draft"), traits: [.button])
        )

        let serverHit = matcher.matches(element)

        // Client-side: HeistElement.matches uses the same StringMatch configuration.
        let heistElement = HeistElement(
            description: "Save Draft",
            label: "Save Draft",
            value: "x",
            identifier: "save_btn",
            traits: [.button],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )
        let clientHit = heistElement.matches(matcher)

        XCTAssertEqual(serverHit, clientHit, "Server and client must agree on the same matcher input")
        XCTAssertTrue(serverHit, "Both sides must hit on exact label+trait match")

        // Substring partial should miss on BOTH sides now.
        let partial = ResolvedElementPredicate.label("Save")
        XCTAssertFalse(partial.matches(element))
        XCTAssertFalse(heistElement.matches(partial))
    }

    /// Smart-quote labels must produce the same answer on both sides
    /// (Finding 4's typography divergence).
    func testServerAndClientAgreeOnSmartQuoteLabel() async {
        let smart = element(label: "Don\u{2019}t skip")
        let heist = HeistElement(
            description: "x",
            label: "Don\u{2019}t skip",
            value: nil,
            identifier: nil,
            traits: [],
            frameX: 0, frameY: 0, frameWidth: 0, frameHeight: 0,
            actions: []
        )
        let asciiMatcher = ResolvedElementPredicate.label("Don't skip")

        XCTAssertTrue(asciiMatcher.matches(smart))
        XCTAssertTrue(heist.matches(asciiMatcher),
                      "Client-side must fold typography just like server-side")
    }
}

#endif
