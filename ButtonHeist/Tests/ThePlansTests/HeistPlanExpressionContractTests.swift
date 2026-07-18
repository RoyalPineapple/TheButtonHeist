import Foundation
import Testing
import ThePlans

@Test func `typed expression leaves resolve through the environment`() throws {
    let title = try HeistReferenceName(validating: "title")
    #expect(title.rawValue == "title")

    let expression = Expr<String>.ref(title)
    #expect(try expression.resolve(in: HeistExecutionEnvironment(strings: [title: "Dashboard"])) == "Dashboard")

    expectExpressionError(.unresolvedStringReference("title")) {
        try expression.resolve(in: .empty)
    }

    let targetReference = try HeistReferenceName(validating: "cta")
    expectExpressionError(.unresolvedTargetReference("cta")) {
        try AccessibilityTarget(ref: targetReference).resolve(in: .empty)
    }
}

@Test func `identifier roles share exact admission at construction and decoding`() throws {
    for value in ["", "  title  ", "target-name", "1target", "class", "Any"] {
        #expect(throws: HeistIdentifierValidationError.self) {
            try HeistPlanName(validating: value)
        }
        #expect(throws: HeistIdentifierValidationError.self) {
            try HeistReferenceName(validating: value)
        }
    }

    expectDecodingError(
        HeistReferenceName.self,
        #""   ""#,
        contains: "Swift-style identifier"
    )
    expectDecodingError(
        AccessibilityTarget.self,
        #"{"ref":"   "}"#,
        contains: "Swift-style identifier"
    )
    expectDecodingError(
        ElementPredicateTemplate.self,
        #"{"checks":[{"kind":"label","match":{"mode":"exact","value":{"ref":"   "}}}]}"#,
        contains: "Swift-style identifier"
    )
}

@Test func `broad string matches reject references that resolve empty`() throws {
    let needle: HeistReferenceName = "needle"
    let labelPredicate = ElementPredicateTemplate(label: .contains(needle))
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try labelPredicate.resolve(in: HeistExecutionEnvironment(strings: [needle: ""]))
    }

    let prefix: HeistReferenceName = "prefix"
    let state = AccessibilityPredicate.exists(.identifier(.prefix(prefix)))
    expectExpressionError(.invalidStringMatch(mode: "prefix")) {
        try state.resolve(in: HeistExecutionEnvironment(strings: [prefix: ""]))
    }

    let titlePart: HeistReferenceName = "titlePart"
    let scopedTarget = AccessibilityTarget.within(
        container: .identifier("Screen"),
        .label(.contains(titlePart))
    )
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try scopedTarget.resolve(in: HeistExecutionEnvironment(strings: [titlePart: ""]))
    }

    let screenID: HeistReferenceName = "screenId"
    let containerTarget = AccessibilityTarget.container(.identifier(screenID), ordinal: 2)
    let resolved = try containerTarget.resolve(
        in: HeistExecutionEnvironment(strings: [screenID: "Checkout"])
    )
    let expected = try AccessibilityTarget.container(.identifier("Checkout"), ordinal: 2).resolve(in: .empty)
    #expect(resolved == expected)

    let fromPart: HeistReferenceName = "fromPart"
    let update = ChangeDeclaration.ElementAssertion.updated(
        .label("Count"),
        .value(before: .contains(fromPart))
    )
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try update.resolve(in: HeistExecutionEnvironment(strings: [fromPart: ""]))
    }
}

@Test func `container predicates reject references that resolve empty`() throws {
    let identifier: HeistReferenceName = "identifier"
    let target = AccessibilityTarget.container(.identifier(identifier))

    #expect(throws: (any Error).self) {
        try target.resolve(in: HeistExecutionEnvironment(strings: [identifier: ""]))
    }
}

@Test func `resolution returns distinct target predicate property and action currencies`() throws {
    let source: ResolvedAccessibilityTarget = try AccessibilityTarget
        .predicate(.label("Submit"), ordinal: 1)
        .resolve(in: .empty)
    let environment = HeistExecutionEnvironment(
        targets: ["sourceTarget": source],
        strings: ["source": "Pay", "item": "outer"]
    )

    let stringScope = try environment.binding(
        argument: .string(reference: "source"),
        to: .string(name: "item")
    )
    #expect(stringScope.strings["item"] == "Pay")
    #expect(stringScope.targets == environment.targets)

    let targetScope = try environment.binding(
        argument: .accessibilityTarget(.ref("sourceTarget")),
        to: .accessibilityTarget(name: "target")
    )
    #expect(targetScope.targets["target"] == source)
    #expect(targetScope.targets["sourceTarget"] == source)

    let sourceReference: HeistReferenceName = "source"
    let change = ElementPropertyChange.value(after: .exact(sourceReference))
    let resolvedChange: ResolvedElementPropertyChange = try change.resolve(in: environment)
    let expectedChange = try ElementPropertyChange.value("Pay").resolve(in: .empty)
    #expect(resolvedChange == expectedChange)

    let command = HeistActionCommand.typeText(
        reference: "source",
        target: .ref("sourceTarget")
    )
    let resolvedCommand: ResolvedHeistActionCommand = try command.resolve(in: environment)
    guard case .typeText(let resolvedTypeText) = resolvedCommand else {
        Issue.record("Expected resolved type text command")
        return
    }
    #expect(resolvedTypeText.text == "Pay")
    #expect(resolvedTypeText.target == source)

    let swipe = HeistActionCommand.mechanicalSwipe(SwipeTarget(
        selection: .elementDirection(.ref("sourceTarget"), .up)
    ))
    guard case .mechanicalSwipe(let resolvedSwipe) = try swipe.resolve(in: environment) else {
        Issue.record("Expected resolved mechanical swipe")
        return
    }
    #expect(resolvedSwipe.selection == .elementDirection(source, .up))
}

@Test func `nested predicate resolution preserves change semantics`() throws {
    let target = AccessibilityTarget.predicate(.identifier("cta"), ordinal: 0)
    let resolvedTarget = try target.resolve(in: .empty)
    let titleReference: HeistReferenceName = "title"
    let valueReference: HeistReferenceName = "valuePart"
    let screenReference: HeistReferenceName = "screenId"
    let expression = AccessibilityPredicate.changed(.screen([
        .exists(.label(.exact(titleReference))),
        .missing(.ref("ctaTarget")),
        .exists(.value(.contains(valueReference))),
        .exists(.container(.identifier(screenReference))),
    ]))

    let environment = HeistExecutionEnvironment(
        targets: ["ctaTarget": resolvedTarget],
        strings: ["title": "Dashboard", "valuePart": "Ready", "screenId": "DashboardScreen"]
    )

    let resolved = try expression.resolve(in: environment)
    let expected = try AccessibilityPredicate.changed(.screen([
        .exists(.label("Dashboard")),
        .missing(target),
        .exists(.value(.contains("Ready"))),
        .exists(.container(.identifier("DashboardScreen"))),
    ])).resolve(in: .empty)

    #expect(resolved == expected)
}

@Test func `authored expression wire shapes remain canonical`() throws {
    let titleReference: HeistReferenceName = "title"
    let template = ElementPredicateTemplate(
        label: .exact(titleReference),
        identifier: .contains("field"),
        value: .exact("Ready")
    )
    let expectedTemplateJSON = """
        {"checks":[{"kind":"label","match":{"mode":"exact","value":{"ref":"title"}}},\
        {"kind":"identifier","match":{"mode":"contains","value":"field"}},\
        {"kind":"value","match":{"mode":"exact","value":"Ready"}}]}
        """
    #expect(try sortedJSON(template) == expectedTemplateJSON)

    #expect(try sortedJSON(AccessibilityTarget.ref("target")) == #"{"ref":"target"}"#)
    #expect(
        try sortedJSON(AccessibilityPredicate.exists(.ref("target"))) ==
        #"{"target":{"ref":"target"},"type":"exists"}"#
    )
    #expect(
        try sortedJSON(AccessibilityPredicate.exists(.container(.label("Checkout")))) ==
        #"{"target":{"container":{"checks":[{"kind":"semantic","semantic":{"kind":"label","# +
        #""match":{"mode":"exact","value":"Checkout"}}}]}},"type":"exists"}"#
    )

    let itemReference: HeistReferenceName = "item"
    let oldReference: HeistReferenceName = "old"
    let change = AccessibilityPredicate.changed(.elements([
        .updated(
            .label(.exact(itemReference)),
            .value(
                before: .exact(oldReference),
                after: .exact("new")
            )
        ),
    ]))
    let expectedChangeJSON = """
        {"assertions":[{"after":{"mode":"exact","value":"new"},\
        "before":{"mode":"exact","value":{"ref":"old"}},\
        "property":"value","target":{"checks":[{"kind":"label","match":{"mode":"exact","value":{"ref":"item"}}}]},\
        "type":"updated"}],"scope":"elements","type":"changed"}
        """
    #expect(try sortedJSON(change) == expectedChangeJSON)
}

@Test func `target construction and refinement preserve authored semantics`() throws {
    let targetBacked = AccessibilityTarget.target(.label("Save"), ordinal: 1)
    let templateBacked = AccessibilityTarget.predicate(
        ElementPredicateTemplate(label: .exact("Save")),
        ordinal: 1
    )
    #expect(targetBacked == templateBacked)

    let refined = targetBacked
        .and(.traits([.isEditing]))
        .excluding(.traits([.textEntry]))
    let expected = AccessibilityTarget.predicate(ElementPredicateTemplate([
        .label("Save"),
        .traits([.isEditing]),
        .exclude(.traits([.textEntry])),
    ]), ordinal: 1)
    #expect(refined == expected)
    #expect(try refined.resolve(in: .empty) == expected.resolve(in: .empty))

    let reference = AccessibilityTarget.ref("row")
    #expect(reference.and(.traits([.isEditing])) == reference)
    #expect(reference.excluding(.traits([.textEntry])) == reference)
}

private func expectExpressionError<T>(
    _ expected: HeistExpressionError,
    _ operation: () throws -> T
) {
    do {
        _ = try operation()
        Issue.record("Expected \(expected)")
    } catch let error as HeistExpressionError {
        #expect(error == expected)
    } catch {
        Issue.record("Expected \(expected), got \(error)")
    }
}

private func expectDecodingError<T: Decodable>(
    _ type: T.Type,
    _ json: String,
    contains expectedMessage: String
) {
    do {
        _ = try JSONDecoder().decode(type, from: Data(json.utf8))
        Issue.record("Expected decoding error containing \(expectedMessage)")
    } catch {
        #expect(String(describing: error).contains(expectedMessage))
    }
}

private func sortedJSON<T: Encodable>(_ value: T) throws -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    return try #require(String(data: data, encoding: .utf8))
}
