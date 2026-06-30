import Testing
@testable import ThePlans

@Test
func `parser helpers expose named result values`() {
    let branches = ParsedPredicateBranches(cases: [], elseBody: nil)
    #expect(branches.cases.isEmpty)
    #expect(branches.elseBody == nil)

    let closure = ParsedClosureParameterBlock(referenceName: "item", body: [])
    #expect(closure.referenceName.rawValue == "item")
    #expect(closure.body.isEmpty)

    let definitionHeader = HeistDefinitionHeader(path: "Checkout.Pay", parameter: .none)
    #expect(definitionHeader.path == "Checkout.Pay")
    #expect(definitionHeader.parameter == .none)

    let planHeader = HeistPlanHeader(name: "Checkout", parameter: .none)
    #expect(planHeader.name == "Checkout")
    #expect(planHeader.parameter == .none)

    let fields = PropertyChangeFields(before: "old", after: "new")
    #expect(fields.before == "old")
    #expect(fields.after == "new")

    let token = HeistPlanSourceToken(
        kind: .identifier("exact"),
        sourceName: "test",
        marker: HeistPlanSourceMarker(offset: 0, line: 1, column: 1, length: 5)
    )
    let labelToken = StringMatchModeLabelToken(name: "exact", token: token)
    #expect(labelToken.name == "exact")
    #expect(labelToken.token == token)
}

@Test
func `dotted path definition builder exposes a named result value`() throws {
    let heistContent = try SourceShapeRepository(filePath: #filePath)
        .requiredFile(relativePath: "ButtonHeist/Sources/ThePlans/HeistContent.swift")
    let resultType = try #require(heistContent.firstBlock(
        matching: #"private struct DottedPathDefinitionBuild\b"#
    ))
    let helper = try #require(heistContent.firstBlock(
        matching: #"private static func buildDefinitionFromDottedPath\("#
    ))

    #expect(resultType.contents.contains("private struct DottedPathDefinitionBuild: Sendable, Equatable"))
    #expect(resultType.contents.contains("let pathComponents: [String]"))
    #expect(resultType.contents.contains(
        "let definitionResult: ValidationResult<HeistPlan, HeistBuildDiagnostic>"
    ))

    #expect(!helper.contents.contains(") -> ("))
    #expect(helper.contents.contains(") -> DottedPathDefinitionBuild"))
    #expect(!helper.contents.contains("(components:"))
    #expect(!helper.contents.contains("definition: ValidationResult<HeistPlan, HeistBuildDiagnostic>"))
    #expect(try !heistContent.containsMatch(#"\bresult\.components\b"#))
    #expect(try !heistContent.containsMatch(#"\bresult\.definition\b"#))
}
