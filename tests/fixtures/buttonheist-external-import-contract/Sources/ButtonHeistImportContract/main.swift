import ButtonHeist

@main
struct ButtonHeistImportContract {
    static func main() throws {
        _ = try makePlan()
    }

    static func makePlan() throws -> HeistPlan {
        let payTarget: ElementTarget = .label("Pay")
        let currentPredicate: AccessibilityPredicate = .state(.existsTarget(payTarget))
        let changedPredicate: AccessibilityPredicate = .change(.screenChanged)
        _ = (currentPredicate, changedPredicate)

        return try HeistPlan("external-import-contract") {
            Activate(.label("Pay")).expect(.change(.screenChanged))
        }
    }
}
