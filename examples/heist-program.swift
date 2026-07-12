import ThePlans

func heist() throws -> HeistPlan {
    try HeistPlan("searchFlow") {
        TypeText("milk", into: .label("Search"))
            .expect(.exists(.element(.label("Search"), .value("milk"))), timeout: .seconds(2))

        Activate(.label("Search"))
            .expect(.changed(.screen([.exists(.label("Results"))])), timeout: .seconds(5))

        WaitFor(.exists(.label("Results")), timeout: .seconds(5))
            .else {
                Fail("Search did not settle")
            }
    }
}
