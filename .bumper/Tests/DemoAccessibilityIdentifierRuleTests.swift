import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Demo accessibility identifier policy")
struct DemoAccessibilityIdentifierRuleTests {
    @Test
    func demoScreensCannotUseTestOnlyIdentifiers() throws {
        let path: RelativeFilePath = "TestApp/Sources/DashboardView.swift"
        let report = try evaluate(path: path, component: .demo)

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.demo_accessibility_identifier",
            path: path
        )))
    }

    @Test
    func researchFixturesAndNonDemoCodeRemainExempt() throws {
        let fixtures: [(path: RelativeFilePath, component: ButtonHeistComponent)] = [
            ("TestApp/Sources/ScrollSPIHarnessView.swift", .demo),
            ("TestApp/Sources/TraitProbeView.swift", .demo),
            ("TestApp/Sources/TraitValidationView.swift", .demo),
            ("ButtonHeist/Sources/TheInsideJob/Support/RuntimeView.swift", .runtime),
        ]

        for fixture in fixtures {
            let report = try evaluate(path: fixture.path, component: fixture.component)
            #expect(report.violations.isEmpty)
        }
    }

    private func evaluate(
        path: RelativeFilePath,
        component: ButtonHeistComponent
    ) throws -> RuleReport {
        try evaluateButtonHeistRules(
            path: path,
            component: component,
            source: "func configure(_ view: UIView) { view.accessibilityIdentifier = \"fixture\" }"
        )
    }
}
