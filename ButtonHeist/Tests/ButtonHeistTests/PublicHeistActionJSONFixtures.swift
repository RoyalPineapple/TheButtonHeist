enum PublicHeistActionJSONFixture {
    static let warningResponse = #"""
    {
      "status": "ok",
      "report": {
        "summary": {
          "executedTopLevelStepCount": 1,
          "executedNodeCount": 1,
          "outputNodeCount": 1,
          "durationMs": 1
        },
        "metrics": {
          "measurements": [
            {
              "name": "heistDurationMs",
              "valueMs": 1
            }
          ],
          "ceilings": []
        },
        "nodes": [
          {
            "path": "$.body[0]",
            "kind": "warn",
            "status": "passed",
            "message": "heads up",
            "durationMs": 1,
            "evidence": {
              "warning": {
                "path": "$.body[0]",
                "message": "heads up"
              }
            },
            "children": []
          }
        ]
      }
    }
    """#

    static let failure = #"""
    {
      "category": "explicitFailure",
      "contract": "explicit heist failure",
      "observed": "stop",
      "code": "request.action_failed",
      "kind": "request",
      "phase": "request",
      "retryable": false
    }
    """#

    static let expectation = #"""
    {
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
    }
    """#

    static let actionWithExpectation = #"""
    {
      "action": {
        "commandName": "dismiss",
        "result": {
          "status": "ok",
          "method": "dismiss",
          "message": "dismissed"
        },
        "expectationResult": {
          "status": "ok",
          "method": "wait",
          "message": "matched"
        },
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
        }
      }
    }
    """#

    static let wait = #"""
    {
      "wait": {
        "outcome": "matched",
        "result": {
          "status": "ok",
          "method": "wait",
          "message": "waited"
        },
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
        "baselineSummary": "Loading",
        "finalSummary": "Done visible"
      }
    }
    """#

    static let invocation = #"""
    {
      "invocation": {
        "capability": "Cart.checkout",
        "argument": "RunHeist(\"Cart.checkout\", \"Milk\")",
        "expectationResult": {
          "status": "ok",
          "method": "wait",
          "message": "waited"
        },
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
        "expectationEvidence": {
          "outcome": "matched",
          "result": {
            "status": "ok",
            "method": "wait",
            "message": "waited"
          },
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
          "baselineSummary": "Loading",
          "finalSummary": "Done visible"
        }
      }
    }
    """#

    static let omissions = #"""
    {
      "accessibilityTrace": {
        "reason": "raw accessibility trace omitted from public heist report",
        "projectedAs": "delta",
        "omittedCount": 2
      },
      "subjectEvidence": {
        "reason": "raw subject evidence omitted from public heist report"
      }
    }
    """#

    static func netDelta(beforeHash: String, afterHash: String) -> String {
        #"""
        {
          "kind": "elementsChanged",
          "elementCount": 1,
          "captureEdge": {
            "before": {
              "sequence": 1,
              "hash": "\#(beforeHash)"
            },
            "after": {
              "sequence": 2,
              "hash": "\#(afterHash)"
            }
          },
          "interactionDigest": {
            "nodeCountBefore": 0,
            "nodeCountAfter": 1,
            "nodeCountChanged": true,
            "elementSetChanged": true,
            "screenIdBefore": "screen",
            "screenIdAfter": "screen",
            "screenIdChanged": false,
            "firstResponderChanged": false
          },
          "edits": {
            "added": [
              {
                "traits": ["staticText"],
                "label": "Pay",
                "identifier": "pay"
              }
            ]
          }
        }
        """#
    }
}
