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
}
