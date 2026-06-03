import Foundation
import Testing
@testable import TheScore

@Test
func actionStepExpectationWaiverRoundTrips() throws {
    let step = try ActionStep(
        command: .activate(.predicate(.label("Save"))),
        expectationWaiver: "No durable semantic outcome"
    )

    let data = try JSONEncoder().encode(step)
    let object = try JSONSerialization.jsonObject(with: data)
    let json = try #require(object as? [String: Any])
    let decoded = try JSONDecoder().decode(ActionStep.self, from: data)

    #expect(json["without_expectation"] as? String == "No durable semantic outcome")
    #expect(decoded == step)
}

@Test
func actionStepRejectsExpectationAndWaiverTogether() {
    let json = """
    {
      "command": {
        "type": "activate",
        "payload": {"label": "Save"}
      },
      "expectation": {
        "predicate": {"type": "present", "element": {"label": "Done"}},
        "timeout": 1
      },
      "without_expectation": "not needed"
    }
    """

    do {
        _ = try JSONDecoder().decode(ActionStep.self, from: Data(json.utf8))
        Issue.record("Expected action step with expectation and waiver to fail")
    } catch {
        #expect("\(error)".contains("ambiguousExpectationContract"))
    }
}

@Test
func strictValidationRequiresSemanticActionExpectation() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .activate(.predicate(.label("Save"))))),
    ])

    let findings = plan.validate(.strictTest)

    #expect(findings == [
        HeistPlanValidationFinding(
            severity: .error,
            path: "$.steps[0].action",
            message: "Semantic action has no expectation",
            suggestion: "Attach .expect(...) or .withoutExpectation(\"reason\")"
        ),
    ])
}

@Test
func recordingQualityAllowsExplicitExpectationWaiver() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectationWaiver: "No durable semantic outcome"
        )),
    ])

    #expect(plan.validate(.recordingQuality).isEmpty)
    #expect(plan.validate(.strictTest).isEmpty)
}

@Test
func validationFlagsMechanicalCommandsAndViewportSetup() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 10, y: 20)))))),
        .action(try ActionStep(command: .scroll(ScrollTarget(direction: .down)))),
        .action(try ActionStep(
            command: .activate(.predicate(.label("Save"))),
            expectation: WaitStep(predicate: .state(.present(.label("Done"))), timeout: 1)
        )),
    ])

    let messages = plan.validate(.strictTest).map(\.message)

    #expect(messages.contains("Mechanical command appears in strict semantic-test mode"))
    #expect(messages.contains("Viewport command appears in strict semantic-test mode"))
    #expect(messages.contains("Viewport setup immediately precedes a semantic action"))
}

@Test
func validationReportsTypeTextWithoutTarget() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .typeText(TypeTextTarget(text: "milk")))),
    ])

    let findings = plan.validate(.recordingQuality)

    #expect(findings == [
        HeistPlanValidationFinding(
            severity: .warning,
            path: "$.steps[0].action",
            message: "TypeText has no semantic target",
            suggestion: "Use TypeText(text, into: target) for durable semantic tests"
        ),
    ])
}

@Test
func validationReportsEmptyBranchesAndLargeForEachLimit() throws {
    let matching = ElementPredicate.label("Delete")
    let plan = HeistPlan(steps: [
        .conditional(try ConditionalStep(cases: [
            PredicateCase(predicate: .state(.present(.label("Home"))), steps: []),
        ])),
        .forEachElement(try ForEachElementStep(
            matching: matching,
            limit: 101,
            parameter: "target",
            steps: [.warn(WarnStep(message: "too many"))]
        )),
    ])

    let messages = plan.validate(.strictTest).map(\.message)

    #expect(messages.contains("Branch has no steps"))
    #expect(messages.contains("ForEach limit is too large for a durable semantic heist"))
}

@Test
func runtimeValidationDoesNotEnforceRecordingQuality() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .activate(.predicate(.label("Save"))))),
    ])

    #expect(plan.validate(.runtime).isEmpty)
}
