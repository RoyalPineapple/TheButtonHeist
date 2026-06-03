import ButtonHeistDSL
import Foundation
import Testing
import TheScore

@Test
func decodedJSONRendersCanonicalSwiftDSLForFullAST() throws {
    let plan = try JSONDecoder().decode(HeistPlan.self, from: Data(fullASTJSON.utf8))

    let rendered = try plan.canonicalSwiftDSL()

    #expect(rendered == fullCanonicalSwiftDSL)
}

@Test
func swiftDSLAndJSONProjectToEquivalentCanonicalSwift() throws {
    let swiftPlan = try Heist {
        Activate(.label("Sign In"))
            .expect(.present(.label("Home")), timeout: .seconds(5))

        WaitFor(.absent(.label("Loading")), timeout: .seconds(1))

        If {
            Case(.present(.label("Home"))) {
                Warn("home")
            }

            Else {
                Fail("unknown")
            }
        }

        WaitFor(timeout: .seconds(8)) {
            Case(.present(.label("Results"))) {
                Warn("results")
            }

            Else {
                Fail("timeout")
            }
        }

        try ForEach(.matching(.label("Delete")), limit: 20) { target in
            Activate(target)
                .expect(.absent(target), timeout: .seconds(2))
        }

        try ForEach(["Milk", "Eggs"]) { item in
            TypeText(item, into: .label("Add item"))
                .expect(.present(.label(item)), timeout: .seconds(2))
        }

        Warn("done")

        Fail("stop")
    }.plan
    let jsonData = try JSONEncoder().encode(swiftPlan)
    let jsonPlan = try JSONDecoder().decode(HeistPlan.self, from: jsonData)

    #expect(jsonPlan == swiftPlan)
    #expect(try jsonPlan.canonicalSwiftDSL() == swiftPlan.canonicalSwiftDSL())
}

@Test
func canonicalSwiftRendererRejectsRefsOutsideLoopScope() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .activate(.ref("target")))),
    ])

    do {
        _ = try plan.canonicalSwiftDSL()
        Issue.record("Expected unresolved ref render failure")
    } catch let error as HeistCanonicalSwiftDSLError {
        #expect(error == .unresolvedTargetReference("target"))
    }
}

@Test
func decodedRuntimeLoopsRejectNonCanonicalSwiftParameters() throws {
    for json in [invalidElementLoopParameterJSON, invalidStringLoopParameterJSON] {
        let plan = try JSONDecoder().decode(HeistPlan.self, from: Data(json.utf8))
        let failures = plan.runtimeAdmissionFailures()
        #expect(failures.contains { $0.contract.contains("Swift-style identifier") })

        do {
            _ = try plan.canonicalSwiftDSL()
            Issue.record("Expected invalid loop parameter render failure")
        } catch let error as HeistCanonicalSwiftDSLError {
            #expect(error == .invalidParameter("target-name"))
        }
    }
}

@Test
func canonicalSwiftRendererRendersAmbientActions() throws {
    let plan = HeistPlan(steps: [
        .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "milk")))),
        .action(try ActionStep(command: .editAction(EditActionTarget(action: .paste)))),
        .action(try ActionStep(command: .dismissKeyboard)),
    ])

    #expect(plan.runtimeAdmissionFailures().isEmpty)
    #expect(try plan.canonicalSwiftDSL() == """
    try Heist {
        SetPasteboard("milk")

        Edit(.paste)

        DismissKeyboard()
    }
    """)
}

private let fullASTJSON = """
{
  "version": 1,
  "steps": [
    {
      "type": "action",
      "action": {
        "command": {
          "type": "activate",
          "payload": { "label": "Sign In" }
        },
        "expectation": {
          "predicate": { "type": "present", "element": { "label": "Home" } },
          "timeout": 5
        }
      }
    },
    {
      "type": "wait",
      "wait": {
        "predicate": { "type": "absent", "element": { "label": "Loading" } },
        "timeout": 1
      }
    },
    {
      "type": "conditional",
      "conditional": {
        "cases": [
          {
            "predicate": { "type": "present", "element": { "label": "Home" } },
            "steps": [
              { "type": "warn", "warn": { "message": "home" } }
            ]
          }
        ],
        "else_steps": [
          { "type": "fail", "fail": { "message": "unknown" } }
        ]
      }
    },
    {
      "type": "wait_for_cases",
      "wait_for_cases": {
        "timeout": 8,
        "cases": [
          {
            "predicate": { "type": "present", "element": { "label": "Results" } },
            "steps": [
              { "type": "warn", "warn": { "message": "results" } }
            ]
          }
        ],
        "else_steps": [
          { "type": "fail", "fail": { "message": "timeout" } }
        ]
      }
    },
    {
      "type": "for_each_element",
      "for_each_element": {
        "matching": { "label": "Delete" },
        "limit": 20,
        "parameter": "target",
        "steps": [
          {
            "type": "action",
            "action": {
              "command": {
                "type": "activate",
                "payload": { "target_ref": "target" }
              },
              "expectation": {
                "predicate": { "type": "absent", "target_ref": "target" },
                "timeout": 2
              }
            }
          }
        ]
      }
    },
    {
      "type": "for_each_string",
      "for_each_string": {
        "values": ["Milk", "Eggs"],
        "parameter": "item",
        "steps": [
          {
            "type": "action",
            "action": {
              "command": {
                "type": "typeText",
                "payload": {
                  "text_ref": "item",
                  "target": { "label": "Add item" }
                }
              },
              "expectation": {
                "predicate": { "type": "present", "element": { "label_ref": "item" } },
                "timeout": 2
              }
            }
          }
        ]
      }
    },
    { "type": "warn", "warn": { "message": "done" } },
    { "type": "fail", "fail": { "message": "stop" } }
  ]
}
"""

private let invalidElementLoopParameterJSON = """
{
  "version": 1,
  "steps": [
    {
      "type": "for_each_element",
      "for_each_element": {
        "matching": { "label": "Delete" },
        "limit": 20,
        "parameter": "target-name",
        "steps": [
          {
            "type": "action",
            "action": {
              "command": {
                "type": "activate",
                "payload": { "target_ref": "target-name" }
              }
            }
          }
        ]
      }
    }
  ]
}
"""

private let invalidStringLoopParameterJSON = """
{
  "version": 1,
  "steps": [
    {
      "type": "for_each_string",
      "for_each_string": {
        "values": ["Milk"],
        "parameter": "target-name",
        "steps": [
          {
            "type": "action",
            "action": {
              "command": {
                "type": "typeText",
                "payload": {
                  "text_ref": "target-name",
                  "target": { "label": "Add item" }
                }
              }
            }
          }
        ]
      }
    }
  ]
}
"""

private let fullCanonicalSwiftDSL = """
try Heist {
    Activate(.label("Sign In"))
        .expect(.present(.label("Home")), timeout: .seconds(5))

    WaitFor(.absent(.label("Loading")), timeout: .seconds(1))

    If {
        Case(.present(.label("Home"))) {
            Warn("home")
        }

        Else {
            Fail("unknown")
        }
    }

    WaitFor(timeout: .seconds(8)) {
        Case(.present(.label("Results"))) {
            Warn("results")
        }

        Else {
            Fail("timeout")
        }
    }

    try ForEach(.matching(.label("Delete")), limit: 20) { target in
        Activate(target)
            .expect(.absent(target), timeout: .seconds(2))
    }

    try ForEach(["Milk", "Eggs"]) { item in
        TypeText(item, into: .label("Add item"))
            .expect(.present(.label(item)), timeout: .seconds(2))
    }

    Warn("done")

    Fail("stop")
}
"""
