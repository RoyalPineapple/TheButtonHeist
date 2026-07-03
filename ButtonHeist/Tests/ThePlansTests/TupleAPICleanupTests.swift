import Testing
@testable import ThePlans

@Test
func `parser helpers expose named result values`() {
    let branches = ParsedPredicateBranches(cases: [], elseBody: nil)
    #expect(branches.cases.isEmpty)
    #expect(branches.elseBody == nil)

    let closure = ParsedClosureParameterBlock(referenceName: "item", body: [])
    #expect(closure.referenceName.rawValue == "item")
    #expect(closure.body.isEmpty)

    let definitionHeader = HeistDefinitionHeader(path: "Checkout.Pay", parameter: .none)
    #expect(definitionHeader.path == "Checkout.Pay")
    #expect(definitionHeader.parameter == .none)

    let planHeader = HeistPlanHeader(name: "Checkout", parameter: .none)
    #expect(planHeader.name == "Checkout")
    #expect(planHeader.parameter == .none)

    let fields = PropertyChangeFields(before: "old", after: "new")
    #expect(fields.before == "old")
    #expect(fields.after == "new")

    let token = HeistPlanSourceToken(
        kind: .identifier("exact"),
        sourceName: "test",
        marker: HeistPlanSourceMarker(offset: 0, line: 1, column: 1, length: 5)
    )
    let labelToken = StringMatchModeLabelToken(name: "exact", token: token)
    #expect(labelToken.name == "exact")
    #expect(labelToken.token == token)
}
