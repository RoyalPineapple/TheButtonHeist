import XCTest
import ThePlans
@testable import TheScore

final class MinimumPredicateSelectorTests: XCTestCase {

    func testPredicateCandidatesAreContextFreeAndSorted() {
        let element = makeElement(
            label: "Save",
            identifier: "saveButton",
            value: "Ready",
            traits: [.selected, .button]
        )

        let candidates = predicateCandidates(for: element)

        XCTAssertEqual(candidates.map(\.predicate), [
            ElementPredicate(identifier: "saveButton"),
            ElementPredicate([.identifier("saveButton"), .label("Save")]),
            ElementPredicate([.identifier("saveButton"), .label("Save"), .traits([.button])]),
            ElementPredicate([.identifier("saveButton"), .label("Save"), .traits([.button]), .value("Ready")]),
            ElementPredicate([
                .identifier("saveButton"),
                .label("Save"),
                .traits([.button]),
                .value("Ready"),
                .traits([.selected]),
            ]),
            ElementPredicate([
                .identifier("saveButton"),
                .label("Save"),
                .traits([.button]),
                .value("Ready"),
                .traits([.selected]),
                .excludeTraits([.inactive]),
            ]),
            ElementPredicate([
                .identifier("saveButton"),
                .label("Save"),
                .traits([.button]),
                .value("Ready"),
                .traits([.selected]),
                .excludeTraits([.inactive]),
                .excludeTraits([.isEditing]),
            ]),
            ElementPredicate([
                .identifier("saveButton"),
                .label("Save"),
                .traits([.button]),
                .value("Ready"),
                .traits([.selected]),
                .excludeTraits([.inactive]),
                .excludeTraits([.isEditing]),
                .excludeTraits([.notEnabled]),
            ]),
            ElementPredicate([
                .identifier("saveButton"),
                .label("Save"),
                .traits([.button]),
                .value("Ready"),
                .traits([.selected]),
                .excludeTraits([.inactive]),
                .excludeTraits([.isEditing]),
                .excludeTraits([.notEnabled]),
                .excludeTraits([.updatesFrequently]),
            ]),
            ElementPredicate([
                .identifier("saveButton"),
                .label("Save"),
                .traits([.button]),
                .value("Ready"),
                .traits([.selected]),
                .excludeTraits([.inactive]),
                .excludeTraits([.isEditing]),
                .excludeTraits([.notEnabled]),
                .excludeTraits([.updatesFrequently]),
                .excludeTraits([.visited]),
            ]),
        ])
    }

    func testUniqueIdentifierWins() throws {
        let save = makeElement(label: "Save", identifier: "saveButton", traits: [.button])
        let other = makeElement(label: "Save", traits: [.button])
        let context = makeContext([
            ("save", save),
            ("other", other),
        ])

        let selection = try XCTUnwrap(minimumUniquePredicate(for: id("save"), in: context))

        XCTAssertEqual(selection.target, .predicate(ElementPredicate(identifier: "saveButton")))
        XCTAssertEqual(selection.candidate.tier, .identityOnly)
    }

    func testUniqueLabelWins() throws {
        let save = makeElement(label: "Save", traits: [.button])
        let cancel = makeElement(label: "Cancel", traits: [.button])
        let context = makeContext([
            ("save", save),
            ("cancel", cancel),
        ])

        let selection = try XCTUnwrap(minimumUniquePredicate(for: id("save"), in: context))

        XCTAssertEqual(selection.target, .predicate(ElementPredicate(label: "Save")))
    }

    func testUniquenessChangesWhenDuplicateElementIsAddedToContext() throws {
        let save = makeElement(label: "Save", traits: [.button])
        let initialContext = makeContext([
            ("save", save),
            ("cancel", makeElement(label: "Cancel", traits: [.button])),
        ])
        let duplicateContext = makeContext([
            ("save", save),
            ("duplicate", makeElement(label: "Save", traits: [.button])),
        ])

        let initial = try XCTUnwrap(minimumUniquePredicate(for: id("save"), in: initialContext))
        let duplicate = try XCTUnwrap(minimumUniquePredicate(for: id("save"), in: duplicateContext))

        XCTAssertEqual(initial.target, .predicate(ElementPredicate(label: "Save")))
        XCTAssertEqual(duplicate.target, .predicate(ElementPredicate(label: "Save", traits: [.button]), ordinal: 0))
    }

    func testDuplicateLabelDisambiguatedByIdentityTrait() throws {
        let target = makeElement(label: "Delete", traits: [.button])
        let staticText = makeElement(label: "Delete", traits: [.staticText])
        let context = makeContext([
            ("button", target),
            ("text", staticText),
        ])

        let selection = try XCTUnwrap(minimumUniquePredicate(for: id("button"), in: context))

        XCTAssertEqual(selection.target, .predicate(ElementPredicate(label: "Delete", traits: [.button])))
        XCTAssertEqual(selection.candidate.tier, .identityOnly)
    }

    func testDuplicateIdentityDisambiguatedByState() throws {
        let visa = makeElement(label: "Payment Method", value: "Visa")
        let cash = makeElement(label: "Payment Method", value: "Cash")
        let context = makeContext([
            ("visa", visa),
            ("cash", cash),
        ])

        let selection = try XCTUnwrap(minimumUniquePredicate(for: id("visa"), in: context))

        XCTAssertEqual(selection.target, .predicate(ElementPredicate(label: "Payment Method", value: "Visa")))
        XCTAssertEqual(selection.candidate.tier, .identityWithState)
    }

    func testStateOnlyDisambiguation() throws {
        let selected = makeElement(traits: [.selected])
        let notSelected = makeElement()
        let context = makeContext([
            ("selected", selected),
            ("notSelected", notSelected),
        ])

        let selection = try XCTUnwrap(minimumUniquePredicate(for: id("selected"), in: context))

        XCTAssertEqual(selection.target, .predicate(ElementPredicate(traits: [.selected])))
        XCTAssertEqual(selection.candidate.tier, .stateOnly)
    }

    func testOrdinalDisambiguationUsesStrongestSemanticCandidate() throws {
        let first = makeElement(label: "Delete", traits: [.button])
        let second = makeElement(label: "Delete", traits: [.button])
        let context = makeContext([
            ("first", first),
            ("second", second),
        ])

        let firstSelection = try XCTUnwrap(minimumUniquePredicate(for: id("first"), in: context))
        let secondSelection = try XCTUnwrap(minimumUniquePredicate(for: id("second"), in: context))

        XCTAssertEqual(firstSelection.target, .predicate(ElementPredicate(label: "Delete", traits: [.button]), ordinal: 0))
        XCTAssertEqual(firstSelection.candidate.tier, .ordinalDisambiguation)
        XCTAssertEqual(secondSelection.target, .predicate(ElementPredicate(label: "Delete", traits: [.button]), ordinal: 1))
        XCTAssertEqual(secondSelection.candidate.tier, .ordinalDisambiguation)
    }

    func testGeometryIsExcludedFromGeneratedCandidates() {
        let first = makeElement(label: "Item", frameX: 10, frameY: 20, frameWidth: 100, frameHeight: 40)
        let second = makeElement(label: "Item", frameX: 200, frameY: 300, frameWidth: 50, frameHeight: 20)

        XCTAssertEqual(predicateCandidates(for: first), predicateCandidates(for: second))
    }

    func testAnonymousElementHasCandidatesButDoesNotClaimUniquenessWithoutFacts() {
        let context = makeContext([
            ("anonymous", makeElement()),
        ])

        XCTAssertTrue(predicateCandidates(for: makeElement()).isEmpty)
        XCTAssertNil(minimumUniquePredicate(for: id("anonymous"), in: context))
    }

    func testContextMembershipIsRequiredForSelection() {
        let context = makeContext([
            ("save", makeElement(label: "Save")),
        ])

        XCTAssertNil(minimumUniquePredicate(for: id("missing"), in: context))
    }

    private func makeContext(
        _ elements: [(id: String, element: HeistElement)]
    ) -> PredicateSelectionContext {
        PredicateSelectionContext(
            elements: elements.map {
                PredicateSelectionContext.Element(id: id($0.id), element: $0.element)
            },
            screenId: "test_screen",
            semanticHash: "sha256:test",
            scope: .discovery
        )
    }

    private func id(_ rawValue: String) -> PredicateSelectionElementId {
        PredicateSelectionElementId(rawValue: rawValue)
    }

    private func makeElement(
        label: String? = nil,
        identifier: String? = nil,
        value: String? = nil,
        traits: [HeistTrait] = [],
        frameX: Double = 0,
        frameY: Double = 0,
        frameWidth: Double = 100,
        frameHeight: Double = 44
    ) -> HeistElement {
        HeistElement(
            description: label ?? "element",
            label: label,
            value: value,
            identifier: identifier,
            traits: traits,
            frameX: frameX,
            frameY: frameY,
            frameWidth: frameWidth,
            frameHeight: frameHeight,
            actions: []
        )
    }
}
