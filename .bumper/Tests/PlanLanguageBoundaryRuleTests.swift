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
        #expect(valid.violations.isEmpty)

        let invalidCases: [(name: String, source: String)] = [
            (
                "function-parameter",
                "public func explicitFunction(_ input: (left: Int, right: Int)) -> Int { input.left }"
            ),
            (
                "nested-return",
                "package func nestedReturn() -> Result<(value: Int, ordinal: Int), Never> { .success((1, 0)) }"
            ),
            (
                "property",
                "public let explicitProperty: (value: Int, ordinal: Int) = (1, 0)"
            ),
            (
                "subscript-parameter",
                """
                public struct ExplicitSubscript {
                    public subscript(key: (section: Int, row: Int)) -> String { "" }
                }
                """
            ),
            (
                "protocol-function",
                "public protocol PublicContract { func requirement() -> (value: Int, ordinal: Int) }"
            ),
            (
                "protocol-property",
                "public protocol PublicContract { var property: (value: Int, ordinal: Int) { get } }"
            ),
            (
                "protocol-subscript",
                "public protocol PublicContract { subscript(index: Int) -> (value: Int, ordinal: Int) { get } }"
            ),
            (
                "package-protocol-parameter",
                "package protocol PackageContract { func requirement(_ input: (value: Int, ordinal: Int)) }"
            ),
            (
                "extension-function",
                """
                public struct ExtensionTarget {}
                public extension ExtensionTarget {
                    func inheritedFunction() -> (value: Int, ordinal: Int) { (1, 0) }
                }
                """
            ),
            (
                "extension-property",
                """
                public struct ExtensionTarget {}
                public extension ExtensionTarget {
                    var inheritedProperty: (value: Int, ordinal: Int) { (1, 0) }
                }
                """
            ),
            (
                "extension-subscript",
                """
                public struct ExtensionTarget {}
                public extension ExtensionTarget {
                    subscript(index: Int) -> (value: Int, ordinal: Int) { (index, 0) }
                }
                """
            ),
            (
                "package-extension-function",
                """
                public struct ExtensionTarget {}
                package extension ExtensionTarget {
                    func inheritedPackageFunction() -> (value: Int, ordinal: Int) { (1, 0) }
                }
                """
            ),
        ]

        for invalidCase in invalidCases {
            let path = try RelativeFilePath(
                "ButtonHeist/Sources/TheScore/ExportedTuples-\(invalidCase.name).swift"
            )
            let invalid = try evaluateButtonHeistRules(
                path: path,
                component: .score,
                source: invalidCase.source
            )

            #expect(invalid.violations.count == 1, "Expected one violation for \(invalidCase.name)")
            #expect(invalid.contains(ViolationMatcher(
                id: "buttonheist.exported_tuple_return",
                path: path
            )))
            #expect(invalid.violations.allSatisfy { violation in
                violation.location != nil && violation.evidence?.observed.contains("(") == true
            })
        }
    }
}
