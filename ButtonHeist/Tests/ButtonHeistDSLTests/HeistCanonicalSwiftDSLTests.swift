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
func canonicalSwiftRendererPreservesHelperDefinitionDependencies() throws {
    enum LibraryScreen {
        static let tapAddButton = HeistDef<Void>("AddButton.tap") {
            Activate(.label("Add to Cart"))
        }

        static let addToCart = HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            Activate(.label(item))
            try tapAddButton()
        }
    }

    let plan = try Heist("purchaseFlow") {
        try LibraryScreen.addToCart("Milk")
    }.plan

    #expect(try plan.canonicalSwiftDSL() == """
    enum LibraryScreen {
        static let addToCart = try! HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            enum AddButton {
                static let tap = try! HeistDef<Void>("AddButton.tap") {
                    Activate(.label("Add to Cart"))
                }
            }

            Activate(.label(item))

            AddButton.tap()
        }
    }

    try Heist("purchaseFlow") {
        LibraryScreen.addToCart("Milk")
    }
    """)
}

@Test
func `Canonical Swift renderer preserves composed expectation with string ref`() throws {
    enum SearchScreen {
        static let search = HeistDef<String>("SearchScreen.search", parameter: "query") { query in
            TypeText(query, into: .label("Search"))
                .expect(.present(.value(query)), timeout: .seconds(1))

            Activate(.label("Search"))
                .expect(.changed(.screen()))
                .expect(.present(.label(query)), timeout: .seconds(5))
        }
    }

    let plan = try Heist("searchFlow") {
        try SearchScreen.search("milk")
    }.plan

    #expect(try plan.canonicalSwiftDSL() == """
    enum SearchScreen {
        static let search = try! HeistDef<String>("SearchScreen.search", parameter: "query") { query in
            TypeText(query, into: .label("Search"))
                .expect(.present(.value(query)), timeout: .seconds(1))

            Activate(.label("Search"))
                .expect(.changed(.screen(where: .present(.label(query)))), timeout: .seconds(5))
        }
    }

    try Heist("searchFlow") {
        SearchScreen.search("milk")
    }
    """)
}

@Test
func canonicalSwiftRendererRejectsRefsOutsideLoopScope() throws {
    let plan = HeistPlan(body: [
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
    let plan = HeistPlan(body: [
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

@Test
func canonicalSwiftRendererSeparatesSemanticMechanicalAndViewportActions() throws {
    let plan = HeistPlan(body: [
        .action(try ActionStep(command: .performCustomAction(CustomActionTarget(
            elementTarget: .predicate(.label("Message")),
            actionName: "Archive"
        )))),
        .action(try ActionStep(command: .rotor(RotorTarget(
            elementTarget: .predicate(.label("Article")),
            selection: .named("Headings"),
            direction: .next
        )))),
        .action(try ActionStep(command: .oneFingerTap(TapTarget(
            selection: .coordinate(ScreenPoint(x: 12, y: 34))
        )))),
        .action(try ActionStep(command: .scroll(ScrollTarget(direction: .down)))),
    ])

    #expect(plan.runtimeAdmissionFailures().isEmpty)
    #expect(try plan.canonicalSwiftDSL() == """
    try Heist {
        CustomAction("Archive", on: .label("Message"))

        Rotor("Headings", on: .label("Article"), direction: .next)

        Mechanical.Tap(x: 12, y: 34)

        Viewport.Scroll(.down)
    }
    """)
}

@Test
func elementUnitPointSwipeIsDurableAndCanonical() throws {
    let command = HeistActionCommand.mechanicalSwipe(SwipeTarget(selection: .unitElement(
        .predicate(.label("Carousel")),
        start: UnitPoint(x: 0.8, y: 0.5),
        end: UnitPoint(x: 0.2, y: 0.5)
    )))
    let plan = HeistPlan(body: [.action(try ActionStep(command: command))])

    #expect(command.durableHeistActionFailure == nil)
    #expect(plan.runtimeAdmissionFailures().isEmpty)
    #expect(try plan.canonicalSwiftDSL() == """
    try Heist {
        Mechanical.Swipe(.label("Carousel"), from: UnitPoint(x: 0.8, y: 0.5), to: UnitPoint(x: 0.2, y: 0.5))
    }
    """)
}

@Test
func nonDurableActionShapeFailsAdmissionAndRenderingWithSameReason() throws {
    let command = HeistActionCommand.rotor(
        selection: .index(0),
        target: .target(.predicate(.label("Article"))),
        direction: .next
    )
    let plan = HeistPlan(body: [.action(try ActionStep(command: command))])
    let reason = try #require(command.durableHeistActionFailure)

    #expect(plan.runtimeAdmissionFailures().contains {
        $0.contract == "durable heist action support"
            && $0.observed == reason
    })

    do {
        _ = try plan.canonicalSwiftDSL()
        Issue.record("Expected non-durable action to fail canonical rendering")
    } catch let error as HeistCanonicalSwiftDSLError {
        #expect(error == .unsupportedAction(reason))
    }
}

private let fullASTJSON = """
{
  "version": 2,
  "body": [
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
            "body": [
              { "type": "warn", "warn": { "message": "home" } }
            ]
          }
        ],
        "else_body": [
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
            "body": [
              { "type": "warn", "warn": { "message": "results" } }
            ]
          }
        ],
        "else_body": [
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
        "body": [
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
        "body": [
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
  "version": 2,
  "body": [
    {
      "type": "for_each_element",
      "for_each_element": {
        "matching": { "label": "Delete" },
        "limit": 20,
        "parameter": "target-name",
        "body": [
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
  "version": 2,
  "body": [
    {
      "type": "for_each_string",
      "for_each_string": {
        "values": ["Milk"],
        "parameter": "target-name",
        "body": [
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
