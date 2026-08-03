import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Canonical pipeline ownership")
struct CanonicalPipelineOwnershipRuleTests {
    @Test
    func canonicalCurrenciesAreConstructedByTheirOwners() throws {
        let report = try evaluateButtonHeistRules(mutations: fixtures.map { fixture in
            VirtualSourceFile.swift(
                fixture.ownerPath,
                component: fixture.component,
                source: fixture.construction
            )
        })

        #expect(report.violations.isEmpty)
    }

    @Test
    func rogueCanonicalCurrencyConstructionFailsAtEachExactPath() throws {
        let report = try evaluateButtonHeistRules(mutations: fixtures.map { fixture in
            VirtualSourceFile.swift(
                fixture.roguePath,
                component: fixture.component,
                source: fixture.construction
            )
        })

        #expect(report.violations.count == fixtures.count)
        for fixture in fixtures {
            #expect(report.contains(ViolationMatcher(
                id: fixture.ruleID,
                path: fixture.roguePath
            )))
        }
    }

    private var fixtures: [Fixture] {
        [
            Fixture(
                ownerPath: "ButtonHeist/Sources/TheInsideJob/TheSafecracker/SafecrackerTouchInjection.swift",
                roguePath: "ButtonHeist/Sources/TheInsideJob/TheSafecracker/RogueTouchEventConstruction.swift",
                component: .embeddedRuntime,
                ruleID: "buttonheist.touch_event_construction",
                construction: """
                extension TheSafecracker {
                    @MainActor
                    func constructTouchEvent() {
                        _ = TouchEvent(touches: [])
                    }
                }
                """
            ),
            Fixture(
                ownerPath: "ButtonHeist/Sources/ThePlans/Compilation/HeistSwiftCompiler.swift",
                roguePath: "ButtonHeist/Sources/ThePlans/Compilation/RogueHeistSwiftFileCompilation.swift",
                component: .plans,
                ruleID: "buttonheist.swift_plan_compilation_construction",
                construction: """
                func constructSwiftCompilation() {
                    _ = HeistSwiftFileCompilation()
                }
                """
            ),
            Fixture(
                ownerPath: "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+RunHeist.swift",
                roguePath: "ButtonHeist/Sources/TheButtonHeist/TheFence/RogueHeistExecutionBudget.swift",
                component: .client,
                ruleID: "buttonheist.heist_execution_budget_construction",
                construction: """
                extension TheFence {
                    func constructBudget() {
                        _ = HeistExecutionBudget(
                            serverTimeout: fatalError(),
                            transportTimeout: fatalError(),
                            actionExpectationTimeoutPolicy: fatalError()
                        )
                    }
                }
                """
            ),
            Fixture(
                ownerPath: "ButtonHeist/Sources/TheScore/Reports/HeistResult+Report.swift",
                roguePath: "ButtonHeist/Sources/TheScore/Reports/RogueHeistReportConstruction.swift",
                component: .score,
                ruleID: "buttonheist.heist_report_construction",
                construction: """
                func constructReport() {
                    _ = HeistReport(
                        summary: fatalError(),
                        metrics: fatalError(),
                        nodes: fatalError(),
                        failure: fatalError(),
                        warnings: fatalError(),
                        diagnostics: fatalError()
                    )
                }
                """
            ),
        ]
    }

    private struct Fixture {
        let ownerPath: RelativeFilePath
        let roguePath: RelativeFilePath
        let component: ButtonHeistComponent
        let ruleID: RuleID
        let construction: String
    }
}
