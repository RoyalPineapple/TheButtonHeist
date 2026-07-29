import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test
func `plan model rejects unknown top level fields`() {
    expectUnknownField("plan", contains: #"Unknown heist plan field "unexpected""#) {
        _ = try JSONDecoder().decode(HeistPlan.self, from: Data("""
        {
          "version": 3,
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
          "version": 3,
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

/// Geometry is observed but not assertable, so a plan that asserts on it is
/// refused rather than accepted-and-ignored. A silently ignored `frame` would
/// leave the plan reading as though it constrained something.
@Test
func `an updated assertion naming geometry does not decode`() {
    for property in ["frame", "activationPoint"] {
        let json = Data("""
        {
          "type": "updated",
          "target": {
            "checks": [
              { "kind": "label", "match": { "mode": "exact", "value": "Panel" } }
            ]
          },
          "property": "\(property)",
          "after": { "x": 1 }
        }
        """.utf8)
        #expect(throws: DecodingError.self) {
            _ = try JSONDecoder().decode(ElementAssertion.self, from: json)
        }
    }
}

@Test
func `the assertable vocabulary excludes identity matchers and geometry`() {
    #expect(AssertableProperty.allCases == [
        .value,
        .traits,
        .hint,
        .actions,
        .customContent,
        .rotors,
    ])
    // Every assertable property is observable, and the two vocabularies agree on
    // spelling, which is what keeps the wire format unchanged.
    for assertable in AssertableProperty.allCases {
        #expect(assertable.observed.rawValue == assertable.rawValue)
        #expect(assertable.observed.assertable == assertable)
    }
    // The four ElementProperty cases with no assertable twin, and why.
    #expect(ElementProperty.label.assertable == nil)
    #expect(ElementProperty.identifier.assertable == nil)
    #expect(ElementProperty.frame.assertable == nil)
    #expect(ElementProperty.activationPoint.assertable == nil)
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
