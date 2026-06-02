import Testing
import TheScore

@Test
func forEachBindingRewritesOnlyTheSentinelTarget() throws {
    let matching = ElementPredicate(label: "Delete", traits: [.button])
    let other = ElementPredicate(label: "Cancel", traits: [.button])

    let steps: [HeistStep] = [
        .action(try ActionStep(
            command: .activate(.predicate(matching, ordinal: 0)),
            expectation: WaitStep(
                predicate: .state(.absentTarget(.predicate(matching, ordinal: 0))),
                timeout: 2
            )
        )),
        .action(try ActionStep(command: .activate(.predicate(matching, ordinal: 1)))),
        .action(try ActionStep(command: .activate(.predicate(other, ordinal: 0)))),
    ]

    let lowered = try HeistPlanTransform.bindingForEachTarget(
        matching: matching,
        ordinal: 3,
        in: steps
    )

    #expect(lowered == [
        .action(try ActionStep(
            command: .activate(.predicate(matching, ordinal: 3)),
            expectation: WaitStep(
                predicate: .state(.absentTarget(.predicate(matching, ordinal: 3))),
                timeout: 2
            )
        )),
        .action(try ActionStep(command: .activate(.predicate(matching, ordinal: 1)))),
        .action(try ActionStep(command: .activate(.predicate(other, ordinal: 0)))),
    ])
}

@Test
func forEachBindingRewritesPredicateCasesAndGestures() throws {
    let matching = ElementPredicate(label: "Delete", traits: [.button])

    let steps: [HeistStep] = [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(
                    predicate: .state(.presentTarget(.predicate(matching, ordinal: 0))),
                    steps: [
                        .action(try ActionStep(command: .oneFingerTap(TapTarget(
                            selection: .element(.predicate(matching, ordinal: 0))
                        )))),
                    ]
                ),
            ],
            elseSteps: [
                .wait(WaitStep(
                    predicate: .state(.all([
                        .presentTarget(.predicate(matching, ordinal: 0)),
                        .absentTarget(.predicate(ElementPredicate(label: "Busy"), ordinal: 0)),
                    ])),
                    timeout: 1
                )),
            ]
        )),
        .waitForCases(try WaitForCasesStep(
            timeout: 5,
            cases: [
                PredicateCase(
                    predicate: .changed(.screen(where: .presentTarget(.predicate(matching, ordinal: 0)))),
                    steps: [
                        .action(try ActionStep(command: .scroll(ScrollTarget(
                            selection: .element(.predicate(matching, ordinal: 0)),
                            direction: .down
                        )))),
                    ]
                ),
            ]
        )),
    ]

    let lowered = try HeistPlanTransform.bindingForEachTarget(
        matching: matching,
        ordinal: 2,
        in: steps
    )

    #expect(lowered == [
        .conditional(try ConditionalStep(
            cases: [
                PredicateCase(
                    predicate: .state(.presentTarget(.predicate(matching, ordinal: 2))),
                    steps: [
                        .action(try ActionStep(command: .oneFingerTap(TapTarget(
                            selection: .element(.predicate(matching, ordinal: 2))
                        )))),
                    ]
                ),
            ],
            elseSteps: [
                .wait(WaitStep(
                    predicate: .state(.all([
                        .presentTarget(.predicate(matching, ordinal: 2)),
                        .absentTarget(.predicate(ElementPredicate(label: "Busy"), ordinal: 0)),
                    ])),
                    timeout: 1
                )),
            ]
        )),
        .waitForCases(try WaitForCasesStep(
            timeout: 5,
            cases: [
                PredicateCase(
                    predicate: .changed(.screen(where: .presentTarget(.predicate(matching, ordinal: 2)))),
                    steps: [
                        .action(try ActionStep(command: .scroll(ScrollTarget(
                            selection: .element(.predicate(matching, ordinal: 2)),
                            direction: .down
                        )))),
                    ]
                ),
            ]
        )),
    ])
}

@Test
func forEachBindingRejectsNestedRuntimeForEach() throws {
    let matching = ElementPredicate(label: "Delete", traits: [.button])
    let nested = try ForEachStep(
        matching: ElementPredicate(label: "Archive", traits: [.button]),
        limit: 5,
        steps: [.action(try ActionStep(command: .activate(.predicate(matching, ordinal: 0))))]
    )

    do {
        _ = try HeistPlanTransform.bindingForEachTarget(
            matching: matching,
            ordinal: 1,
            in: [.forEach(nested)]
        )
        Issue.record("Expected nested runtime ForEach binding to fail")
    } catch let error as HeistPlanTransformError {
        #expect(error == .nestedForEachBinding)
    }
}
