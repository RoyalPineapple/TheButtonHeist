import XCTest
@testable import TheScore

final class MinimumMatcherTests: XCTestCase {

    func testBuildAllProducesMatchersThatResolveToTheSameElements() {
        let save = makeElement(label: "Save", identifier: "saveButton", traits: [.button])
        let cancel = makeElement(label: "Cancel", traits: [.button])
        let firstItem = makeElement(label: "Item", traits: [.staticText])
        let secondItem = makeElement(label: "Item", traits: [.staticText])
        let selectedToggle = makeElement(label: "Toggle", traits: [.button, .selected])
        let capture = makeCapture([save, cancel, firstItem, secondItem, selectedToggle])

        let derived = MinimumMatcher.buildAll(in: capture)

        XCTAssertEqual(derived.map(\.element), capture.interface.projectedElements)
        for minimumMatcher in derived {
            let resolved = resolve(minimumMatcher, in: capture)
            XCTAssertEqual(resolved, minimumMatcher.element)
        }
    }

    func testBuildAllUsesTheSmallestDurableMatcherForEachElement() {
        let stableIdentifier = makeElement(label: "Save", identifier: "saveButton", traits: [.button])
        let uniqueLabel = makeElement(label: "Cancel", traits: [.button])
        let labelWithTraits = makeElement(label: "Submit", traits: [.header])
        let sameLabelDifferentRole = makeElement(label: "Submit", traits: [.button])
        let capture = makeCapture([stableIdentifier, uniqueLabel, labelWithTraits, sameLabelDifferentRole])

        let derived = Dictionary(uniqueKeysWithValues: MinimumMatcher.buildAll(in: capture).map { ($0.element, $0) })

        XCTAssertEqual(derived[stableIdentifier]?.predicate, ElementPredicate(identifier: "saveButton"))
        XCTAssertEqual(derived[uniqueLabel]?.predicate, ElementPredicate(label: "Cancel"))
        XCTAssertEqual(derived[labelWithTraits]?.predicate, ElementPredicate(label: "Submit", traits: [.header]))
        XCTAssertEqual(derived[sameLabelDifferentRole]?.predicate, ElementPredicate(label: "Submit", traits: [.button]))
    }

    func testBuildForSingleElementUsesCaptureMembershipAndUniqueness() throws {
        let target = makeElement(label: "Submit", traits: [.button])
        let duplicateLabel = makeElement(label: "Submit", traits: [.header])
        let capture = makeCapture([target, duplicateLabel])

        let minimumMatcher = try XCTUnwrap(MinimumMatcher.build(element: target, in: capture))

        XCTAssertEqual(minimumMatcher.element, target)
        XCTAssertEqual(minimumMatcher.predicate, ElementPredicate(label: "Submit", traits: [.button]))
        XCTAssertNil(minimumMatcher.ordinal)
        XCTAssertEqual(resolve(minimumMatcher, in: capture), target)
    }

    func testBuildForElementOutsideCaptureAppendsElementToUniquenessUniverse() throws {
        let externalElement = makeElement(label: "External", traits: [.button])
        let capture = makeCapture([
            makeElement(label: "Save", traits: [.button]),
        ])

        let minimumMatcher = try XCTUnwrap(MinimumMatcher.build(element: externalElement, in: capture))

        XCTAssertEqual(minimumMatcher.element, externalElement)
        XCTAssertEqual(minimumMatcher.predicate, ElementPredicate(label: "External"))
        XCTAssertNil(minimumMatcher.ordinal)
        XCTAssertNil(resolve(minimumMatcher, in: capture))
    }

    func testFreshPassResolvesNewConflictIntroducedByMutatedCapture() throws {
        let originalTarget = makeElement(label: "Save", traits: [.button])
        let originalCapture = makeCapture([
            originalTarget,
            makeElement(label: "Cancel", traits: [.button]),
        ])
        let originalMatcher = try XCTUnwrap(MinimumMatcher.build(element: originalTarget, in: originalCapture))

        let mutatedTarget = makeElement(label: "Save", identifier: "primary.save", traits: [.button])
        let newConflict = makeElement(label: "Save", traits: [.button])
        let mutatedCapture = makeCapture([mutatedTarget, newConflict])

        XCTAssertEqual(
            mutatedCapture.interface.projectedElements.filter { $0.matches(originalMatcher.predicate) }.count,
            2,
            "The prior matcher should become ambiguous after the capture mutates."
        )

        let repairedMatcher = try XCTUnwrap(MinimumMatcher.build(element: mutatedTarget, in: mutatedCapture))

        XCTAssertEqual(repairedMatcher.predicate, ElementPredicate(identifier: "primary.save"))
        XCTAssertNil(repairedMatcher.ordinal)
        XCTAssertEqual(resolve(repairedMatcher, in: mutatedCapture), mutatedTarget)
    }

    func testStatePredicatesAreUsedBeforeOrdinal() throws {
        let selected = makeElement(label: "Save", traits: [.button, .selected])
        let unselected = makeElement(label: "Save", traits: [.button])
        let capture = makeCapture([selected, unselected])

        let selectedMatcher = try XCTUnwrap(MinimumMatcher.build(element: selected, in: capture))
        let unselectedMatcher = try XCTUnwrap(MinimumMatcher.build(element: unselected, in: capture))

        XCTAssertEqual(selectedMatcher.predicate, ElementPredicate(label: "Save", traits: [.button, .selected]))
        XCTAssertNil(selectedMatcher.ordinal)
        XCTAssertEqual(unselectedMatcher.predicate, ElementPredicate(
            label: "Save",
            traits: [.button],
            excludeTraits: [.selected]
        ))
        XCTAssertNil(unselectedMatcher.ordinal)
    }

    func testOrdinalIsOnlyUsedAfterAllMatcherPredicatesFailToDisambiguate() throws {
        let stableTarget = makeElement(label: "Save", identifier: "primary.save", traits: [.button])
        let sameLabel = makeElement(label: "Save", traits: [.button])
        let firstAmbiguous = makeElement(label: "Item", traits: [.staticText])
        let secondAmbiguous = makeElement(label: "Item", traits: [.staticText])
        let capture = makeCapture([stableTarget, sameLabel, firstAmbiguous, secondAmbiguous])

        let stableMatcher = try XCTUnwrap(MinimumMatcher.build(element: stableTarget, in: capture))
        let firstOrdinalMatcher = try XCTUnwrap(MinimumMatcher.build(element: firstAmbiguous, in: capture))
        let secondOrdinalMatcher = try XCTUnwrap(MinimumMatcher.build(element: secondAmbiguous, in: capture))

        XCTAssertEqual(stableMatcher.predicate, ElementPredicate(identifier: "primary.save"))
        XCTAssertNil(stableMatcher.ordinal, "Identifier should disambiguate before ordinal selection.")
        XCTAssertEqual(firstOrdinalMatcher.predicate, ElementPredicate(label: "Item", traits: [.staticText]))
        XCTAssertEqual(firstOrdinalMatcher.ordinal, 0)
        XCTAssertEqual(secondOrdinalMatcher.predicate, ElementPredicate(label: "Item", traits: [.staticText]))
        XCTAssertEqual(secondOrdinalMatcher.ordinal, 1)
    }

    func testBuildSkipsUUIDIdentifiers() throws {
        let runtimeIdentifier = "SwiftUI.550E8400-E29B-41D4-A716-446655440000.42"
        let target = makeElement(label: "Proceed", identifier: runtimeIdentifier, traits: [.button])
        let capture = makeCapture([
            target,
            makeElement(label: "Cancel", traits: [.button]),
        ])

        let minimumMatcher = try XCTUnwrap(MinimumMatcher.build(element: target, in: capture))

        XCTAssertNil(minimumMatcher.predicate.identifier)
        XCTAssertEqual(minimumMatcher.predicate.label, "Proceed")
        XCTAssertNil(minimumMatcher.ordinal)
    }

    func testBuildOmitsStateTraitsWhenSemanticTraitsAreUnique() throws {
        let target = makeElement(label: "Toggle", traits: [.button, .selected])
        let capture = makeCapture([
            target,
            makeElement(label: "Toggle", traits: [.staticText]),
        ])

        let minimumMatcher = try XCTUnwrap(MinimumMatcher.build(element: target, in: capture))

        XCTAssertEqual(minimumMatcher.predicate.label, "Toggle")
        XCTAssertEqual(minimumMatcher.predicate.traits, [.button])
        XCTAssertNil(minimumMatcher.ordinal)
    }

    func testBuildUsesValueBeforeOrdinalWhenNeededForCurrentState() {
        let first = makeElement(label: "Slider", value: "50%", traits: [.adjustable])
        let second = makeElement(label: "Slider", value: "75%", traits: [.adjustable])
        let capture = makeCapture([first, second])

        let matchers = MinimumMatcher.buildAll(in: capture)

        XCTAssertEqual(matchers[0].predicate.label, "Slider")
        XCTAssertEqual(matchers[0].predicate.value, "50%")
        XCTAssertEqual(matchers[0].predicate.traits, [.adjustable])
        XCTAssertNil(matchers[0].ordinal)
        XCTAssertEqual(resolve(matchers[0], in: capture), first)
        XCTAssertEqual(resolve(matchers[1], in: capture), second)
    }

    func testBuildUsesValueBeforeStateTraits() throws {
        let first = makeElement(label: "Mode", value: "A", traits: [.button, .selected])
        let second = makeElement(label: "Mode", value: "B", traits: [.button, .selected])
        let capture = makeCapture([first, second])

        let minimumMatcher = try XCTUnwrap(MinimumMatcher.build(element: first, in: capture))

        XCTAssertEqual(minimumMatcher.predicate, ElementPredicate(label: "Mode", value: "A", traits: [.button]))
        XCTAssertNil(minimumMatcher.ordinal)
        XCTAssertEqual(resolve(minimumMatcher, in: capture), first)
    }

    func testAnonymousElementsDoNotProduceDurableMatchers() {
        let first = makeElement()
        let named = makeElement(label: "Save", traits: [.button])
        let second = makeElement()
        let capture = makeCapture([first, named, second])

        XCTAssertNil(MinimumMatcher.build(element: first, in: capture))
        XCTAssertNil(MinimumMatcher.build(element: second, in: capture))
    }

    func testSingleAnonymousElementDoesNotProduceDurableMatcher() {
        let element = makeElement()
        let capture = makeCapture([element])

        XCTAssertNil(MinimumMatcher.build(element: element, in: capture))
    }

    func testDescriptionComposesElementPredicateAndOrdinal() {
        let element = makeElement(label: "Item", traits: [.staticText])
        let minimumMatcher = MinimumMatcher(
            element: element,
            predicate: ElementPredicate(label: "Item", traits: [.staticText]),
            ordinal: 1
        )

        XCTAssertEqual(
            minimumMatcher.description,
            #"minimumMatcher(element="item_2" predicate(label="Item" traits=[staticText]) ordinal=1)"#
        )
    }

    private func resolve(_ minimumMatcher: MinimumMatcher, in capture: AccessibilityTrace.Capture) -> HeistElement? {
        let matches = capture.interface.projectedElements.filter { $0.matches(minimumMatcher.predicate) }
        return matches[safe: minimumMatcher.ordinal ?? 0]
    }

    private func makeCapture(_ elements: [HeistElement]) -> AccessibilityTrace.Capture {
        AccessibilityTrace.Capture(
            sequence: 1,
            interface: makeTestInterface(elements: elements)
        )
    }

    private func makeElement(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = []
    ) -> HeistElement {
        let frameX = 0.0
        let frameY = 0.0
        let frameWidth = 100.0
        let frameHeight = 44.0
        let activationPoint = defaultActivationPoint(
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight
        )
        return HeistElement(
            description: label ?? "element",
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            activationPointX: activationPoint.x,
            activationPointY: activationPoint.y,
            actions: []
        )
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
