import XCTest
@testable import TheScore

final class MinimumMatcherTests: XCTestCase {

    func testBuildAllProducesMatchersThatResolveToTheSameElements() {
        let save = makeElement(heistId: "save", label: "Save", identifier: "saveButton", traits: [.button])
        let cancel = makeElement(heistId: "cancel", label: "Cancel", traits: [.button])
        let firstItem = makeElement(heistId: "item_1", label: "Item", traits: [.staticText])
        let secondItem = makeElement(heistId: "item_2", label: "Item", traits: [.staticText])
        let selectedToggle = makeElement(heistId: "toggle", label: "Toggle", traits: [.button, .selected])
        let capture = makeCapture([save, cancel, firstItem, secondItem, selectedToggle])

        let derived = MinimumMatcher.buildAll(in: capture)

        XCTAssertEqual(derived.map(\.element), capture.interface.elements)
        for minimumMatcher in derived {
            let resolved = resolve(minimumMatcher, in: capture)
            XCTAssertEqual(resolved, minimumMatcher.element)
        }
    }

    func testBuildAllUsesTheSmallestDurableMatcherForEachElement() {
        let stableIdentifier = makeElement(heistId: "save", label: "Save", identifier: "saveButton", traits: [.button])
        let uniqueLabel = makeElement(heistId: "cancel", label: "Cancel", traits: [.button])
        let labelWithTraits = makeElement(heistId: "section_submit", label: "Submit", traits: [.header])
        let sameLabelDifferentRole = makeElement(heistId: "button_submit", label: "Submit", traits: [.button])
        let capture = makeCapture([stableIdentifier, uniqueLabel, labelWithTraits, sameLabelDifferentRole])

        let derived = Dictionary(uniqueKeysWithValues: MinimumMatcher.buildAll(in: capture).map { ($0.element.heistId, $0) })

        XCTAssertEqual(derived["save"]?.matcher, ElementMatcher(identifier: "saveButton"))
        XCTAssertEqual(derived["cancel"]?.matcher, ElementMatcher(label: "Cancel"))
        XCTAssertEqual(derived["section_submit"]?.matcher, ElementMatcher(label: "Submit", traits: [.header]))
        XCTAssertEqual(derived["button_submit"]?.matcher, ElementMatcher(label: "Submit", traits: [.button]))
    }

    func testBuildForSingleElementUsesCaptureMembershipAndUniqueness() {
        let target = makeElement(heistId: "submit", label: "Submit", traits: [.button])
        let duplicateLabel = makeElement(heistId: "heading", label: "Submit", traits: [.header])
        let capture = makeCapture([target, duplicateLabel])

        let minimumMatcher = MinimumMatcher.build(element: target, in: capture)

        XCTAssertEqual(minimumMatcher.element, target)
        XCTAssertEqual(minimumMatcher.matcher, ElementMatcher(label: "Submit", traits: [.button]))
        XCTAssertNil(minimumMatcher.ordinal)
        XCTAssertEqual(resolve(minimumMatcher, in: capture), target)
    }

    func testFreshPassResolvesNewConflictIntroducedByMutatedCapture() {
        let originalTarget = makeElement(heistId: "save", label: "Save", traits: [.button])
        let originalCapture = makeCapture([
            originalTarget,
            makeElement(heistId: "cancel", label: "Cancel", traits: [.button]),
        ])
        let originalMatcher = MinimumMatcher.build(element: originalTarget, in: originalCapture)

        let mutatedTarget = makeElement(heistId: "save", label: "Save", identifier: "primary.save", traits: [.button])
        let newConflict = makeElement(heistId: "secondary_save", label: "Save", traits: [.button])
        let mutatedCapture = makeCapture([mutatedTarget, newConflict])

        XCTAssertEqual(
            mutatedCapture.interface.elements.filter { $0.matches(originalMatcher.matcher) }.count,
            2,
            "The old matcher should become ambiguous after the capture mutates."
        )

        let repairedMatcher = MinimumMatcher.build(element: mutatedTarget, in: mutatedCapture)

        XCTAssertEqual(repairedMatcher.matcher, ElementMatcher(identifier: "primary.save"))
        XCTAssertNil(repairedMatcher.ordinal)
        XCTAssertEqual(resolve(repairedMatcher, in: mutatedCapture), mutatedTarget)
    }

    func testStatePredicatesAreUsedBeforeOrdinal() {
        let selected = makeElement(heistId: "primary_save", label: "Save", traits: [.button, .selected])
        let unselected = makeElement(heistId: "secondary_save", label: "Save", traits: [.button])
        let capture = makeCapture([selected, unselected])

        let selectedMatcher = MinimumMatcher.build(element: selected, in: capture)
        let unselectedMatcher = MinimumMatcher.build(element: unselected, in: capture)

        XCTAssertEqual(selectedMatcher.matcher, ElementMatcher(label: "Save", traits: [.button, .selected]))
        XCTAssertNil(selectedMatcher.ordinal)
        XCTAssertEqual(unselectedMatcher.matcher, ElementMatcher(
            label: "Save",
            traits: [.button],
            excludeTraits: [.selected]
        ))
        XCTAssertNil(unselectedMatcher.ordinal)
    }

    func testOrdinalIsOnlyUsedAfterAllMatcherPredicatesFailToDisambiguate() {
        let stableTarget = makeElement(heistId: "primary_save", label: "Save", identifier: "primary.save", traits: [.button])
        let sameLabel = makeElement(heistId: "secondary_save", label: "Save", traits: [.button])
        let firstAmbiguous = makeElement(heistId: "item_1", label: "Item", traits: [.staticText])
        let secondAmbiguous = makeElement(heistId: "item_2", label: "Item", traits: [.staticText])
        let capture = makeCapture([stableTarget, sameLabel, firstAmbiguous, secondAmbiguous])

        let stableMatcher = MinimumMatcher.build(element: stableTarget, in: capture)
        let firstFallback = MinimumMatcher.build(element: firstAmbiguous, in: capture)
        let secondFallback = MinimumMatcher.build(element: secondAmbiguous, in: capture)

        XCTAssertEqual(stableMatcher.matcher, ElementMatcher(identifier: "primary.save"))
        XCTAssertNil(stableMatcher.ordinal, "Identifier should disambiguate before ordinal fallback.")
        XCTAssertEqual(firstFallback.matcher, ElementMatcher(label: "Item", traits: [.staticText]))
        XCTAssertEqual(firstFallback.ordinal, 0)
        XCTAssertEqual(secondFallback.matcher, ElementMatcher(label: "Item", traits: [.staticText]))
        XCTAssertEqual(secondFallback.ordinal, 1)
    }

    func testBuildSkipsUUIDIdentifiers() {
        let runtimeIdentifier = "SwiftUI.550E8400-E29B-41D4-A716-446655440000.42"
        let target = makeElement(heistId: "proceed", label: "Proceed", identifier: runtimeIdentifier, traits: [.button])
        let capture = makeCapture([
            target,
            makeElement(heistId: "cancel", label: "Cancel", traits: [.button]),
        ])

        let minimumMatcher = MinimumMatcher.build(element: target, in: capture)

        XCTAssertNil(minimumMatcher.matcher.identifier)
        XCTAssertEqual(minimumMatcher.matcher.label, "Proceed")
        XCTAssertNil(minimumMatcher.ordinal)
    }

    func testBuildOmitsStateTraitsWhenSemanticTraitsAreUnique() {
        let target = makeElement(heistId: "toggle", label: "Toggle", traits: [.button, .selected])
        let capture = makeCapture([
            target,
            makeElement(heistId: "heading", label: "Toggle", traits: [.staticText]),
        ])

        let minimumMatcher = MinimumMatcher.build(element: target, in: capture)

        XCTAssertEqual(minimumMatcher.matcher.label, "Toggle")
        XCTAssertEqual(minimumMatcher.matcher.traits, [.button])
        XCTAssertNil(minimumMatcher.ordinal)
    }

    func testBuildUsesValueBeforeOrdinalWhenNeededForCurrentState() {
        let first = makeElement(heistId: "slider_1", label: "Slider", value: "50%", traits: [.adjustable])
        let second = makeElement(heistId: "slider_2", label: "Slider", value: "75%", traits: [.adjustable])
        let capture = makeCapture([first, second])

        let matchers = MinimumMatcher.buildAll(in: capture)

        XCTAssertEqual(matchers[0].matcher.label, "Slider")
        XCTAssertEqual(matchers[0].matcher.value, "50%")
        XCTAssertEqual(matchers[0].matcher.traits, [.adjustable])
        XCTAssertNil(matchers[0].ordinal)
        XCTAssertEqual(resolve(matchers[0], in: capture), first)
        XCTAssertEqual(resolve(matchers[1], in: capture), second)
    }

    func testBuildUsesValueBeforeStateTraits() {
        let first = makeElement(heistId: "mode_1", label: "Mode", value: "A", traits: [.button, .selected])
        let second = makeElement(heistId: "mode_2", label: "Mode", value: "B", traits: [.button, .selected])
        let capture = makeCapture([first, second])

        let minimumMatcher = MinimumMatcher.build(element: first, in: capture)

        XCTAssertEqual(minimumMatcher.matcher, ElementMatcher(label: "Mode", value: "A", traits: [.button]))
        XCTAssertNil(minimumMatcher.ordinal)
        XCTAssertEqual(resolve(minimumMatcher, in: capture), first)
    }

    private func resolve(_ minimumMatcher: MinimumMatcher, in capture: AccessibilityTrace.Capture) -> HeistElement? {
        let matches = capture.interface.elements.filter { $0.matches(minimumMatcher.matcher) }
        return matches[safe: minimumMatcher.ordinal ?? 0]
    }

    private func makeCapture(_ elements: [HeistElement]) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: 1,
            interface: Interface(
                timestamp: Date(timeIntervalSince1970: 0),
                tree: elements.map(InterfaceNode.element)
            )
        )
    }

    private func makeElement(
        heistId: String,
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        HeistElement(
            heistId: heistId,
            description: label ?? heistId,
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: 0,
            frameY: 0,
            frameWidth: 100,
            frameHeight: 44,
            actions: []
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
