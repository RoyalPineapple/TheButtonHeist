import ButtonHeist

@main
struct ButtonHeistImportContract {
    static func main() throws {
        _ = try makePlan()
    }

    static func makePlan() throws -> HeistPlan {
        let payTarget: AccessibilityTarget = .label("Pay")
        let checkoutContainer: AccessibilityTarget = .container(.label("Checkout"))
        let currentPredicate: AccessibilityPredicate<RootContext> = .exists(payTarget)
        let containerPredicate: AccessibilityPredicate<RootContext> = .exists(checkoutContainer)
        let updatedPredicate: AccessibilityPredicate<ElementsAssertionContext> = .updated(
            payTarget,
            .value("Paid")
        )
        let changedPredicate: AccessibilityPredicate<RootContext> = .changed(.elements([updatedPredicate]))
        let noChangePredicate: AccessibilityPredicate<RootContext> = .noChange
        _ = (currentPredicate, containerPredicate, changedPredicate, noChangePredicate)

        return try HeistPlan("external-import-contract") {
            Activate(.label("Pay")).expect(.changed(.screen()))
        }
    }
}
