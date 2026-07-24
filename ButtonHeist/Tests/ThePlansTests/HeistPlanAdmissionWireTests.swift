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
func `external plan version remains candidate data until semantic admission`() throws {
    let data = Data(#"{"version":3,"body":[{"type":"warn","warn":{"message":"future"}}]}"#.utf8)
    let sourceURL = URL(fileURLWithPath: "/tmp/future-plan.json")

    let candidate = try HeistArtifactCodec.decodeAdmissionCandidateJSON(data, at: sourceURL)

    #expect(candidate.version == 3)
    #expect(throws: HeistPlanVersionAdmissionError.self) {
        _ = try candidate.validatedSemantics()
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
