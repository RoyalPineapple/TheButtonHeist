import ButtonHeist

@main
struct ButtonHeistImportContract {
    static func main() throws {
        _ = try makePlan()
    }

    static func makePlan() throws -> HeistPlan {
        let payTarget: ElementTarget = .label("Pay")
        let currentPredicate: AccessibilityPredicate = .state(.presentTarget(payTarget))
        let changedPredicate: AccessibilityPredicate = .changed(.screen())
        _ = (currentPredicate, changedPredicate)

        return try HeistPlan("external-import-contract") {
            Activate(.label("Pay")).expect(.changed(.screen()))
        }
    }
}
