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
    expectDecodingError(ElementPredicateTemplate.self, #"{"label_ref":"   "}"#, contains: "label_ref must not be empty")
    expectDecodingError(StatePredicateExpr.self, #"{"type":"present","target_ref":"   "}"#, contains: "target_ref must not be empty")
    expectDecodingError(ElementUpdatePredicateExpr.self, #"{"from_ref":"   "}"#, contains: "from_ref must not be empty")
}

@Test
func `broad string matches reject refs that resolve empty`() throws {
    let labelPredicate = ElementPredicateTemplate(label: .contains(.ref("needle")))
    expectExpressionError(.invalidStringMatch(mode: "contains")) {
        try labelPredicate.resolve(in: HeistExecutionEnvironment(strings: ["needle": ""]))
    }

    let state = StatePredicateExpr.present(ElementPredicateTemplate(identifier: .prefix(.ref("prefix"))))
    expectExpressionError(.invalidStringMatch(mode: "prefix")) {
        try state.resolve(in: HeistExecutionEnvironment(strings: ["prefix": ""]))
    }

    let update = ElementUpdatePredicateExpr(property: .value, from: .contains(.ref("fromPart")))
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
    let expression = AccessibilityPredicateExpr.changed(.screen(where: .all([
        .present(ElementPredicateTemplate(label: .exact(.ref("title")))),
        .absentTarget(.ref("ctaTarget")),
        .present(ElementPredicateTemplate(value: .contains(.ref("valuePart")))),
    ])))

    let environment = HeistExecutionEnvironment(
        targets: ["ctaTarget": target],
        strings: ["title": "Dashboard", "valuePart": "Ready"]
    )

    let resolved = try expression.resolve(in: environment)
    let expected = AccessibilityPredicate.changed(.screen(where: .all([
        .present(ElementPredicate(label: "Dashboard")),
        .absentTarget(target),
        .present(ElementPredicate(value: .contains("Ready"))),
    ])))

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
    #expect(try sortedJSON(template) == #"{"identifier":{"mode":"contains","value":"field"},"label_ref":"title","value":"Ready"}"#)

    #expect(try sortedJSON(StatePredicateExpr.presentTarget(.ref("target"))) == #"{"target_ref":"target","type":"present"}"#)

    let change = ChangePredicateExpr.updated(ElementUpdatePredicateExpr(
        element: ElementPredicateTemplate(label: .exact(.ref("item"))),
        property: .value,
        from: .ref("old"),
        to: .literal("new")
    ))
    #expect(try sortedJSON(change) == #"{"element":{"label_ref":"item"},"from_ref":"old","property":"value","to":"new","type":"element_updated"}"#)

    let broadChange = ChangePredicateExpr.updated(ElementUpdatePredicateExpr(
        property: .value,
        from: .prefix(.literal("cart:")),
        to: .contains(.ref("count"))
    ))
    #expect(
        try sortedJSON(broadChange) ==
            #"{"from":{"mode":"prefix","value":"cart:"},"property":"value","to":{"mode":"contains","value":{"ref":"count"}},"type":"element_updated"}"#
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

    let predicateBacked = AccessibilityPredicateExpr.predicate(.state(.present(ElementPredicate(label: "Save"))))
    let stateTemplate = AccessibilityPredicateExpr.state(.present(ElementPredicateTemplate(label: .exact("Save"))))

    #expect(predicateBacked == stateTemplate)
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
