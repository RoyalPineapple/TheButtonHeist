import Foundation
import Testing
@testable import ThePlans

@Test func testAllPublicBoundariesAdmitOneHeistPlan() throws {
    let cases = [
        PublicBoundaryAdmissionCase(
            boundary: "JSON",
            expectedContract: "heist run path must resolve to a local capability"
        ) {
            try JSONDecoder().decode(HeistPlan.self, from: Data("""
            {
              "version": 2,
              "body": [
                {
                  "type": "invoke",
                  "invoke": { "path": "Missing" }
                }
              ]
            }
            """.utf8))
        },
        PublicBoundaryAdmissionCase(
            boundary: "Swift DSL",
            expectedContract: "heist runs must not be recursive"
        ) {
            let first = HeistDef<Void>("lib.first") {
                RunHeist("lib.second")
            }
            let second = HeistDef<Void>("lib.second") {
                RunHeist("lib.first")
            }
            return try HeistPlan {
                first
                second
                try first()
            }
        },
        PublicBoundaryAdmissionCase(
            boundary: "source compilation",
            expectedContract: "max nested step depth"
        ) {
            try HeistSourceCompilation.compile(deeplyNestedSource)
        },
        PublicBoundaryAdmissionCase(
            boundary: "live composition",
            expectedContract: "max total heist steps"
        ) {
            try HeistPlan(body: Array(
                repeating: .warn(WarnStep(message: "step")),
                count: 501
            ))
        },
        PublicBoundaryAdmissionCase(
            boundary: "Swift DSL expansion",
            expectedContract: "max total heist steps"
        ) {
            let expanded = HeistDef<Void>("expanded") {
                HeistContent(Array(
                    repeating: .warn(WarnStep(message: "expanded")),
                    count: 170
                ))
            }
            return try HeistPlan {
                expanded
                try expanded()
                try expanded()
            }
        },
    ]

    for testCase in cases {
        do {
            _ = try testCase.admit()
            Issue.record("\(testCase.boundary) accepted an unsafe plan")
        } catch let error as HeistPlanBuildError {
            #expect(
                error.diagnostics.contains { $0.message.contains(testCase.expectedContract) },
                "\(testCase.boundary): \(error)"
            )
        } catch {
            Issue.record("\(testCase.boundary) bypassed canonical diagnostics: \(error)")
        }
    }
}

private struct PublicBoundaryAdmissionCase {
    let boundary: String
    let expectedContract: String
    let admit: () throws -> HeistPlan
}

private let deeplyNestedSource: String = {
    let nesting = 17
    return """
    HeistPlan {
    \(String(repeating: "If(.exists(.label(\"Home\"))) {\n", count: nesting))
    Warn("nested")
    \(String(repeating: "}\n", count: nesting))
    }
    """
}()

func structurallyAdmittedPlan(
    name: HeistPlanName? = nil,
    parameter: HeistParameter = .none,
    definitions: [HeistPlan] = [],
    body: [HeistStep] = []
) -> HeistPlan {
    do {
        return try HeistPlan(
            structuralVersion: HeistPlan.currentVersion,
            name: name,
            parameter: parameter,
            definitions: definitions,
            body: body
        )
    } catch {
        preconditionFailure("test plan structure must be admitted: \(error)")
    }
}

func admitRuntimeSafety(
    _ plan: HeistPlan,
    limits: HeistPlanRuntimeSafetyLimits = .standard
) throws -> HeistPlan {
    var validator = HeistPlanRuntimeSafetyValidator(limits: limits)
    return try validator.admit(plan)
}

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
    let duplicate = structurallyAdmittedPlan(definitions: [
        structurallyAdmittedPlan(name: "checkout", body: [.warn(WarnStep(message: "one"))]),
        structurallyAdmittedPlan(name: "checkout", body: [.warn(WarnStep(message: "two"))]),
    ], body: [.warn(WarnStep(message: "root"))])
    try expectSemanticDiagnostic(
        duplicate,
        path: "$.definitions[1].name",
        message: "duplicate heist definition names are not allowed in the same scope"
    )

    let unresolved = structurallyAdmittedPlan(body: [
        .invoke(HeistInvocationStep(path: "Missing")),
    ])
    try expectSemanticDiagnostic(
        unresolved,
        path: "$.body[0].invoke.path",
        message: "heist run path must resolve to a local capability"
    )

    let recursive = structurallyAdmittedPlan(definitions: [
        structurallyAdmittedPlan(name: "lib", definitions: [
            structurallyAdmittedPlan(name: "a", body: [
                .invoke(HeistInvocationStep(path: "lib.b")),
            ]),
            structurallyAdmittedPlan(name: "b", body: [
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
        let diagnostic = try semanticDiagnostic(testCase.candidate)
        #expect(diagnostic.code == .planRuntimeSafety)
        #expect(diagnostic.title == "Plan semantic validation failed")
        #expect(diagnostic.phase == .planValidation)
        #expect(diagnostic.path == testCase.path)
        #expect(diagnostic.message == "collection loops must not be nested; observed \(testCase.observed)")
        #expect(diagnostic.hint == "Flatten this heist so ForEach bodies contain only non-collection steps.")
    }
}

private func nestedCollectionLoopCases() throws -> [(candidate: HeistPlan, path: String, observed: String)] {
    [
        (
            structurallyAdmittedPlan(body: [admissionStep(try stringLoop(parameter: "item", body: [
                try stringLoop(parameter: "size"),
            ]))]),
            "$.body[0].for_each_string.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
        (
            structurallyAdmittedPlan(body: [admissionStep(try stringLoop(parameter: "rowName", body: [
                try elementLoop(parameter: "rowTarget"),
            ]))]),
            "$.body[0].for_each_string.body[0].for_each_element",
            "for_each_element inside collection loop"
        ),
        (
            structurallyAdmittedPlan(body: [admissionStep(try elementLoop(parameter: "section", body: [
                try stringLoop(parameter: "size"),
            ]))]),
            "$.body[0].for_each_element.body[0].for_each_string",
            "for_each_string inside collection loop"
        ),
        (
            structurallyAdmittedPlan(body: [admissionStep(try elementLoop(parameter: "section", body: [
                try elementLoop(parameter: "row"),
            ]))]),
            "$.body[0].for_each_element.body[0].for_each_element",
            "for_each_element inside collection loop"
        ),
        (
            structurallyAdmittedPlan(
                definitions: [
                    structurallyAdmittedPlan(name: "Inner", body: [admissionStep(try stringLoop(parameter: "size"))]),
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

private func admissionStep(_ step: HeistStep) -> HeistStep {
    step
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
    _ candidate: HeistPlan,
    path expectedPath: String,
    message expectedMessage: String
) throws {
    let diagnostic = try semanticDiagnostic(candidate)

    #expect(diagnostic.code == .planRuntimeSafety)
    #expect(diagnostic.title == "Plan semantic validation failed")
    #expect(diagnostic.phase == .planValidation)
    #expect(diagnostic.path == expectedPath)
    #expect(diagnostic.message.contains(expectedMessage))
    #expect(diagnostic.hint != nil)
}

private func semanticDiagnostic(_ candidate: HeistPlan) throws -> HeistBuildDiagnostic {
    do {
        _ = try admitRuntimeSafety(candidate)
        throw LanguageContractFailure.expectedSemanticFailure
    } catch let error as HeistPlanRuntimeSafetyError {
        return try #require(error.diagnostics.first)
    }
}

private enum LanguageContractFailure: Error {
    case expectedSemanticFailure
}
