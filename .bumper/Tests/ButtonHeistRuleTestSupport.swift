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
        "ButtonHeist/Sources/TheInsideJob/TheBrains/PredicateWait.swift",
        component: ButtonHeistComponent.runtime,
        source: "func runWait() { _ = PredicateWaitLifecycleMachine() }"
    ),
    .swift(
        "ButtonHeist/Sources/TheInsideJob/TheStash/TheStash+Matching.swift",
        component: ButtonHeistComponent.runtime,
        source: """
        func recurse() {
            matchingTreeElements()
            matchingTreeContainers()
        }
        """
    ),
]
