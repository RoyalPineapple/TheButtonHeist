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
func `checked in heist fixtures use canonical JSON contracts`() throws {
    let fixtureURLs = try heistArtifactFixtureURLs()
    if fixtureURLs.isEmpty {
        Issue.record("Expected at least one checked-in .heist fixture")
    }

    for fixtureURL in fixtureURLs {
        let artifact = try HeistArtifactCodec.read(from: fixtureURL)
        try expectCanonicalJSON(
            at: fixtureURL.appendingPathComponent(HeistArtifactCodec.manifestFileName, isDirectory: false),
            expectedData: HeistArtifactCodec.canonicalManifestJSONData(artifact.manifest)
        )
        try expectCanonicalJSON(
            at: fixtureURL.appendingPathComponent(HeistArtifactCodec.planFileName, isDirectory: false),
            expectedData: artifact.plan.canonicalHeistJSONData()
        )
    }
}

@Test
func `JSONDecoder decode of heist plan still runs runtime safety validation`() {
    let unresolvedInvocation = Data("""
    {
      "version": 2,
      "body": [
        {
          "type": "invoke",
          "invoke": {
            "path": "MissingCapability"
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
func `invalid external plan remains a candidate until runtime safety admission`() throws {
    let data = Data(#"{"version":2,"body":[{"type":"invoke","invoke":{"path":"MissingCapability"}}]}"#.utf8)
    let candidate = try JSONDecoder().decode(HeistPlanAdmissionCandidate.self, from: data)

    #expect(throws: HeistPlanRuntimeSafetyError.self) {
        _ = try candidate.validatedForRuntimeSafety()
    }
}

@Test
func `JSONDecoder decode of nested collection loops is rejected by runtime safety validation`() throws {
    let nestedCollectionLoop = Data("""
    {
      "version": 2,
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
        #expect(failure.path.description == "$.body[0].for_each_string.body[0].for_each_element")
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
        "type": "changed",
        "scope": "elements",
        "assertions": [
              {
                "type": "appeared",
                "target": {
                  "checks": [
                    { "kind": "label", "match": { "mode": "exact", "value": "Receipt" } }
                  ]
                }
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
        "target": {
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
        _ = try JSONDecoder().decode(ElementPredicateTemplate.self, from: Data("""
        {
          "label": "Receipt"
        }
        """.utf8))
    }

    let predicate = try JSONDecoder().decode(ElementPredicateTemplate.self, from: Data("""
    {
      "checks": [
        { "kind": "label", "match": { "mode": "exact", "value": "Receipt" } }
      ]
    }
    """.utf8))
    #expect(predicate == .label("Receipt"))
}

private func heistArtifactFixtureURLs() throws -> [URL] {
    let fixturesURL = repositoryRootURL()
        .appendingPathComponent("tests", isDirectory: true)
        .appendingPathComponent("fixtures", isDirectory: true)
    let enumerator = FileManager.default.enumerator(
        at: fixturesURL,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    return try (enumerator?.compactMap { entry -> URL? in
        guard let url = entry as? URL,
              url.pathExtension == "heist"
        else {
            return nil
        }
        let values = try url.resourceValues(forKeys: [.isDirectoryKey])
        return values.isDirectory == true ? url : nil
    } ?? [])
    .sorted { $0.path < $1.path }
}

private func repositoryRootURL() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private func expectCanonicalJSON(at url: URL, expectedData: Data) throws {
    let actualData = try Data(contentsOf: url)
    let actualJSON = try canonicalJSONObjectData(from: actualData)
    let expectedJSON = try canonicalJSONObjectData(from: expectedData)
    #expect(actualJSON == expectedJSON, "\(url.path) must use Button Heist's canonical JSON encoding")
}

private func canonicalJSONObjectData(from data: Data) throws -> Data {
    let object = try JSONSerialization.jsonObject(with: data, options: [])
    return try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
}

@Test
func `model Codable boundaries reject unknown fields`() {
    expectUnknownField("plan", contains: #"Unknown heist plan field "unexpected""#) {
        _ = try JSONDecoder().decode(HeistPlan.self, from: Data("""
        {
          "version": 2,
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
func `target parameter kind uses accessibility target spelling`() throws {
    let parameter = HeistParameter.accessibilityTarget(name: "row")
    let argument = HeistArgument.accessibilityTarget(.ref("row"))

    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    #expect(String(bytes: try encoder.encode(parameter), encoding: .utf8) ==
        #"{"name":"row","type":"accessibility_target"}"#)
    #expect(String(bytes: try encoder.encode(argument), encoding: .utf8) ==
        #"{"target":{"ref":"row"},"type":"accessibility_target"}"#)

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
        _ = try JSONDecoder().decode(ChangeDeclaration.ElementAssertion.self, from: Data("""
        {
          "type": "updated",
          "target": {
            "checks": [
              { "kind": "label", "match": { "mode": "exact", "value": "Panel" } }
            ]
          },
          "property": "frame",
          "after": { "x": 1, "unexpected": true }
        }
        """.utf8))
    }
}

@Test
func `element update property registry excludes identity matchers`() {
    #expect(ElementProperty.updateProperties == [
        .value,
        .traits,
        .hint,
        .actions,
        .frame,
        .activationPoint,
        .customContent,
        .rotors,
    ])
    #expect(ElementProperty.allCases.filter(\.isUpdateProperty) == ElementProperty.updateProperties)
    #expect(!ElementProperty.label.isUpdateProperty)
    #expect(!ElementProperty.identifier.isUpdateProperty)
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
                "target": {
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
                    "target": {
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
                "target": {
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
                "target": {
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
            { "path": "Search", "unexpected": true }
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
                reference: "query",
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
                expectationPolicy: .expect(ActionExpectation(predicate: .changed(.screen()), timeout: .milliseconds(1))))),
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
                        reference: "item",
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
                path: "Search",
                argument: .string("Milk")
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
            "assertions" : [

            ],
            "scope" : "screen",
            "type" : "changed"
          },
          "timeout" : 0.001
        }
      },
      "type" : "action"
    },
    {
      "type" : "wait",
      "wait" : {
        "predicate" : {
          "target" : {
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
              "target" : {
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
                  "target" : {
                    "ref" : "row"
                  }
                },
                "type" : "activate"
              },
              "expectation" : {
                "predicate" : {
                  "target" : {
                    "ref" : "row"
                  },
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
                  "mode" : "append",
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
          "target" : {
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
        "version" : 2
      },
      "type" : "heist"
    },
    {
      "invoke" : {
        "argument" : {
          "type" : "string",
          "value" : "Milk"
        },
        "path" : "Search"
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
                "mode" : "append",
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
      "version" : 2
    }
  ],
  "name" : "wireAllSteps",
  "version" : 2
}
"""
