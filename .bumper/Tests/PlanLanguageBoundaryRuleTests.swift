import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Plan language boundaries")
struct PlanLanguageBoundaryRuleTests {
    @Test
    func heistContentDoesNotExposeStoredBookkeeping() throws {
        let valid = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/ThePlans/HeistContent.swift",
            component: .plans,
            source: "public struct HeistContent { let steps: [Int] }"
        )
        let invalid = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/ThePlans/PublicHeistContent.swift",
            component: .plans,
            source: "public struct HeistContent { public let steps: [Int] }"
        )

        #expect(valid.violations.isEmpty)
        #expect(invalid.contains(ViolationMatcher(
            id: "buttonheist.heist_content_opacity",
            path: "ButtonHeist/Sources/ThePlans/PublicHeistContent.swift"
        )))
    }

    @Test
    func onlyWaitAndConditionalFragmentsExposeElse() throws {
        let valid = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/ThePlans/HeistControl.swift",
            component: .plans,
            source: """
            public struct WaitFor {
                public func `else`() {}
            }
            public struct IfContent {
                public func `else`() {}
            }
            """
        )
        let invalid = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/ThePlans/RepeatUntil.swift",
            component: .plans,
            source: """
            public struct RepeatUntil {
                public func `else`() {}
            }
            """
        )

        #expect(valid.violations.isEmpty)
        #expect(invalid.contains(ViolationMatcher(
            id: "buttonheist.plan_else_ownership",
            path: "ButtonHeist/Sources/ThePlans/RepeatUntil.swift"
        )))
    }

    @Test
    func exportedFunctionsReturnNamedContractsInsteadOfTuples() throws {
        let valid = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheScore/NamedResult.swift",
            component: .score,
            source: """
            public struct NamedResult {}
            public func admit() -> NamedResult { NamedResult() }
            func scratch() -> (left: Int, right: Int) { (1, 2) }
            """
        )
        let invalid = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheScore/TupleResult.swift",
            component: .score,
            source: """
            package func admit() -> (path: String, ordinal: Int) { ("$", 0) }
            """
        )

        #expect(valid.violations.isEmpty)
        #expect(invalid.contains(ViolationMatcher(
            id: "buttonheist.exported_tuple_return",
            path: "ButtonHeist/Sources/TheScore/TupleResult.swift"
        )))
    }
}
