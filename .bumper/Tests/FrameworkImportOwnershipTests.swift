import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Framework import ownership")
struct FrameworkImportOwnershipTests {
    @Test
    func allowedComponentsOwnTheirFrameworkImports() throws {
        let fixtures: [(module: String, component: ButtonHeistComponent)] = [
            ("UIKit", .runtime),
            ("UIKit", .demo),
            ("SwiftUI", .runtime),
            ("SwiftUI", .demo),
            ("Network", .runtime),
            ("Network", .score),
            ("Security", .score),
            ("ObjectiveC", .runtime),
            ("ObjectiveC.runtime", .runtime),
            ("AccessibilitySnapshotCore", .runtime),
            ("AccessibilitySnapshotParser", .runtime),
            ("AccessibilitySnapshotPreviews", .runtime),
        ]

        for (index, fixture) in fixtures.enumerated() {
            let report = try evaluate(
                module: fixture.module,
                component: fixture.component,
                path: "Sources/Allowed/Fixture\(index).swift"
            )

            #expect(report.violations.isEmpty)
        }
    }

    @Test
    func foreignComponentsCannotImportBoundaryFrameworks() throws {
        let fixtures: [(module: String, ruleID: RuleID)] = [
            ("UIKit", "buttonheist.ui_framework_ownership"),
            ("SwiftUI", "buttonheist.ui_framework_ownership"),
            ("Network", "buttonheist.network_framework_ownership"),
            ("Security", "buttonheist.security_framework_ownership"),
            ("ObjectiveC", "buttonheist.objective_c_framework_ownership"),
            ("ObjectiveC.runtime", "buttonheist.objective_c_framework_ownership"),
            ("AccessibilitySnapshotCore", "buttonheist.accessibility_parser_ownership"),
            ("AccessibilitySnapshotParser", "buttonheist.accessibility_parser_ownership"),
            ("AccessibilitySnapshotPreviews", "buttonheist.accessibility_parser_ownership"),
        ]

        for (index, fixture) in fixtures.enumerated() {
            let path = try RelativeFilePath("Sources/Foreign/Fixture\(index).swift")
            let report = try evaluate(
                module: fixture.module,
                component: .tools,
                path: path.rawValue
            )

            #expect(report.violations.count == 1)
            #expect(report.contains(ViolationMatcher(id: fixture.ruleID, path: path)))
        }
    }

    private func evaluate(
        module: String,
        component: ButtonHeistComponent,
        path: String
    ) throws -> RuleReport {
        try evaluateButtonHeistRules(
            path: RelativeFilePath(path),
            component: component,
            source: "import \(module)"
        )
    }
}
