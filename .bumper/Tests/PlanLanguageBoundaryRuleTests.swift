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

    @Test
    func exportedTupleContractsCoverEveryAuditedDeclarationForm() throws {
        let valid = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheScore/TupleScratch.swift",
            component: .score,
            source: """
            public struct ExportedContainer {
                var internalByDefault: (left: Int, right: Int) { (1, 2) }
            }

            private func privateScratch(
                _ input: (left: Int, right: Int)
            ) -> (left: Int, right: Int) {
                input
            }

            func internalScratch() -> (left: Int, right: Int) { (1, 2) }

            public extension ExportedContainer {
                private var privateScratch: (left: Int, right: Int) { (1, 2) }
                internal subscript(index: (left: Int, right: Int)) -> (left: Int, right: Int) {
                    index
                }
            }

            private protocol PrivateScratch {
                var pair: (left: Int, right: Int) { get }
            }

            func useLocalScratch() {
                let local: (left: Int, right: Int) = (1, 2)
                func nested() -> (left: Int, right: Int) { local }
                _ = nested()
            }

            public func parenthesized(_ value: (Int)) -> (String) { String(value) }
            """
        )
        let invalidPath: RelativeFilePath = "ButtonHeist/Sources/TheScore/ExportedTuples.swift"
        let invalid = try evaluateButtonHeistRules(
            path: invalidPath,
            component: .score,
            source: """
            public func explicitFunction(
                _ input: (left: Int, right: Int)
            ) -> Int {
                input.left
            }

            package func nestedReturn() -> Result<(value: Int, ordinal: Int), Never> {
                .success((1, 0))
            }

            public let explicitProperty: (value: Int, ordinal: Int) = (1, 0)

            public struct ExplicitSubscript {
                public subscript(
                    key: (section: Int, row: Int)
                ) -> String {
                    String(key.section) + ":" + String(key.row)
                }
            }

            public protocol PublicContract {
                func requirement() -> (value: Int, ordinal: Int)
                var property: (value: Int, ordinal: Int) { get }
                subscript(index: Int) -> (value: Int, ordinal: Int) { get }
            }

            package protocol PackageContract {
                func requirement(_ input: (value: Int, ordinal: Int))
            }

            public struct ExtensionTarget {}

            public extension ExtensionTarget {
                func inheritedFunction() -> (value: Int, ordinal: Int) { (1, 0) }
                var inheritedProperty: (value: Int, ordinal: Int) { (1, 0) }
                subscript(index: Int) -> (value: Int, ordinal: Int) { (index, 0) }
            }

            package extension ExtensionTarget {
                func inheritedPackageFunction() -> (value: Int, ordinal: Int) { (1, 0) }
            }
            """
        )

        #expect(valid.violations.isEmpty)
        #expect(invalid.violations.count == 12)
        #expect(invalid.violations.allSatisfy { violation in
            violation.rule.id == "buttonheist.exported_tuple_return"
                && violation.location != nil
                && violation.evidence?.observed.contains("(") == true
        })
        #expect(invalid.contains(ViolationMatcher(
            id: "buttonheist.exported_tuple_return",
            path: invalidPath
        )))
    }
}
