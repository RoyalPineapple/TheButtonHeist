import BumperBowlingCore
import BumperBowlingTestSupport
import Testing

@Suite("Stored callback isolation")
struct CallbackIsolationRuleTests {
    @Test
    func storedCallbacksRequireExplicitIsolation() throws {
        let path: RelativeFilePath = "ButtonHeist/Sources/TheInsideJob/Client.swift"
        let report = try evaluateButtonHeistRules(
            path: path,
            component: .runtime,
            source: "struct Client { var onEvent: ((String) -> Void)? }"
        )

        #expect(report.violations.count == 1)
        #expect(report.contains(ViolationMatcher(id: "buttonheist.callback_isolation", path: path)))
    }

    @Test
    func actorAndSendableCallbacksAreExplicitlyIsolated() throws {
        let report = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheInsideJob/Client.swift",
            component: .runtime,
            source: """
            struct Client {
                var onEvent: (@Sendable (String) -> Void)?
                var onClose: (@MainActor () -> Void)?
            }
            """
        )

        #expect(report.violations.isEmpty)
    }

    @Test
    func fileLocalCallbackAliasesPreserveTheirIsolationContract() throws {
        let report = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheInsideJob/Callbacks.swift",
            component: .runtime,
            source: """
            typealias CheckedHandler = @Sendable (String) -> Void
            typealias LooseHandler = (String) -> Void
            struct Callbacks {
                var onChecked: CheckedHandler?
                var onLoose: LooseHandler?
            }
            """
        )

        #expect(report.violations.count == 1)
        #expect(report.violations.first?.rule.id == "buttonheist.callback_isolation")
        #expect(report.violations.first?.message.contains("onLoose") == true)
    }

    @Test
    func sameNamedNestedAliasesResolveInTheirLexicalType() throws {
        let report = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheInsideJob/Callbacks.swift",
            component: .runtime,
            source: """
            struct CheckedCallbacks {
                typealias Handler = @Sendable () -> Void
                var onEvent: Handler?
            }
            struct LooseCallbacks {
                typealias Handler = () -> Void
                var onEvent: Handler?
            }
            """
        )

        #expect(report.violations.count == 1)
        #expect(report.violations.first?.message.contains("onEvent") == true)
    }

    @Test
    func nestedSendableParametersDoNotIsolateTheStoredCallback() throws {
        let report = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheInsideJob/Callbacks.swift",
            component: .runtime,
            source: "struct Callbacks { var onEvent: (@Sendable () -> Void) -> Void }"
        )

        #expect(report.violations.count == 1)
    }

    @Test
    func genericOptionalCallbacksRemainVisibleToTheRule() throws {
        let report = try evaluateButtonHeistRules(
            path: "ButtonHeist/Sources/TheInsideJob/Callbacks.swift",
            component: .runtime,
            source: """
            typealias Handler = () -> Void
            struct Callbacks {
                var onDirect: Optional<() -> Void>
                var onAlias: Optional<Handler>
            }
            """
        )

        #expect(report.violations.count == 2)
    }
}
