import BumperBowlingCore
import BumperBowlingTestSupport

func evaluateButtonHeistRules(
    path: RelativeFilePath,
    component: ButtonHeistComponent,
    source: String
) throws -> RuleReport {
    try RuleTestHarness(buttonHeistRules).evaluate(
        VirtualRepository {
            VirtualSourceFile.swift(path, component: component, source: source)
        }
    )
}
