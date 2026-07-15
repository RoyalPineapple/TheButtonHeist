import BumperBowlingCore
import BumperBowlingTestSupport

func evaluateButtonHeistRules(
    path: RelativeFilePath,
    component: ButtonHeistComponent,
    source: String
) throws -> RuleReport {
    try evaluateButtonHeistRules(mutations: [
        .swift(path, component: component, source: source),
    ])
}

func evaluateButtonHeistRules(
    mutations: [VirtualSourceFile] = []
) throws -> RuleReport {
    let mutatedPaths = Set(mutations.map(\.path))
    let files = canonicalButtonHeistRuleFixtures.filter {
        !mutatedPaths.contains($0.path)
    } + mutations
    return try RuleTestHarness(buttonHeistRules).evaluate(
        VirtualRepository(files: files)
    )
}

private let canonicalButtonHeistRuleFixtures: [VirtualSourceFile] = [
    .swift(
        "ButtonHeist/Sources/ThePlans/Model/StringExpressions.swift",
        component: ButtonHeistComponent.plans,
        source: "package enum Expr<Value> { case literal(Value) }"
    ),
    .swift(
        "ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationStream.swift",
        component: ButtonHeistComponent.runtime,
        source: """
        final class SemanticObservationLog {
            func publish(_ value: Int) {}
        }
        struct InterfaceObservationProof {}
        final class SemanticObservationStream {
            let observationLog = SemanticObservationLog()
            let stash: TheStash

            init(stash: TheStash) {
                self.stash = stash
            }

            func publishCommittedObservation(_ proof: InterfaceObservationProof) {
                stash.reduceInterfaceGraph()
                observationLog.publish(0)
            }
        }
        """
    ),
    .swift(
        "ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+InterfaceState.swift",
        component: ButtonHeistComponent.runtime,
        source: """
        final class TheStash {
            var interfaceTree = 0

            func reduceInterfaceGraph() {
                interfaceTree = 1
            }

            func clearInterfaceForLifecycleReset() {
                interfaceTree = 0
            }
        }
        """
    ),
]
