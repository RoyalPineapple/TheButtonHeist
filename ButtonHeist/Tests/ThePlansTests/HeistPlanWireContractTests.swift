import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test
func `all heist step kinds round trip through canonical JSON bytes`() throws {
    let plan = try representativeAllStepKindsPlan()
    let encoded = try plan.canonicalHeistJSONData()
    let actualJSON = try #require(String(data: encoded, encoding: .utf8))

    #expect(actualJSON == expectedAllStepKindsPlanJSON)

    let decoded = try JSONDecoder().decode(HeistPlan.self, from: encoded)
    #expect(decoded == plan)
    #expect(try decoded.canonicalHeistJSONData() == encoded)
    #expect(decoded.body.map(stepKind) == [
        "action",
        "wait",
        "conditional",
        "for_each_element",
        "for_each_string",
        "repeat_until",
        "warn",
        "fail",
        "heist",
        "invoke",
    ])
}

@Test
func `JSONDecoder decode of heist plan still runs runtime safety validation`() {
    let unresolvedInvocation = Data("""
    {
      "version": 1,
      "body": [
        {
          "type": "invoke",
          "invoke": {
            "path": [ "MissingCapability" ]
          }
        }
      ]
    }
    """.utf8)

    #expect(throws: HeistPlanRuntimeSafetyError.self) {
        _ = try JSONDecoder().decode(HeistPlan.self, from: unresolvedInvocation)
    }
}

@Test
func `JSONDecoder decode of nested collection loops is rejected by runtime safety validation`() throws {
    let nestedCollectionLoop = Data("""
    {
      "version": 1,
      "body": [
        {
          "type": "for_each_string",
          "for_each_string": {
            "values": [ "Milk" ],
            "parameter": "item",
            "body": [
              {
                "type": "for_each_element",
                "for_each_element": {
                  "matching": {
                    "checks": [
                      { "kind": "label", "match": { "mode": "exact", "value": "Row" } }
                    ]
                  },
                  "limit": 1,
                  "parameter": "row",
                  "body": [
                    { "type": "warn", "warn": { "message": "nested" } }
                  ]
                }
              }
            ]
          }
        }
      ]
    }
    """.utf8)

    do {
        _ = try JSONDecoder().decode(HeistPlan.self, from: nestedCollectionLoop)
        Issue.record("Expected nested collection loop JSON to fail runtime safety validation")
    } catch let error as HeistPlanRuntimeSafetyError {
        let failure = try #require(error.failures.first)
        #expect(failure.path == "$.body[0].for_each_string.body[0].for_each_element")
        #expect(failure.contract == "collection loops must not be nested")
        #expect(failure.observed == "for_each_element inside collection loop")
        #expect(failure.correction == "Flatten this heist so ForEach bodies contain only non-collection steps.")
    }
}

@Test
func `predicate case wire boundary decodes only snapshot predicates`() throws {
    let transitionCase = Data("""
    {
      "predicate": {
        "type": "change",
        "scopes": [
          {
            "type": "elements",
            "assertions": [
              {
                "type": "appeared",
                "element": {
                  "checks": [
                    { "kind": "label", "match": { "mode": "exact", "value": "Receipt" } }
                  ]
                }
              }
            ]
          }
        ]
      },
      "body": [
        { "type": "warn", "warn": { "message": "ready" } }
      ]
    }
    """.utf8)

    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(PredicateCase.self, from: transitionCase)
    }

    let snapshotCase = try JSONDecoder().decode(PredicateCase.self, from: Data("""
    {
      "predicate": {
        "type": "exists",
        "element": {
          "checks": [
            { "kind": "label", "match": { "mode": "exact", "value": "Receipt" } }
          ]
        }
      },
      "body": [
        { "type": "warn", "warn": { "message": "ready" } }
      ]
    }
    """.utf8))
    #expect(snapshotCase.predicate == .exists(.label("Receipt")))
}

@Test
func `durable element predicate JSON requires canonical checks`() throws {
    #expect(throws: DecodingError.self) {
        _ = try JSONDecoder().decode(ElementPredicate.self, from: Data("""
        {
          "label": "Receipt"
        }
        """.utf8))
    }

    let predicate = try JSONDecoder().decode(ElementPredicate.self, from: Data("""
    {
      "checks": [
        { "kind": "label", "match": { "mode": "exact", "value": "Receipt" } }
      ]
    }
    """.utf8))
    #expect(predicate == .label("Receipt"))
}

@Test
func `for each parameter names reject Swift reserved identifiers including Any`() {
    #expect(HeistParameterName.isValid("item"))
    #expect(!HeistParameterName.isValid("Any"))
    #expect(!HeistParameterName.isValid("class"))
}

@Test
func `model Codable boundaries reject unknown fields`() {
    expectUnknownField("plan", contains: #"Unknown heist plan field "unexpected""#) {
        _ = try JSONDecoder().decode(HeistPlan.self, from: Data("""
        {
          "version": 1,
          "body": [
            { "type": "warn", "warn": { "message": "hello" } }
          ],
          "unexpected": true
        }
        """.utf8))
    }

    expectUnknownField("parameter", contains: #"Unknown heist parameter field "unexpected""#) {
        _ = try JSONDecoder().decode(HeistParameter.self, from: Data("""
        { "type": "string", "name": "query", "unexpected": true }
        """.utf8))
    }

    expectUnknownField("argument", contains: #"Unknown heist argument field "unexpected""#) {
        _ = try JSONDecoder().decode(HeistArgument.self, from: Data("""
        { "type": "string", "value": "Milk", "unexpected": true }
        """.utf8))
    }

    for testCase in unknownStepPayloadCases() {
        expectUnknownField(testCase.name, contains: testCase.expectedMessage, decode: testCase.decode)
    }
}

@Test
func `element update property checkers reject unknown fields`() {
    expectUnknownField("frame match", contains: #"Unknown frame match field "unexpected""#) {
        _ = try JSONDecoder().decode(ElementFrameMatch.self, from: Data("""
        { "width": 1, "unexpected": true }
        """.utf8))
    }

    expectUnknownField("activation point match", contains: #"Unknown activation point match field "unexpected""#) {
        _ = try JSONDecoder().decode(ElementPointMatch.self, from: Data("""
        { "x": 1, "unexpected": true }
        """.utf8))
    }

    expectUnknownField("nested frame update", contains: #"Unknown frame match field "unexpected""#) {
        _ = try JSONDecoder().decode(ElementDeltaPredicate.self, from: Data("""
        {
          "type": "updated",
          "property": "frame",
          "after": { "x": 1, "unexpected": true }
        }
        """.utf8))
    }
}

private struct UnknownFieldCase {
    var name: String
    var expectedMessage: String
    var decode: () throws -> Void
}

private func unknownStepPayloadCases() -> [UnknownFieldCase] {
    unknownBasicStepPayloadCases()
        + unknownCollectionStepPayloadCases()
        + unknownTerminalStepPayloadCases()
}

private func unknownBasicStepPayloadCases() -> [UnknownFieldCase] {
    [
        UnknownFieldCase(name: "step wrapper", expectedMessage: #"Unknown warn heist step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(HeistStep.self, from: Data("""
            { "type": "warn", "warn": { "message": "hello" }, "unexpected": true }
            """.utf8))
        }),
        UnknownFieldCase(name: "action step", expectedMessage: #"Unknown action step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(ActionStep.self, from: Data("""
            {
              "command": { "type": "resignFirstResponder" },
              "unexpected": true
            }
            """.utf8))
        }),
        UnknownFieldCase(name: "wait step", expectedMessage: #"Unknown wait step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(WaitStep.self, from: Data("""
            {
              "predicate": {
                "type" : "exists",
                "element": {
                  "checks": [
                    { "kind": "label", "match": { "mode": "exact", "value": "Home" } }
                  ]
                }
              },
              "timeout": 0,
              "unexpected": true
            }
            """.utf8))
        }),
        UnknownFieldCase(name: "conditional step", expectedMessage: #"Unknown conditional step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(ConditionalStep.self, from: Data("""
            {
              "cases": [
                {
                  "predicate": {
                    "type" : "exists",
                    "element": {
                      "checks": [
                        { "kind": "label", "match": { "mode": "exact", "value": "Promo" } }
                      ]
                    }
                  },
                  "body": [ { "type": "warn", "warn": { "message": "promo" } } ]
                }
              ],
              "unexpected": true
            }
            """.utf8))
        }),
        UnknownFieldCase(name: "predicate case", expectedMessage: #"Unknown predicate case field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(PredicateCase.self, from: Data("""
            {
              "predicate": {
                "type" : "exists",
                "element": {
                  "checks": [
                    { "kind": "label", "match": { "mode": "exact", "value": "Promo" } }
                  ]
                }
              },
              "body": [ { "type": "warn", "warn": { "message": "promo" } } ],
              "unexpected": true
            }
            """.utf8))
        }),
    ]
}

private func unknownCollectionStepPayloadCases() -> [UnknownFieldCase] {
    [
        UnknownFieldCase(name: "for each element step", expectedMessage: #"Unknown for_each_element step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(ForEachElementStep.self, from: Data("""
            {
              "matching": {
                "checks": [
                  { "kind": "label", "match": { "mode": "exact", "value": "Delete" } }
                ]
              },
              "limit": 1,
              "parameter": "row",
              "body": [ { "type": "warn", "warn": { "message": "row" } } ],
              "unexpected": true
            }
            """.utf8))
        }),
        UnknownFieldCase(name: "for each string step", expectedMessage: #"Unknown for_each_string step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(ForEachStringStep.self, from: Data("""
            {
              "values": [ "Milk" ],
              "parameter": "item",
              "body": [ { "type": "warn", "warn": { "message": "item" } } ],
              "unexpected": true
            }
            """.utf8))
        }),
        UnknownFieldCase(name: "repeat until step", expectedMessage: #"Unknown repeat_until step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(RepeatUntilStep.self, from: Data("""
            {
              "predicate": {
                "type" : "exists",
                "element": {
                  "checks": [
                    { "kind": "label", "match": { "mode": "exact", "value": "Ready" } }
                  ]
                }
              },
              "timeout": 1,
              "body": [ { "type": "warn", "warn": { "message": "retry" } } ],
              "unexpected": true
            }
            """.utf8))
        }),
    ]
}

private func unknownTerminalStepPayloadCases() -> [UnknownFieldCase] {
    [
        UnknownFieldCase(name: "warn step", expectedMessage: #"Unknown warn step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(WarnStep.self, from: Data("""
            { "message": "hello", "unexpected": true }
            """.utf8))
        }),
        UnknownFieldCase(name: "fail step", expectedMessage: #"Unknown fail step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(FailStep.self, from: Data("""
            { "message": "stop", "unexpected": true }
            """.utf8))
        }),
        UnknownFieldCase(name: "invoke step", expectedMessage: #"Unknown heist invocation step field "unexpected""#, decode: {
            _ = try JSONDecoder().decode(HeistInvocationStep.self, from: Data("""
            { "path": [ "Search" ], "unexpected": true }
            """.utf8))
        }),
    ]
}

private func representativeAllStepKindsPlan() throws -> HeistPlan {
    let searchDefinition = try HeistPlan(
        name: "Search",
        parameter: .string(name: "query"),
        body: [
            .action(try ActionStep(command: .typeText(
                text: .ref("query"),
                target: .predicate(.label("Search"))
            ))),
        ]
    )

    return try HeistPlan(
        name: "wireAllSteps",
        definitions: [searchDefinition],
        body: [
            .action(try ActionStep(
                command: .activate(.predicate(.label("Pay"))),
                expectationPolicy: .expect(ActionExpectation(predicate: .change(.screen()), timeout: 0)))),
            .wait(WaitStep(predicate: .exists(.label("Home")), timeout: 1)),
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(predicate: .exists(.label("Promo")), body: [
                        .warn(WarnStep(message: "promo visible")),
                    ]),
                ],
                elseBody: [
                    .fail(FailStep(message: "promo missing")),
                ]
            )),
            .forEachElement(try ForEachElementStep(
                matching: .element(.label("Delete"), .traits([.button])),
                limit: 2,
                parameter: "row",
                body: [
                    .action(try ActionStep(
                        command: .activate(.ref("row")),
                        expectationPolicy: .expect(ActionExpectation(predicate: .missing(.ref("row")), timeout: 2)))),
                ]
            )),
            .forEachString(try ForEachStringStep(
                values: ["Milk", "Eggs"],
                parameter: "item",
                body: [
                    .action(try ActionStep(command: .typeText(
                        text: .ref("item"),
                        target: .predicate(.label("Search"))
                    ))),
                ]
            )),
            .repeatUntil(try RepeatUntilStep(
                predicate: .exists(.label("Ready")),
                timeout: 2,
                body: [
                    .warn(WarnStep(message: "retry")),
                ],
                elseBody: [
                    .fail(FailStep(message: "not ready")),
                ]
            )),
            .warn(WarnStep(message: "checkpoint")),
            .fail(FailStep(message: "stop here")),
            .heist(try HeistPlan(body: [
                .warn(WarnStep(message: "inline group")),
            ])),
            .invoke(HeistInvocationStep(
                path: ["Search"],
                argument: .string(.literal("Milk"))
            )),
        ]
    )
}

private func stepKind(_ step: HeistStep) -> String {
    switch step {
    case .action:
        return "action"
    case .wait:
        return "wait"
    case .conditional:
        return "conditional"
    case .forEachElement:
        return "for_each_element"
    case .forEachString:
        return "for_each_string"
    case .repeatUntil:
        return "repeat_until"
    case .warn:
        return "warn"
    case .fail:
        return "fail"
    case .heist:
        return "heist"
    case .invoke:
        return "invoke"
    }
}

private func expectUnknownField(
    _ name: String,
    contains expectedMessage: String,
    decode: () throws -> Void
) {
    do {
        try decode()
        Issue.record("Expected \(name) to reject an unknown field")
    } catch DecodingError.dataCorrupted(let context) {
        #expect(
            context.debugDescription.contains(expectedMessage),
            "\(name) error \(context.debugDescription) did not contain \(expectedMessage)"
        )
    } catch {
        Issue.record("Expected \(name) to throw DecodingError.dataCorrupted, got \(error)")
    }
}

private let expectedAllStepKindsPlanJSON = """
{
  "body" : [
    {
      "action" : {
        "command" : {
          "payload" : {
            "target" : {
              "checks" : [
                {
                  "kind" : "label",
                  "match" : {
                    "mode" : "exact",
                    "value" : "Pay"
                  }
                }
              ]
            }
          },
          "type" : "activate"
        },
        "expectation" : {
          "predicate" : {
            "scopes" : [
              {
                "type" : "screen"
              }
            ],
            "type" : "change"
          },
          "timeout" : 0
        }
      },
      "type" : "action"
    },
    {
      "type" : "wait",
      "wait" : {
        "predicate" : {
          "element" : {
            "checks" : [
              {
                "kind" : "label",
                "match" : {
                  "mode" : "exact",
                  "value" : "Home"
                }
              }
            ]
          },
          "type" : "exists"
        },
        "timeout" : 1
      }
    },
    {
      "conditional" : {
        "cases" : [
          {
            "body" : [
              {
                "type" : "warn",
                "warn" : {
                  "message" : "promo visible"
                }
              }
            ],
            "predicate" : {
              "element" : {
                "checks" : [
                  {
                    "kind" : "label",
                    "match" : {
                      "mode" : "exact",
                      "value" : "Promo"
                    }
                  }
                ]
              },
              "type" : "exists"
            }
          }
        ],
        "else_body" : [
          {
            "fail" : {
              "message" : "promo missing"
            },
            "type" : "fail"
          }
        ]
      },
      "type" : "conditional"
    },
    {
      "for_each_element" : {
        "body" : [
          {
            "action" : {
              "command" : {
                "payload" : {
                  "target_ref" : "row"
                },
                "type" : "activate"
              },
              "expectation" : {
                "predicate" : {
                  "target_ref" : "row",
                  "type" : "missing"
                },
                "timeout" : 2
              }
            },
            "type" : "action"
          }
        ],
        "limit" : 2,
        "matching" : {
          "checks" : [
            {
              "kind" : "label",
              "match" : {
                "mode" : "exact",
                "value" : "Delete"
              }
            },
            {
              "kind" : "traits",
              "values" : [
                "button"
              ]
            }
          ]
        },
        "parameter" : "row"
      },
      "type" : "for_each_element"
    },
    {
      "for_each_string" : {
        "body" : [
          {
            "action" : {
              "command" : {
                "payload" : {
                  "target" : {
                    "checks" : [
                      {
                        "kind" : "label",
                        "match" : {
                          "mode" : "exact",
                          "value" : "Search"
                        }
                      }
                    ]
                  },
                  "text_ref" : "item"
                },
                "type" : "typeText"
              }
            },
            "type" : "action"
          }
        ],
        "parameter" : "item",
        "values" : [
          "Milk",
          "Eggs"
        ]
      },
      "type" : "for_each_string"
    },
    {
      "repeat_until" : {
        "body" : [
          {
            "type" : "warn",
            "warn" : {
              "message" : "retry"
            }
          }
        ],
        "else_body" : [
          {
            "fail" : {
              "message" : "not ready"
            },
            "type" : "fail"
          }
        ],
        "predicate" : {
          "element" : {
            "checks" : [
              {
                "kind" : "label",
                "match" : {
                  "mode" : "exact",
                  "value" : "Ready"
                }
              }
            ]
          },
          "type" : "exists"
        },
        "timeout" : 2
      },
      "type" : "repeat_until"
    },
    {
      "type" : "warn",
      "warn" : {
        "message" : "checkpoint"
      }
    },
    {
      "fail" : {
        "message" : "stop here"
      },
      "type" : "fail"
    },
    {
      "heist" : {
        "body" : [
          {
            "type" : "warn",
            "warn" : {
              "message" : "inline group"
            }
          }
        ],
        "version" : 1
      },
      "type" : "heist"
    },
    {
      "invoke" : {
        "argument" : {
          "type" : "string",
          "value" : "Milk"
        },
        "path" : [
          "Search"
        ]
      },
      "type" : "invoke"
    }
  ],
  "definitions" : [
    {
      "body" : [
        {
          "action" : {
            "command" : {
              "payload" : {
                "target" : {
                  "checks" : [
                    {
                      "kind" : "label",
                      "match" : {
                        "mode" : "exact",
                        "value" : "Search"
                      }
                    }
                  ]
                },
                "text_ref" : "query"
              },
              "type" : "typeText"
            }
          },
          "type" : "action"
        }
      ],
      "name" : "Search",
      "parameter" : {
        "name" : "query",
        "type" : "string"
      },
      "version" : 1
    }
  ],
  "name" : "wireAllSteps",
  "version" : 1
}
"""
