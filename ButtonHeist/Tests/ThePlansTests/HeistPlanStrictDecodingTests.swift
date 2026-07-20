import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

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
              "command": { "type": "dismissKeyboard" },
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
