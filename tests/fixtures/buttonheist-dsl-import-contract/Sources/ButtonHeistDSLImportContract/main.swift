import ButtonHeistDSL

@main
struct ButtonHeistDSLImportContract {
    static func main() throws {
        _ = try HeistPlan("dsl-import-contract") {
            Activate(.label("Pay"))
                .expect(.screenChanged, timeout: .seconds(2))

            TypeText("milk", into: .element(.label("Search"), .traits([.searchField])))
                .expect(.exists(.element(.label("Search"), .value("milk"))), timeout: .seconds(2))

            ForEach(.matching(.element(.label("Delete"), .traits([.button]))), limit: 2) { target in
                Activate(target)
            }

            Warn("done")
        }
    }
}
