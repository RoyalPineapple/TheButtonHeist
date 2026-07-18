import ThePlans

@main
struct ThePlansAuthoringImportContract {
    static func main() throws {
        _ = try HeistPlan("theplans-authoring-import-contract") {
            Activate(.label("Pay"))
                .expect(.changed(.screen()), timeout: 2)

            TypeText("milk", into: .element(.label("Search"), .traits([.searchField])))
                .expect(.exists(.element(.label("Search"), .value("milk"))), timeout: 2)

            DismissKeyboard()
                .withoutExpectation("The keyboard may already be absent")

            Increment(.label("Quantity"))
                .until(.exists(.value("2")), timeout: 2)

            ForEach(.element(.label("Delete"), .traits([.button])), limit: 2) { target in
                Activate(target)
            }

            Warn("done")
        }
    }
}
