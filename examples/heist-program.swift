import ThePlans

func heist() throws -> HeistPlan {
    try HeistPlan("searchFlow") {
        TypeText("milk", into: .traits([.searchField]))
            .expect(.exists(.element(.traits([.searchField]), .value("milk"))))

        Activate(.element(.label("Search"), traits: [.button]))
            .expect(.screenChanged)

        WaitFor(.exists(.label("Results")), timeout: 5)
            .else {
                Fail("Search did not settle")
            }
    }
}
