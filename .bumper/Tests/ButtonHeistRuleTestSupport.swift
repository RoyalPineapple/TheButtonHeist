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
    mutations: [VirtualSourceFile]
) throws -> RuleReport {
    return try RuleTestHarness(buttonHeistRules).evaluate(
        VirtualRepository(files: mutations)
    )
}
