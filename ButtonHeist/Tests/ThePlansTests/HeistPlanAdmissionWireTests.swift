import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

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

    #expect(throws: HeistPlanBuildError.self) {
        _ = try JSONDecoder().decode(HeistPlan.self, from: unresolvedInvocation)
    }
}

@Test
func `external plan version is rejected during root admission`() throws {
    let data = Data(#"{"version":3,"body":[{"type":"warn","warn":{"message":"future"}}]}"#.utf8)

    #expect(throws: HeistPlanVersionAdmissionError.self) {
        _ = try JSONDecoder().decode(HeistPlan.self, from: data)
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
    } catch let error as HeistPlanBuildError {
        let diagnostic = try #require(error.diagnostics.first)
        #expect(diagnostic.path == "$.body[0].for_each_string.body[0].for_each_element")
        #expect(diagnostic.message == "collection loops must not be nested; observed for_each_element inside collection loop")
        #expect(diagnostic.hint == "Flatten this heist so ForEach bodies contain only non-collection steps.")
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
