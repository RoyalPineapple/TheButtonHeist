import ButtonHeistTestSupport

private typealias FixtureJSON = PublicHeistJSONFixtureValue

enum PublicHeistControlFlowJSONFixture {
    static let caseSelection = FixtureJSON.object([
        "caseSelection": FixtureJSON.object([
            "outcome": FixtureJSON.object([
                "kind": FixtureJSON.string("matched_case"),
                "index": FixtureJSON.int(0),
            ]),
            "elapsedMs": FixtureJSON.int(4),
            "timeout": FixtureJSON.double(0.25),
            "lastObservedSummary": FixtureJSON.string("Ready visible"),
            "caseCount": FixtureJSON.int(2),
            "cases": FixtureJSON.array([FixtureJSON.readyCase]),
            "omittedCaseCount": FixtureJSON.int(1),
        ]),
    ])

    static let forEachString = FixtureJSON.object([
        "forEachString": FixtureJSON.object([
            "parameter": FixtureJSON.string("item"),
            "count": FixtureJSON.int(2),
            "iterationCount": FixtureJSON.int(1),
            "iterationOrdinal": FixtureJSON.int(0),
            "value": FixtureJSON.string("Milk"),
        ]),
    ])

    static let forEachElement = FixtureJSON.object([
        "forEachElement": FixtureJSON.object([
            "parameter": FixtureJSON.string("row"),
            "matching": FixtureJSON.target(label: "Row"),
            "limit": FixtureJSON.int(3),
            "matchedCount": FixtureJSON.int(2),
            "iterationCount": FixtureJSON.int(1),
            "iterationOrdinal": FixtureJSON.int(0),
            "targetOrdinal": FixtureJSON.int(1),
            "targetSummary": FixtureJSON.string("Row 2"),
        ]),
    ])

    static let repeatUntil = FixtureJSON.object([
        "repeatUntil": FixtureJSON.object([
            "outcome": FixtureJSON.string("matched"),
            "predicate": FixtureJSON.existsPredicate(label: "Done"),
            "timeout": FixtureJSON.double(0.5),
            "iterationCount": FixtureJSON.int(2),
            "expectation": FixtureJSON.doneExpectation,
            "result": FixtureJSON.actionResult(method: "wait", message: "repeat matched"),
            "lastObservedSummary": FixtureJSON.string("Done visible"),
        ]),
    ])
}
