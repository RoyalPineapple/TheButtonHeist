import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans
@testable import TheScore

private let nonDurableHeistActionRepairHint =
    "Use a direct client command for viewport/debug/session actions, or replace " +
    "this with a canonical durable DSL action."

private func expectNonDurableHeistActionFailure(
    _ failures: [HeistPlanRuntimeSafetyFailure],
    observed: String,
    path: String = "$.body[0].action.command"
) {
    #expect(failures.contains {
        $0.path.description == path
            && $0.contract == "durable heist action"
            && $0.observed == observed
            && $0.correction == nonDurableHeistActionRepairHint
    }, "\(failures)")
}

@Test
func runtimeSafetyRejectsInvalidRefs() throws {
    let tooLong = String(repeating: "a", count: HeistPlanRuntimeSafetyLimits.standard.maxParameterBytes + 1)
    let cases: [(String, HeistPlanAdmissionCandidate, String)] = [
        (
            "unknown target ref",
            HeistPlanAdmissionCandidate(body: [.action(ActionStep(command: .activate(.ref("target"))))]),
            "target ref must resolve"
        ),
        (
            "unknown text ref",
            HeistPlanAdmissionCandidate(body: [.action(ActionStep(command: .typeText(
                reference: "item",
                target: .predicate(.label("Search"))
            )))]),
            "text_ref must resolve"
        ),
        (
            "long target ref",
            HeistPlanAdmissionCandidate(body: [.action(ActionStep(command: .activate(.ref(
                try HeistReferenceName(validating: tooLong)
            ))))]),
            "max parameter/ref length"
        ),
    ]

    for (label, raw, expected) in cases {
        let failures = runtimeSafetyFailures(for: raw)
        #expect(failures.contains { $0.contract.contains(expected) }, "\(label): \(failures)")
    }
}

@Test
func heistPlanConstructionRejectsNonDurableActions() throws {
    let command = HeistActionCommand.rotor(
        selection: .index(0),
        target: .predicate(.label("Article")),
        direction: .next
    )
    let expectedFailure = try #require(command.durableHeistActionFailure)

    do {
        _ = try HeistPlan(body: [.action(ActionStep(command: command))])
        Issue.record("Expected non-durable action to fail plan construction")
    } catch let error as HeistPlanRuntimeSafetyError {
        expectNonDurableHeistActionFailure(error.failures, observed: expectedFailure)
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
    }
}

@Test
func heistPlanJSONDecodeRejectsNonDurableActions() throws {
    let expectedFailure = try #require(
        HeistActionCommand
            .viewportScroll(ScrollTarget(selection: .container("scrollable_0_0_40_50"), direction: .down))
            .durableHeistActionFailure
    )
    let json = """
    {
      "version": \(HeistPlan.currentVersion),
      "body": [
        {
          "type": "action",
          "action": {
            "command": {
              "type": "scroll",
              "payload": {
                "containerName": "scrollable_0_0_40_50",
                "direction": "down"
              }
            }
          }
        }
      ]
    }
    """

    do {
        _ = try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))
        Issue.record("Expected non-durable JSON action to fail plan decode")
    } catch let error as HeistPlanRuntimeSafetyError {
        expectNonDurableHeistActionFailure(error.failures, observed: expectedFailure)
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
    }
}

@Test
func runtimeSafetyRejectsRefsOutsideTheirLoopScope() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .forEachString(try ForEachStringStep(
            values: ["Milk"],
            parameter: "item",
            body: [.warn(WarnStep(message: "inside string loop"))]
        )),
        .action(ActionStep(command: .typeText(
            reference: "item",
            target: .predicate(.label("Search"))
        ))),
        .forEachElement(try ForEachElementStep(
            matching: .label("Delete"),
            limit: 1,
            parameter: "target",
            body: [.warn(WarnStep(message: "inside element loop"))]
        )),
        .action(ActionStep(command: .activate(.ref("target")))),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    #expect(failures.contains {
        $0.path.description == "$.body[1].action.command.payload.text_ref"
            && $0.contract == "text_ref must resolve in the current heist scope"
    })
    #expect(failures.contains {
        $0.path.description == "$.body[3].action.command.payload.target"
            && $0.contract == "target ref must resolve in the current heist scope"
    })
}

@Test
func runtimeSafetyRejectsStringRefThatLowersToInvalidCommandPayload() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .forEachString(try ForEachStringStep(
            values: [""],
            parameter: "item",
            body: [
                .action(ActionStep(command: .typeText(
                    reference: "item",
                    target: .predicate(.label("Search"))
                ))),
            ]
        )),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    #expect(failures.contains { $0.contract.contains("admissible action command") })
    #expect(failures.contains { $0.observed.contains("text to append must be non-empty") })
}

@Test
func runtimeSafetyRejectsEmptyBroadConcreteAccessibilityTargets() throws {
    let targets: [(String, AccessibilityTarget)] = [
        ("label exact", .label("")),
        ("label contains", .label(.contains(""))),
        ("label prefix", .label(.prefix(""))),
        ("label suffix", .label(.suffix(""))),
        ("identifier exact", .identifier("")),
        ("identifier contains", .identifier(.contains(""))),
        ("identifier prefix", .identifier(.prefix(""))),
        ("identifier suffix", .identifier(.suffix(""))),
        ("value exact", .value("")),
        ("value contains", .value(.contains(""))),
        ("value prefix", .value(.prefix(""))),
        ("value suffix", .value(.suffix(""))),
        ("hint exact", .hint("")),
        ("traits empty", .traits([])),
        ("actions empty", .actions([])),
        ("custom content empty", .customContent(CustomContentMatch())),
        ("rotors empty", .rotors([])),
    ]

    for (label, target) in targets {
        let raw = HeistPlanAdmissionCandidate(body: [
            .action(ActionStep(command: .activate(target))),
        ])

        let failures = runtimeSafetyFailures(for: raw)

        #expect(
            failures.contains { $0.contract.contains("element predicate") },
            "\(label): \(failures)"
        )
    }
}

@Test
func runtimeSafetyRejectsNegativeOrdinalsBeforeRuntimeUse() throws {
    let concreteRaw = HeistPlanAdmissionCandidate(body: [
        .action(ActionStep(command: .activate(.predicate(.label("Save"), ordinal: -1)))),
    ])
    let expressionRaw = HeistPlanAdmissionCandidate(body: [
        .action(ActionStep(command: .activate(.predicate(.label("Save"), ordinal: -1)))),
    ])

    for raw in [concreteRaw, expressionRaw] {
        let failures = runtimeSafetyFailures(for: raw)

        #expect(failures.contains {
            $0.contract == "ordinal must be non-negative"
                && $0.observed == "-1"
        }, "\(failures)")
    }
}

@Test
func runtimeSafetyRejectsEmptyElementPredicatesBeforeRuntimeUse() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .wait(WaitStep(predicate: .exists(.predicate(ElementPredicateTemplate())))),
    ])

    let failures = runtimeSafetyFailures(for: raw)

    #expect(failures.contains {
        $0.contract == "element predicate must not be empty"
            && $0.observed.contains("AccessibilityTarget predicate requires")
    }, "\(failures)")
}
