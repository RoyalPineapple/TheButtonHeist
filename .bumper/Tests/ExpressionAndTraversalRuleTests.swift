import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Expression and traversal ownership")
struct ExpressionAndTraversalRuleTests {
    @Test
    func expressionCurrencyHasOneOwnerWithoutReservingSuffix() throws {
        let validReport = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheScore/DisplayExpr.swift",
            component: .score,
            source: "enum DisplayExpr {}"
        )
        let invalidPath: RelativeFilePath = "ButtonHeist/Sources/TheScore/RogueExpr.swift"
        let invalidReport = try evaluateButtonHeistRules(
            path: invalidPath,
            component: .score,
            source: "enum Expr<Value> { case rogue(Value) }"
        )

        #expect(validReport.violations.isEmpty)
        #expect(invalidReport.violations.count == 1)
        #expect(invalidReport.contains(ViolationMatcher(
            id: "buttonheist.expr_ownership",
            path: invalidPath
        )))
    }

    @Test
    func planRecursionStaysWithTraversalOwners() throws {
        let recursiveSource = """
        func walk(step: HeistStep) {
            switch step {
            case .heist(let plan):
                for child in plan.body {
                    walk(step: child)
                }
            default:
                break
            }
        }
        """
        let validReport = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/ThePlans/Model/HeistPlanTraversal.swift",
            component: .plans,
            source: recursiveSource
        )
        let invalidPath: RelativeFilePath = "ButtonHeist/Sources/ThePlans/Rendering/RogueWalk.swift"
        let invalidReport = try evaluateButtonHeistRules(
            path: invalidPath,
            component: .plans,
            source: recursiveSource
        )

        #expect(validReport.violations.isEmpty)
        #expect(invalidReport.violations.count == 1)
        #expect(invalidReport.contains(ViolationMatcher(
            id: "buttonheist.canonical_plan_traversal",
            path: invalidPath
        )))
    }

    @Test
    func hierarchyRecursionStaysWithTraversalOwner() throws {
        let recursiveSource = """
        func walk(hierarchy: AccessibilityHierarchy) {
            switch hierarchy {
            case .container(_, let children):
                for child in children {
                    walk(hierarchy: child)
                }
            case .element:
                break
            }
        }
        """
        let validReport = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheScore/Core/AccessibilityHierarchy+Traversal.swift",
            component: .score,
            source: recursiveSource
        )
        let invalidPath: RelativeFilePath = "ButtonHeist/Sources/TheScore/Rendering/RogueWalk.swift"
        let invalidReport = try evaluateButtonHeistRules(
            path: invalidPath,
            component: .score,
            source: recursiveSource
        )

        #expect(validReport.violations.isEmpty)
        #expect(invalidReport.violations.count == 1)
        #expect(invalidReport.contains(ViolationMatcher(
            id: "buttonheist.canonical_accessibility_hierarchy_traversal",
            path: invalidPath
        )))
    }
}
