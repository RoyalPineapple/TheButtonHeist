import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Canonical runtime ownership")
struct CanonicalRuntimeOwnerRuleTests {
    @Test
    func canonicalOwnersSatisfyRuntimeRules() throws {
        let report = try evaluateButtonHeistRules()

        #expect(report.violations.isEmpty)
    }

    @Test
    func predicateWaitLifecycleConstructionOutsideExecutorIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingWait.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "func runWait() { _ = PredicateWaitLifecycleMachine() }"
        )

        expectOnlyViolation(
            in: report,
            id: "buttonheist.predicate_wait_lifecycle_ownership",
            path: path
        )
    }

    @Test
    func directInterfaceTreeMatchingOutsideOwnersIsRejected() throws {
        let path: RelativeFilePath =
            "ButtonHeist/Sources/TheInsideJob/TheBrains/CompetingMatcher.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: """
            func match() {
                matchingTreeElements()
                matchingTreeContainers()
            }
            """
        )

        #expect(report.violations.count == 2)
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.interface_tree_element_matching_ownership",
            path: path
        )))
        #expect(report.contains(ViolationMatcher(
            id: "buttonheist.interface_tree_container_matching_ownership",
            path: path
        )))
    }

    private func expectOnlyViolation(
        in report: RuleReport,
        id: RuleID,
        path: RelativeFilePath
    ) {
        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(id: id, path: path)))
    }
}
