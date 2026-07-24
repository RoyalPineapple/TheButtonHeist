import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans
@testable import TheScore

private struct EncodedActionStepContract: Decodable {
    let withoutExpectation: String

    private enum CodingKeys: String, CodingKey {
        case withoutExpectation = "without_expectation"
    }
}

private func invalidForEachElementJSON(parameter: String) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "version": HeistPlan.currentVersion,
        "body": [[
            "type": "for_each_element",
            "for_each_element": [
                "matching": ["checks": [["kind": "label", "match": "Delete"]]],
                "limit": 1,
                "parameter": parameter,
                "body": [["type": "warn", "warn": ["message": "body"]]],
            ],
        ]],
    ])
}

@Test
func actionStepExpectationWaiverRoundTrips() throws {
    let step = ActionStep(
        command: .activate(.predicate(.label("Save"))),
        expectationPolicy: .waived("No durable semantic outcome"))

    let data = try JSONEncoder().encode(step)
    let json = try JSONDecoder().decode(EncodedActionStepContract.self, from: data)
    let decoded = try JSONDecoder().decode(ActionStep.self, from: data)

    #expect(json.withoutExpectation == "No durable semantic outcome")
    #expect(decoded == step)
}

@Test
func actionStepRejectsExpectationAndWaiverTogether() {
    let json = """
    {
      "command": {
        "type": "activate",
        "payload": {"target": {"checks": [{"kind": "label", "match": {"mode": "exact", "value": "Save"}}]}}
      },
      "expectation": {
        "predicate": {
          "type": "exists",
          "target": {
            "checks": [{ "kind": "label", "match": { "mode": "exact", "value": "Done" } }]
          }
        },
        "timeout": 1
      },
      "without_expectation": "not needed"
    }
    """

    do {
        _ = try JSONDecoder().decode(ActionStep.self, from: Data(json.utf8))
        Issue.record("Expected action step with expectation and waiver to fail")
    } catch {
        #expect("\(error)".contains("action step cannot include both expectation and without_expectation"))
    }
}

@Test
func strictValidationRequiresSemanticActionExpectation() throws {
    let plan = try HeistPlan(body: [
        .action(ActionStep(command: .activate(.predicate(.label("Save"))))),
    ])

    let findings = plan.lint(.strictTest)

    let finding = try #require(findings.first)
    #expect(findings.count == 1)
    #expect(finding.severity == .error)
    #expect(finding.path.description == "$.body[0].action")
    #expect(finding.message == "Semantic action has no expectation")
    #expect(finding.suggestion == "Attach .expect(...) or .withoutExpectation(\"reason\")")
}

@Test
func `composition quality allows explicit expectation waiver`() throws {
    let plan = try HeistPlan(body: [
        .action(ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectationPolicy: .waived("No durable semantic outcome"))),
    ])

    #expect(plan.lint(.compositionQuality).isEmpty)
    #expect(plan.lint(.strictTest).isEmpty)
}

@Test
func lintFlagsSpatialGestureCommands() throws {
    let plan = try HeistPlan(body: [
        .action(ActionStep(command: .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))))),
        .action(ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectationPolicy: .expect(ActionExpectation(predicate: .exists(.label("Done")), timeout: 1)))),
    ])

    let messages = plan.lint(.strictTest).map(\.message)

    #expect(messages.contains("Spatial gesture command appears in strict semantic-test mode"))
}

@Test
func lintReportsTypeTextWithoutTarget() throws {
    let plan = try HeistPlan(body: [
        .action(ActionStep(command: .typeText(text: "milk", target: nil))),
    ])

    let findings = plan.lint(.compositionQuality)

    let finding = try #require(findings.first)
    #expect(findings.count == 1)
    #expect(finding.severity == .warning)
    #expect(finding.path.description == "$.body[0].action")
    #expect(finding.message == "TypeText has no semantic target")
    #expect(finding.suggestion == "Use TypeText(text, into: target) for durable semantic tests")
}

@Test
func lintReportsEmptyBranches() throws {
    let plan = try HeistPlan(body: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .exists(.label("Home")), body: []),
        ])),
    ])

    let messages = plan.lint(.strictTest).map(\.message)

    #expect(messages == ["Branch has no steps"])
    #expect(plan.lint(.strictTest).map(\.path.description) == ["$.body[0].conditional.cases[0]"])
}

@Test
func admissionDecodingRejectsInvalidLoopParameters() throws {
    let invalidParameters = [
        "",
        " ",
        "target-name",
        "target name",
        "class",
        "../target",
        "target\nname",
        "target\0name",
    ]

    for parameter in invalidParameters {
        let data = try invalidForEachElementJSON(parameter: parameter)

        #expect(throws: (any Error).self) {
            _ = try JSONDecoder().decode(HeistPlan.self, from: data)
        }
    }
}
