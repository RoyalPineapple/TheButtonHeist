import ButtonHeist

@main
struct ButtonHeistImportContract {
    static func main() throws {
        _ = try makePlan()
    }

    static func makePlan() throws -> HeistPlan {
        let payTarget: AccessibilityTarget = .label("Pay")
        let checkoutContainer: AccessibilityTarget = .container(.label("Checkout"))
        let currentPredicate: AccessibilityPredicate = .exists(payTarget)
        let containerPredicate: AccessibilityPredicate = .exists(checkoutContainer)
        let updatedPredicate: ElementAssertion = .updated(
            payTarget,
            .value("Paid")
        )
        let changedPredicate: AccessibilityPredicate = .elementsChanged([updatedPredicate])
        _ = (currentPredicate, containerPredicate, changedPredicate)

        return try HeistPlan("external-import-contract") {
            Activate(.label("Pay")).expect(.screenChanged)
        }
    }
}
