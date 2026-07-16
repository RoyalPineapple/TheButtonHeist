import Foundation
import Testing
@testable import ThePlans

@Test func `name and path currencies use one single value wire shape`() throws {
    let planName: HeistPlanName = "Cart"
    let definitionPath: HeistDefinitionPath = "Cart.addItem"
    let invocationPath: HeistInvocationPath = "Cart.addItem"
    let encoder = JSONEncoder()
    let decoder = JSONDecoder()

    #expect(String(bytes: try encoder.encode(planName), encoding: .utf8) == #""Cart""#)
    #expect(String(bytes: try encoder.encode(definitionPath), encoding: .utf8) == #""Cart.addItem""#)
    #expect(String(bytes: try encoder.encode(invocationPath), encoding: .utf8) == #""Cart.addItem""#)
    #expect(try decoder.decode(HeistPlanName.self, from: encoder.encode(planName)) == planName)
    #expect(try decoder.decode(HeistDefinitionPath.self, from: encoder.encode(definitionPath)) == definitionPath)
    #expect(try decoder.decode(HeistInvocationPath.self, from: encoder.encode(invocationPath)) == invocationPath)
}

@Test func `typed paths build definitions and invocations without raw strings`() throws {
    let definitionPath: HeistDefinitionPath = "Cart.addItem"
    let invocationPath: HeistInvocationPath = "Cart.addItem"
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
            path: invocationPath,
            argument: .string("Milk")
        )),
    ])
    #expect(plan.heistDefinition(at: definitionPath)?.name == "addItem")
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
        .invoke(HeistInvocationStep(path: "Missing")),
    ])
    try expectSemanticDiagnostic(
        unresolved,
        path: "$.body[0].invoke.path",
        message: "heist run path must resolve to a local capability"
    )

    let recursive = HeistPlanAdmissionCandidate(definitions: [
        HeistPlanAdmissionCandidate(name: "lib", definitions: [
            HeistPlanAdmissionCandidate(name: "a", body: [
                .invoke(HeistInvocationStep(path: "lib.b")),
            ]),
            HeistPlanAdmissionCandidate(name: "b", body: [
                .invoke(HeistInvocationStep(path: "lib.a")),
            ]),
        ], body: []),
    ], body: [.invoke(HeistInvocationStep(path: "lib.a"))])
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
    [
        (
            HeistPlanAdmissionCandidate(body: [admissionStep(try stringLoop(parameter: "item", body: [
                try stringLoop(parameter: "size"),
            ]))]),
            "$.body[0].for_each_string.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(body: [admissionStep(try stringLoop(parameter: "rowName", body: [
                try elementLoop(parameter: "rowTarget"),
            ]))]),
            "$.body[0].for_each_string.body[0].for_each_element",
            "for_each_element inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(body: [admissionStep(try elementLoop(parameter: "section", body: [
                try stringLoop(parameter: "size"),
            ]))]),
            "$.body[0].for_each_element.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(body: [admissionStep(try elementLoop(parameter: "section", body: [
                try elementLoop(parameter: "row"),
            ]))]),
            "$.body[0].for_each_element.body[0].for_each_element",
            "for_each_element inside collection loop"
        ),
        (
            HeistPlanAdmissionCandidate(
                definitions: [
                    HeistPlanAdmissionCandidate(name: "Inner", body: [admissionStep(try stringLoop(parameter: "size"))]),
                ],
                body: [admissionStep(try stringLoop(parameter: "item", body: [
                    .invoke(HeistInvocationStep(path: "Inner")),
                ]))]
            ),
            "$.body[0].for_each_string.body[0].invoke.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
    ]
}

private func admissionStep(_ step: HeistStep) -> HeistStepAdmissionCandidate {
    HeistStepAdmissionCandidate(step)
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
