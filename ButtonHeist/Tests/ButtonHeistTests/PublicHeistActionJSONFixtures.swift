import ButtonHeistTestSupport

private typealias FixtureJSON = PublicHeistJSONFixtureValue

enum PublicHeistActionJSONFixture {
    static let warningResponse = FixtureJSON.object([
        "status": FixtureJSON.string("ok"),
        "report": FixtureJSON.object([
            "summary": FixtureJSON.object([
                "executedTopLevelStepCount": FixtureJSON.int(1),
                "executedNodeCount": FixtureJSON.int(1),
                "outputNodeCount": FixtureJSON.int(1),
                "durationMs": FixtureJSON.int(1),
            ]),
            "metrics": FixtureJSON.object([
                "measurements": FixtureJSON.array([
                    FixtureJSON.object([
                        "name": FixtureJSON.string("heistDurationMs"),
                        "valueMs": FixtureJSON.int(1),
                    ]),
                ]),
                "ceilings": FixtureJSON.array([]),
            ]),
            "nodes": FixtureJSON.array([
                FixtureJSON.object([
                    "path": FixtureJSON.string("$.body[0]"),
                    "kind": FixtureJSON.string("warn"),
                    "status": FixtureJSON.string("passed"),
                    "message": FixtureJSON.string("heads up"),
                    "durationMs": FixtureJSON.int(1),
                    "evidence": FixtureJSON.object([
                        "warning": FixtureJSON.object([
                            "path": FixtureJSON.string("$.body[0]"),
                            "message": FixtureJSON.string("heads up"),
                        ]),
                    ]),
                    "children": FixtureJSON.array([]),
                ]),
            ]),
        ]),
    ])

    static let failure = FixtureJSON.object([
        "category": FixtureJSON.string("explicitFailure"),
        "contract": FixtureJSON.string("explicit heist failure"),
        "observed": FixtureJSON.string("stop"),
        "code": FixtureJSON.string("request.action_failed"),
        "kind": FixtureJSON.string("request"),
        "phase": FixtureJSON.string("request"),
        "retryable": FixtureJSON.bool(false),
    ])

    static let expectation = FixtureJSON.doneExpectation

    static let actionWithExpectation = FixtureJSON.object([
        "action": FixtureJSON.object([
            "commandName": FixtureJSON.string("dismiss"),
            "result": FixtureJSON.actionResult(method: "dismiss", message: "dismissed"),
            "expectationResult": FixtureJSON.actionResult(method: "wait", message: "matched"),
            "expectation": FixtureJSON.doneExpectation,
        ]),
    ])

    static let wait = FixtureJSON.object([
        "wait": FixtureJSON.matchedWaitEvidence,
    ])

    static let invocation = FixtureJSON.object([
        "invocation": FixtureJSON.object([
            "capability": FixtureJSON.string("Cart.checkout"),
            "argument": FixtureJSON.string(#"RunHeist("Cart.checkout", "Milk")"#),
            "expectationResult": FixtureJSON.waitResult,
            "expectation": FixtureJSON.doneExpectation,
            "expectationEvidence": FixtureJSON.matchedWaitEvidence,
        ]),
    ])

    static let omissions = FixtureJSON.object([
        "accessibilityTrace": FixtureJSON.object([
            "reason": FixtureJSON.string("raw accessibility trace omitted from public heist report"),
            "projectedAs": FixtureJSON.string("delta"),
            "omittedCount": FixtureJSON.int(2),
        ]),
        "subjectEvidence": FixtureJSON.object([
            "reason": FixtureJSON.string("raw subject evidence omitted from public heist report"),
        ]),
    ])

    static func netDelta(beforeHash: String, afterHash: String) -> JSONValue {
        FixtureJSON.object([
            "kind": FixtureJSON.string("elementsChanged"),
            "elementCount": FixtureJSON.int(1),
            "captureEdge": FixtureJSON.object([
                "before": FixtureJSON.object([
                    "sequence": FixtureJSON.int(1),
                    "hash": FixtureJSON.string(beforeHash),
                ]),
                "after": FixtureJSON.object([
                    "sequence": FixtureJSON.int(2),
                    "hash": FixtureJSON.string(afterHash),
                ]),
            ]),
            "interactionDigest": FixtureJSON.object([
                "nodeCountBefore": FixtureJSON.int(0),
                "nodeCountAfter": FixtureJSON.int(1),
                "nodeCountChanged": FixtureJSON.bool(true),
                "elementSetChanged": FixtureJSON.bool(true),
                "screenIdBefore": FixtureJSON.string("screen"),
                "screenIdAfter": FixtureJSON.string("screen"),
                "screenIdChanged": FixtureJSON.bool(false),
                "firstResponderChanged": FixtureJSON.bool(false),
            ]),
            "edits": FixtureJSON.object([
                "added": FixtureJSON.array([
                    FixtureJSON.object([
                        "traits": FixtureJSON.array([FixtureJSON.string("staticText")]),
                        "label": FixtureJSON.string("Pay"),
                        "identifier": FixtureJSON.string("pay"),
                    ]),
                ]),
            ]),
        ])
    }
}
