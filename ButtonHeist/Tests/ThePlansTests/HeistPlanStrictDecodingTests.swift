import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test
func `plan model rejects unknown top level fields`() {
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
}

@Test
func `repeat until JSON rejects else body`() {
    expectUnknownField("repeat_until", contains: #"Unknown repeat_until step field "else_body""#) {
        _ = try JSONDecoder().decode(HeistPlan.self, from: Data("""
        {
          "version": 2,
          "body": [
            {
              "type": "repeat_until",
              "repeat_until": {
                "predicate": { "type": "exists", "target": { "checks": [{ "kind": "label", "match": { "mode": "exact", "value": "Done" } }] } },
                "timeout": 1,
                "body": [
                  { "type": "warn", "warn": { "message": "retry" } }
                ],
                "else_body": [
                  { "type": "fail", "fail": { "message": "timed out" } }
                ]
              }
            }
          ]
        }
        """.utf8))
    }
}

@Test
func `element predicate reports its canonical diagnostic name`() {
    expectUnknownField("element predicate", contains: #"Unknown element predicate field "unexpected""#) {
        _ = try JSONDecoder().decode(ElementPredicate.self, from: Data("""
        { "checks": [{ "kind": "label", "match": { "mode": "exact", "value": "Receipt" } }], "unexpected": true }
        """.utf8))
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
