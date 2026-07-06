import Testing
@testable import ThePlans

@Test func `typed paths build definitions and invocations without raw strings`() throws {
    let definitionPath = try HeistDefinitionPath(dottedName: "Cart.addItem")
    let invocationPath = try HeistInvocationPath(dottedName: "Cart.addItem")
    let addItem = HeistDef<String>(definitionPath, parameter: "item") { item in
        Activate(.label(item))
    }

    let plan = try HeistPlan {
        addItem
        RunHeist(invocationPath, "Milk")
    }

    #expect(plan.definitions.map(\.name) == ["Cart"])
    #expect(plan.body == [
        .invoke(HeistInvocationStep(
            invocationPath: invocationPath,
            argument: .string(.literal("Milk"))
        )),
    ])
    #expect(plan.heistDefinition(at: definitionPath.components)?.name == "addItem")
}

@Test func `typed path constructors reject malformed name corpus`() throws {
    let cases = [
        ("", "must not be empty"),
        (".checkout", "component at index 0 must not be empty"),
        ("Cart.", "component at index 1 must not be empty"),
        ("Cart..checkout", "component at index 1 must not be empty"),
        ("Cart Screen.checkout", "component at index 0 must be a Swift-style identifier"),
        ("1Cart.checkout", "component at index 0 must be a Swift-style identifier"),
        ("Cart.class", "component at index 1 must be a Swift-style identifier"),
        ("Cart.checkout-now", "component at index 1 must be a Swift-style identifier"),
    ]

    for (path, expectedMessage) in cases {
        expectDefinitionPathFailure(path, contains: expectedMessage)
        expectInvocationPathFailure(path, contains: expectedMessage)
    }
}

@Test func `source and Swift builder share invalid definition path diagnostics`() throws {
    let definition = HeistDef<Void>("Cart..checkout") {
        Warn("checkout")
    }
    let builderDiagnostic = try #require(definition.heistBuildDiagnostics.first)
    let sourceDiagnostic = compileDiagnostic("""
    HeistPlan("cart") {
        HeistDef<Void>("Cart..checkout") {
            Warn("checkout")
        }
    }
    """)

    #expect(builderDiagnostic.code == .dslInvalidDefinition)
    #expect(sourceDiagnostic.code == builderDiagnostic.code)
    #expect(builderDiagnostic.title == "Invalid heist definition")
    #expect(sourceDiagnostic.title == builderDiagnostic.title)
    #expect(builderDiagnostic.path == "Cart..checkout")
    #expect(sourceDiagnostic.path == builderDiagnostic.path)
    #expect(builderDiagnostic.message == sourceDiagnostic.message)
    #expect(builderDiagnostic.hint == sourceDiagnostic.hint)
    #expect(builderDiagnostic.phase == .dslBuild)
    #expect(sourceDiagnostic.phase == .sourceCompilation)
    #expect(sourceDiagnostic.sourceSpan?.line == 2)
    #expect(sourceDiagnostic.sourceSpan?.column == 20)
}

@Test func `source and Swift builder share invalid invocation path diagnostics`() throws {
    let builderContent = RunHeist("Cart..checkout")
    let builderDiagnostic = try #require(builderContent.heistBuildDiagnostics.first)
    let sourceDiagnostic = compileDiagnostic("""
    HeistPlan("cart") {
        RunHeist("Cart..checkout")
    }
    """)

    #expect(builderDiagnostic.code == .dslInvalidInvocationPath)
    #expect(sourceDiagnostic.code == builderDiagnostic.code)
    #expect(builderDiagnostic.title == "Invalid RunHeist path")
    #expect(sourceDiagnostic.title == builderDiagnostic.title)
    #expect(builderDiagnostic.path == "Cart..checkout")
    #expect(sourceDiagnostic.path == builderDiagnostic.path)
    #expect(builderDiagnostic.message == sourceDiagnostic.message)
    #expect(builderDiagnostic.hint == sourceDiagnostic.hint)
    #expect(builderDiagnostic.phase == .dslBuild)
    #expect(sourceDiagnostic.phase == .sourceCompilation)
    #expect(sourceDiagnostic.sourceSpan?.line == 2)
    #expect(sourceDiagnostic.sourceSpan?.column == 14)
}

@Test func `semantic validation rejects duplicate unresolved and recursive plans`() throws {
    let duplicate = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "checkout", body: [.warn(WarnStep(message: "one"))]),
        HeistPlanAdmissionCandidate(name: "checkout", body: [.warn(WarnStep(message: "two"))]),
    ], body: [.warn(WarnStep(message: "root"))])
    try expectSemanticDiagnostic(
        duplicate,
        path: "$.definitions[1].name",
        message: "duplicate heist definition names are not allowed in the same scope"
    )

    let unresolved = HeistPlanAdmissionCandidate(body: [
        .invoke(HeistInvocationStep(path: ["Missing"])),
    ])
    try expectSemanticDiagnostic(
        unresolved,
        path: "$.body[0].invoke.path",
        message: "heist run path must resolve to a local capability"
    )

    let recursive = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "lib", definitions: [
            HeistPlanAdmissionCandidate(name: "a", body: [
                .invoke(HeistInvocationStep(path: ["lib", "b"])),
            ]),
            HeistPlanAdmissionCandidate(name: "b", body: [
                .invoke(HeistInvocationStep(path: ["lib", "a"])),
            ]),
        ], body: []),
    ], body: [.invoke(HeistInvocationStep(path: ["lib", "a"]))])
    try expectSemanticDiagnostic(
        recursive,
        path: "$.definitions[0].definitions[0].body[0].invoke.body[0].invoke.path",
        message: "heist runs must not be recursive"
    )
}

@Test func `semantic validation rejects nested collection loops`() throws {
    for testCase in try nestedCollectionLoopCases() {
        let diagnostic = try #require(testCase.candidate.semanticValidationResult().failureDiagnostics?.first)
        #expect(diagnostic.code == .planRuntimeSafety)
        #expect(diagnostic.title == "Plan semantic validation failed")
        #expect(diagnostic.phase == .planValidation)
        #expect(diagnostic.path == testCase.path)
        #expect(diagnostic.message == "collection loops must not be nested; observed \(testCase.observed)")
        #expect(diagnostic.hint == "Flatten this heist so ForEach bodies contain only non-collection steps.")
    }
}

private func nestedCollectionLoopCases() throws -> [(candidate: HeistPlanAdmissionCandidate, path: String, observed: String)] {
    try [
        (
            HeistPlanAdmissionCandidate(body: [try stringLoop(parameter: "item", body: [
                try stringLoop(parameter: "size"),
            ])]),
            "$.body[0].for_each_string.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(body: [try stringLoop(parameter: "rowName", body: [
                try elementLoop(parameter: "rowTarget"),
            ])]),
            "$.body[0].for_each_string.body[0].for_each_element",
            "for_each_element inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(body: [try elementLoop(parameter: "section", body: [
                try stringLoop(parameter: "size"),
            ])]),
            "$.body[0].for_each_element.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(body: [try elementLoop(parameter: "section", body: [
                try elementLoop(parameter: "row"),
            ])]),
            "$.body[0].for_each_element.body[0].for_each_element",
            "for_each_element inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(
                definitions: [
                    HeistPlanAdmissionCandidate(name: "Inner", body: [try stringLoop(parameter: "size")]),
                ],
                body: [try stringLoop(parameter: "item", body: [
                    .invoke(HeistInvocationStep(path: ["Inner"])),
                ])]
            ),
            "$.body[0].for_each_string.body[0].invoke.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
    ]
}

private func stringLoop(
    parameter: HeistReferenceName,
    body: [HeistStep] = [.warn(WarnStep(message: "nested"))]
) throws -> HeistStep {
    .forEachString(try ForEachStringStep(values: ["Milk"], parameter: parameter, body: body))
}

private func elementLoop(
    parameter: HeistReferenceName,
    body: [HeistStep] = [.warn(WarnStep(message: "nested"))]
) throws -> HeistStep {
    .forEachElement(try ForEachElementStep(matching: .label("Row"), limit: 1, parameter: parameter, body: body))
}

private func expectDefinitionPathFailure(
    _ path: String,
    contains expectedMessage: String
) {
    do {
        _ = try HeistDefinitionPath(dottedName: path)
        Issue.record("Expected definition path to fail: \(path)")
    } catch {
        let message = String(describing: error)
        #expect(message.contains(expectedMessage), "\(message) did not contain \(expectedMessage)")
    }
}

private func expectInvocationPathFailure(
    _ path: String,
    contains expectedMessage: String
) {
    do {
        _ = try HeistInvocationPath(dottedName: path)
        Issue.record("Expected invocation path to fail: \(path)")
    } catch {
        let message = String(describing: error)
        #expect(message.contains(expectedMessage), "\(message) did not contain \(expectedMessage)")
    }
}

private func expectSemanticDiagnostic(
    _ candidate: HeistPlanAdmissionCandidate,
    path expectedPath: String,
    message expectedMessage: String
) throws {
    let diagnostic = try #require(candidate.semanticValidationResult().failureDiagnostics?.first)

    #expect(diagnostic.code == .planRuntimeSafety)
    #expect(diagnostic.title == "Plan semantic validation failed")
    #expect(diagnostic.phase == .planValidation)
    #expect(diagnostic.path == expectedPath)
    #expect(diagnostic.message.contains(expectedMessage))
    #expect(diagnostic.hint != nil)
}

private func compileDiagnostic(_ source: String) -> HeistBuildDiagnostic {
    do {
        _ = try HeistPlanSourceCompiler().compile(source)
        Issue.record("Expected source to fail: \(source)")
        return HeistBuildDiagnostic(
            externalBoundaryRawCode: "test.missing_diagnostic",
            phase: .sourceCompilation,
            message: "Expected source to fail"
        )
    } catch let error as HeistPlanSourceCompilerError {
        return error.diagnostic
    } catch {
        Issue.record("Expected HeistPlanSourceCompilerError, got \(error)")
        return HeistBuildDiagnostic(
            externalBoundaryRawCode: "test.unexpected_error",
            phase: .sourceCompilation,
            message: String(describing: error)
        )
    }
}
