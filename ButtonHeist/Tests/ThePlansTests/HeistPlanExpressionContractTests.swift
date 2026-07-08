import Foundation
import Testing
import ThePlans

@Test
func `unresolved expression refs throw typed errors`() throws {
    expectExpressionError(.unresolvedStringReference("missing")) {
        try StringExpr(ref: HeistReferenceName(rawValue: "missing")).resolve(in: .empty)
    }

    expectExpressionError(.unresolvedTargetReference("missing")) {
        try ElementTargetExpr(ref: HeistReferenceName(rawValue: "missing")).resolve(in: .empty)
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
        try ElementTargetExpr(ref: HeistReferenceName(rawValue: "  \n "))
    }

    expectDecodingError(StringExpr.self, #"{"ref":"   "}"#, contains: "string reference must not be empty")
    expectDecodingError(ElementTargetExpr.self, #"{"ref":"   "}"#, contains: "target reference must not be empty")
    expectDecodingError(
        ElementPredicateTemplate.self,
        #"{"checks":[{"kind":"label","match":{"mode":"exact","value":{"ref":"   "}}}]}"#,
        contains: "string reference must not be empty"
    )
    expectDecodingError(StatePredicateExpr.self, #"{"type": "exists","target_ref":"   "}"#, contains: "target_ref must not be empty")
    expectDecodingError(
        ElementUpdatePredicateExpr.self,
        #"{"property":"value","before":{"mode":"exact","value":{"ref":"   "}}}"#,
        contains: "string reference must not be empty"
    )
}

@Test
func `broad string matches reject refs that resolve empty`() throws {
    let labelPredicate = ElementPredicateTemplate(label: .contains(.ref("needle")))
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try labelPredicate.resolve(in: HeistExecutionEnvironment(strings: ["needle": ""]))
    }

    let state = StatePredicateExpr.exists(ElementPredicateTemplate(identifier: .prefix(.ref("prefix"))))
    expectExpressionError(.invalidStringMatch(mode: "prefix")) {
        try state.resolve(in: HeistExecutionEnvironment(strings: ["prefix": ""]))
    }

    let screen = StatePredicateExpr.onScreen(header: .contains(.ref("titlePart")))
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try screen.resolve(in: HeistExecutionEnvironment(strings: ["titlePart": ""]))
    }

    let update = ElementUpdatePredicateExpr(change: .value(before: .contains(.ref("fromPart"))))
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try update.resolve(in: HeistExecutionEnvironment(strings: ["fromPart": ""]))
    }
}

@Test
func `parameter binding resolves arguments in current scope and returns nested scope`() throws {
    let sourceTarget = ElementTarget.predicate(ElementPredicate(label: "Submit"), ordinal: 1)
    let outer = HeistExecutionEnvironment(
        targets: ["sourceTarget": sourceTarget],
        strings: ["source": "Pay", "item": "outer"]
    )

    let stringScope = try outer.binding(argument: .string(.ref("source")), to: .string(name: "item"))
    #expect(stringScope.strings["item"] == "Pay")
    #expect(stringScope.strings["source"] == "Pay")
    #expect(stringScope.targets == outer.targets)
    #expect(outer.strings["item"] == "outer")

    let targetScope = try outer.binding(argument: .elementTarget(.ref("sourceTarget")), to: .elementTarget(name: "target"))
    #expect(targetScope.targets["target"] == sourceTarget)
    #expect(targetScope.targets["sourceTarget"] == sourceTarget)
    #expect(targetScope.strings == outer.strings)
    #expect(outer.targets["target"] == nil)

    expectExpressionError(.parameterArgumentMismatch(parameter: .string, argument: .elementTarget)) {
        try outer.binding(argument: .elementTarget(.target(sourceTarget)), to: .string(name: "item"))
    }
}

@Test
func `nested predicate resolution preserves state and change semantics`() throws {
    let target = ElementTarget.predicate(ElementPredicate(identifier: "cta"), ordinal: 0)
    let expression = AccessibilityPredicateExpr.change(.screen(.all(
        .exists(ElementPredicateTemplate(label: .exact(.ref("title")))),
        .missingTarget(.ref("ctaTarget")),
        .exists(ElementPredicateTemplate(value: .contains(.ref("valuePart")))),
        .onScreen(header: .exact(.ref("title")))
    )))

    let environment = HeistExecutionEnvironment(
        targets: ["ctaTarget": target],
        strings: ["title": "Dashboard", "valuePart": "Ready"]
    )

    let resolved = try expression.resolve(in: environment)
    let expected = AccessibilityPredicate.change(.screen(.all(
        .exists(ElementPredicate(label: "Dashboard")),
        .missingTarget(target),
        .exists(ElementPredicate(value: .contains("Ready"))),
        .onScreen(header: "Dashboard")
    )))

    #expect(resolved == expected)
}

@Test
func `expression codable shapes remain stable`() throws {
    #expect(try sortedJSON(StringExpr.ref("title")) == #"{"ref":"title"}"#)
    #expect(try sortedJSON(ElementTargetExpr.ref("target")) == #"{"ref":"target"}"#)

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

    #expect(try sortedJSON(StatePredicateExpr.existsTarget(.ref("target"))) == #"{"target_ref":"target","type":"exists"}"#)
    #expect(
        try sortedJSON(StatePredicateExpr.onScreen(id: "checkout")) ==
        #"{"id":"checkout","type":"screen"}"#
    )
    #expect(
        try sortedJSON(StatePredicateExpr.onScreen(header: "Checkout")) ==
        #"{"header":{"mode":"exact","value":"Checkout"},"type":"screen"}"#
    )

    let change = ChangePredicateExpr.elements(.updatedElement(ElementUpdatePredicateExpr(
        element: ElementPredicateTemplate(label: .exact(.ref("item"))),
        change: .value(before: .exact(.ref("old")), after: .exact(.literal("new")))
    )))
    let expectedChangeJSON = """
        {"scopes":[{"assertions":[{"after":{"mode":"exact","value":"new"},\
        "before":{"mode":"exact","value":{"ref":"old"}},\
        "element":{"checks":[{"kind":"label","match":{"mode":"exact","value":{"ref":"item"}}}]},\
        "property":"value","type":"updated"}],"type":"elements"}],"type":"change"}
        """
    #expect(try sortedJSON(change) == expectedChangeJSON)

    let broadChange = ChangePredicateExpr.elements(.updatedElement(ElementUpdatePredicateExpr(
        change: .value(before: .prefix(.literal("cart:")), after: .contains(.ref("count")))
    )))
    let expectedBroadChangeJSON =
        #"{"scopes":[{"assertions":[{"after":{"mode":"contains","value":{"ref":"count"}},"# +
        #""before":{"mode":"prefix","value":"cart:"},"# +
        #""property":"value","type":"updated"}],"type":"elements"}],"type":"change"}"#
    #expect(
        try sortedJSON(broadChange) == expectedBroadChangeJSON
    )
}

@Test
func `target backed predicates equal predicate templates`() throws {
    let targetBacked = ElementTargetExpr.target(.predicate(ElementPredicate(label: "Save"), ordinal: 1))
    let templateBacked = ElementTargetExpr.predicate(
        ElementPredicateTemplate(label: .exact(.literal("Save"))),
        ordinal: 1
    )

    #expect(targetBacked == templateBacked)
    #expect(Set([targetBacked, templateBacked]).count == 1)
    #expect(targetBacked != .predicate(ElementPredicateTemplate(label: .exact(.literal("Save"))), ordinal: 2))

    let predicateBacked = AccessibilityPredicateExpr.predicate(.state(.exists(ElementPredicate(label: "Save"))))
    let stateTemplate = AccessibilityPredicateExpr.state(.exists(ElementPredicateTemplate(label: .exact("Save"))))

    #expect(predicateBacked == stateTemplate)
}

@Test
func `target expression refinement appends checks and preserves ordinal`() throws {
    let target = ElementTargetExpr.target(.predicate(ElementPredicate(label: "Search"), ordinal: 1))
    let refined = target
        .and(.traits([.isEditing]))
        .excluding(.traits([.textEntry]))

    let expected = ElementTargetExpr.predicate(ElementPredicateTemplate([
        .label(.exact(.literal("Search"))),
        .traits([.isEditing]),
        .exclude(.traits([.textEntry])),
    ]), ordinal: 1)
    #expect(refined == expected)
    #expect(try refined.resolve(in: .empty) == .predicate(ElementPredicate([
        .label(.exact("Search")),
        .traits([.isEditing]),
        .exclude(.traits([.textEntry])),
    ]), ordinal: 1))
}

@Test
func `target expression refinement leaves refs unresolved`() throws {
    let target = ElementTargetExpr.ref("row")

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
