import Foundation
import Testing
import ThePlans

@Test
func `unresolved expression refs throw typed errors`() throws {
    expectExpressionError(.unresolvedStringReference("missing")) {
        try StringExpr(ref: HeistReferenceName(rawValue: "missing")).resolve(in: .empty)
    }

    expectExpressionError(.unresolvedTargetReference("missing")) {
        try AccessibilityTarget(ref: HeistReferenceName(rawValue: "missing")).resolve(in: .empty)
    }

    let predicate = ElementPredicateTemplate(label: .exact(.ref("label")))
    expectExpressionError(.unresolvedStringReference("label")) {
        try predicate.resolve(in: .empty)
    }
}

@Test
func `empty refs are rejected at expression boundaries`() throws {
    expectExpressionError(.emptyReference("string")) {
        try StringExpr(ref: HeistReferenceName(rawValue: "  \n "))
    }

    expectExpressionError(.emptyReference("target")) {
        try AccessibilityTarget(ref: HeistReferenceName(rawValue: "  \n "))
    }

    expectDecodingError(StringExpr.self, #"{"ref":"   "}"#, contains: "string reference must not be empty")
    expectDecodingError(AccessibilityTarget.self, #"{"ref":"   "}"#, contains: "target reference must not be empty")
    expectDecodingError(
        ElementPredicateTemplate.self,
        #"{"checks":[{"kind":"label","match":{"mode":"exact","value":{"ref":"   "}}}]}"#,
        contains: "string reference must not be empty"
    )
    expectDecodingError(
        AccessibilityPredicate<RootContext>.self,
        #"{"type":"exists","target":{"ref":"   "}}"#,
        contains: "target reference must not be empty"
    )
    expectDecodingError(
        AccessibilityPredicate<ElementsAssertionContext>.self,
        #"{"type":"updated","target":{"checks":["# +
            #"{"kind":"label","match":{"mode":"exact","value":"Count"}}]},"# +
            #""property":"value","before":{"mode":"exact","value":{"ref":"   "}}}"#,
        contains: "string reference must not be empty"
    )
}

@Test
func `broad string matches reject refs that resolve empty`() throws {
    let labelPredicate = ElementPredicateTemplate(label: .contains(.ref("needle")))
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try labelPredicate.resolve(in: HeistExecutionEnvironment(strings: ["needle": ""]))
    }

    let state = AccessibilityPredicate<RootContext>.exists(.identifier(.prefix(.ref("prefix"))))
    expectExpressionError(.invalidStringMatch(mode: "prefix")) {
        try state.resolve(in: HeistExecutionEnvironment(strings: ["prefix": ""]))
    }

    let scopedTarget = AccessibilityTarget.within(
        container: .identifier("Screen"),
        .label(.contains(.ref("titlePart")))
    )
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        _ = try scopedTarget.resolve(in: HeistExecutionEnvironment(strings: ["titlePart": ""]))
    }

    let containerTarget = AccessibilityTarget.container(
        .identifier(StringExpr.ref("screenId")),
        ordinal: 2
    )
    #expect(
        try containerTarget.resolve(in: HeistExecutionEnvironment(strings: ["screenId": "Checkout"])) ==
        .container(.identifier("Checkout"), ordinal: 2)
    )

    let update = AccessibilityPredicate<ElementsAssertionContext>.updated(
        .label("Count"),
        .value(before: .contains(.ref("fromPart")))
    )
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try update.resolve(in: HeistExecutionEnvironment(strings: ["fromPart": ""]))
    }
}

@Test
func `parameter binding resolves arguments in current scope and returns nested scope`() throws {
    let sourceTarget = AccessibilityTarget.predicate(.label("Submit"), ordinal: 1)
    let outer = HeistExecutionEnvironment(
        targets: ["sourceTarget": sourceTarget],
        strings: ["source": "Pay", "item": "outer"]
    )

    let stringScope = try outer.binding(argument: .string(.ref("source")), to: .string(name: "item"))
    #expect(stringScope.strings["item"] == "Pay")
    #expect(stringScope.strings["source"] == "Pay")
    #expect(stringScope.targets == outer.targets)
    #expect(outer.strings["item"] == "outer")

    let targetScope = try outer.binding(
        argument: .accessibilityTarget(.ref("sourceTarget")),
        to: .accessibilityTarget(name: "target")
    )
    #expect(targetScope.targets["target"] == sourceTarget)
    #expect(targetScope.targets["sourceTarget"] == sourceTarget)
    #expect(targetScope.strings == outer.strings)
    #expect(outer.targets["target"] == nil)

    expectExpressionError(.parameterArgumentMismatch(parameter: .string, argument: .accessibilityTarget)) {
        try outer.binding(argument: .accessibilityTarget(sourceTarget), to: .string(name: "item"))
    }
}

@Test
func `nested predicate resolution preserves screen change semantics`() throws {
    let target = AccessibilityTarget.predicate(.identifier("cta"), ordinal: 0)
    let expression = AccessibilityPredicate<RootContext>.changed(.screen([
        .exists(.label(.exact(.ref("title")))),
        .missing(.ref("ctaTarget")),
        .exists(.value(.contains(.ref("valuePart")))),
        .exists(.container(.identifier(StringExpr.ref("screenId")))),
    ]))

    let environment = HeistExecutionEnvironment(
        targets: ["ctaTarget": target],
        strings: ["title": "Dashboard", "valuePart": "Ready", "screenId": "DashboardScreen"]
    )

    let resolved = try expression.resolve(in: environment)
    let expected = AccessibilityPredicate<RootContext>.changed(.screen([
        .exists(.label("Dashboard")),
        .missing(target),
        .exists(.value(.contains("Ready"))),
        .exists(.container(.identifier("DashboardScreen"))),
    ]))

    #expect(resolved == expected)
}

@Test
func `expression codable shapes remain stable`() throws {
    #expect(try sortedJSON(StringExpr.ref("title")) == #"{"ref":"title"}"#)
    #expect(try sortedJSON(AccessibilityTarget.ref("target")) == #"{"ref":"target"}"#)

    let template = ElementPredicateTemplate(
        label: .exact(.ref("title")),
        identifier: .contains(.literal("field")),
        value: .exact(.literal("Ready"))
    )
    let expectedTemplateJSON = """
        {"checks":[{"kind":"label","match":{"mode":"exact","value":{"ref":"title"}}},\
        {"kind":"identifier","match":{"mode":"contains","value":"field"}},\
        {"kind":"value","match":{"mode":"exact","value":"Ready"}}]}
        """
    #expect(try sortedJSON(template) == expectedTemplateJSON)

    #expect(
        try sortedJSON(AccessibilityPredicate<RootContext>.exists(.ref("target"))) ==
        #"{"target":{"ref":"target"},"type":"exists"}"#
    )
    #expect(
        try sortedJSON(AccessibilityPredicate<RootContext>.exists(.container(.label("Checkout")))) ==
        #"{"target":{"container":{"checks":[{"kind":"semantic","semantic":{"kind":"label","# +
        #""match":{"mode":"exact","value":"Checkout"}}}]}},"type":"exists"}"#
    )
    #expect(
        try sortedJSON(AccessibilityPredicate<RootContext>.missing(.container(.label("Checkout")))) ==
        #"{"target":{"container":{"checks":[{"kind":"semantic","semantic":{"kind":"label","# +
        #""match":{"mode":"exact","value":"Checkout"}}}]}},"type":"missing"}"#
    )

    let change = AccessibilityPredicate<RootContext>.changed(.elements([
        .updated(
            .label(.exact(.ref("item"))),
            .value(before: .exact(.ref("old")), after: .exact(.literal("new")))
        ),
    ]))
    let expectedChangeJSON = """
        {"assertions":[{"after":{"mode":"exact","value":"new"},\
        "before":{"mode":"exact","value":{"ref":"old"}},\
        "property":"value","target":{"checks":[{"kind":"label","match":{"mode":"exact","value":{"ref":"item"}}}]},\
        "type":"updated"}],"scope":"elements","type":"changed"}
        """
    #expect(try sortedJSON(change) == expectedChangeJSON)

    let targetChange = AccessibilityPredicate<RootContext>.changed(.elements([
        .updated(
            .identifier("cart-count"),
            .value(before: .prefix(.literal("cart:")), after: .contains(.ref("count")))
        ),
    ]))
    let expectedTargetChangeJSON =
        #"{"assertions":[{"after":{"mode":"contains","value":{"ref":"count"}},"# +
        #""before":{"mode":"prefix","value":"cart:"},"# +
        #""property":"value","target":{"checks":["# +
        #"{"kind":"identifier","match":{"mode":"exact","value":"cart-count"}}]},"# +
        #""type":"updated"}],"scope":"elements","type":"changed"}"#
    #expect(
        try sortedJSON(targetChange) == expectedTargetChangeJSON
    )
}

@Test
func `target construction sugar equals predicate templates`() throws {
    let targetBacked = AccessibilityTarget.target(.label("Save"), ordinal: 1)
    let templateBacked = AccessibilityTarget.predicate(
        ElementPredicateTemplate(label: .exact(.literal("Save"))),
        ordinal: 1
    )

    #expect(targetBacked == templateBacked)
    #expect(Set([targetBacked, templateBacked]).count == 1)
    #expect(targetBacked != .predicate(ElementPredicateTemplate(label: .exact(.literal("Save"))), ordinal: 2))

    let predicateBacked = AccessibilityPredicate<RootContext>.exists(.label("Save"))
    let stateTemplate = AccessibilityPredicate<RootContext>.exists(.predicate(
        ElementPredicateTemplate(label: .exact("Save"))
    ))

    #expect(predicateBacked == stateTemplate)
}

@Test
func `target expression refinement appends checks and preserves ordinal`() throws {
    let target = AccessibilityTarget.target(.label("Search"), ordinal: 1)
    let refined = target
        .and(.traits([.isEditing]))
        .excluding(.traits([.textEntry]))

    let expected = AccessibilityTarget.predicate(ElementPredicateTemplate([
        .label(.exact(.literal("Search"))),
        .traits([.isEditing]),
        .exclude(.traits([.textEntry])),
    ]), ordinal: 1)
    #expect(refined == expected)
    #expect(try refined.resolve(in: .empty) == .predicate(ElementPredicateTemplate([
        .label(.exact(.literal("Search"))),
        .traits([.isEditing]),
        .exclude(.traits([.textEntry])),
    ]), ordinal: 1))
}

@Test
func `target expression refinement leaves refs unresolved`() throws {
    let target = AccessibilityTarget.ref("row")

    #expect(target.and(.traits([.isEditing])) == target)
    #expect(target.excluding(.traits([.textEntry])) == target)
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
