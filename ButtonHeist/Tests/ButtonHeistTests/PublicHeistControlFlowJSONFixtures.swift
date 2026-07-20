enum PublicHeistControlFlowJSONFixture {
    static let caseSelection = #"""
    {
      "caseSelection": {
        "outcome": {
          "kind": "matched_case",
          "index": 0
        },
        "elapsedMs": 4,
        "timeout": 0.25,
        "lastObservedSummary": "Ready visible",
        "caseCount": 2,
        "cases": [
          {
            "predicate": {
              "type": "exists",
              "target": {
                "checks": [
                  {
                    "kind": "label",
                    "match": { "mode": "exact", "value": "Ready" }
                  }
                ]
              }
            },
            "met": true,
            "actual": "Ready visible"
          }
        ],
        "omittedCaseCount": 1
      }
    }
    """#

    static let forEachString = #"""
    {
      "forEachString": {
        "parameter": "item",
        "count": 2,
        "iterationCount": 1,
        "iterationOrdinal": 0,
        "value": "Milk"
      }
    }
    """#

    static let forEachElement = #"""
    {
      "forEachElement": {
        "parameter": "row",
        "matching": {
          "checks": [
            {
              "kind": "label",
              "match": { "mode": "exact", "value": "Row" }
            }
          ]
        },
        "limit": 3,
        "matchedCount": 2,
        "iterationCount": 1,
        "iterationOrdinal": 0,
        "targetOrdinal": 1,
        "targetSummary": "Row 2"
      }
    }
    """#

    static let repeatUntil = #"""
    {
      "repeatUntil": {
        "outcome": "matched",
        "predicate": {
          "type": "exists",
          "target": {
            "checks": [
              {
                "kind": "label",
                "match": { "mode": "exact", "value": "Done" }
              }
            ]
          }
        },
        "timeout": 0.5,
        "iterationCount": 2,
        "expectation": {
          "met": true,
          "actual": "Done visible",
          "expected": {
            "type": "exists",
            "target": {
              "checks": [
                {
                  "kind": "label",
                  "match": { "mode": "exact", "value": "Done" }
                }
              ]
            }
          }
        },
        "result": {
          "status": "ok",
          "method": "wait",
          "message": "repeat matched"
        },
        "lastObservedSummary": "Done visible"
      }
    }
    """#
}
