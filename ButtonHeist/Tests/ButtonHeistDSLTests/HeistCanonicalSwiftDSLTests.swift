import ButtonHeistDSL
import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans
import TheScore

@Test
func decodedJSONRendersCanonicalSwiftDSLForFullAST() throws {
    let plan = try JSONDecoder().decode(HeistPlan.self, from: Data(fullASTJSON.utf8))

    let rendered = try plan.canonicalSwiftDSL()

    #expect(rendered == fullCanonicalSwiftDSL)
}

@Test
func swiftDSLAndJSONProjectToEquivalentCanonicalSwift() throws {
    let swiftPlan = try HeistPlan {
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

        WaitFor(.present(.label("Results")), timeout: .seconds(8))
            .else {
                Fail("timeout")
            }

        Warn("results")

        ForEach(.matching(.label("Delete")), limit: 20) { target in
            Activate(target)
                .expect(.absent(target), timeout: .seconds(2))
        }

        ForEach(["Milk", "Eggs"]) { item in
            TypeText(item, into: .label("Add item"))
                .expect(.present(.label(item)), timeout: .seconds(2))
        }

        Warn("done")

        Fail("stop")
    }
    let jsonData = try JSONEncoder().encode(swiftPlan)
    let jsonPlan = try JSONDecoder().decode(HeistPlan.self, from: jsonData)

    #expect(jsonPlan == swiftPlan)
    #expect(try jsonPlan.canonicalSwiftDSL() == swiftPlan.canonicalSwiftDSL())
}

@Test
func rootElementTargetPlanRendersCanonicalSwiftAndCompilesBack() async throws {
    let plan = try HeistPlan("RecordedTarget", targetParameter: "target") { target in
        Activate(target)
            .expect(.absent(target), timeout: .seconds(2))

        WaitFor(.present(target), timeout: .seconds(1))

        If {
            Case(.present(target)) {
                CustomAction("Archive", on: target)
                    .expect(.changed(.screen(where: .present(target))), timeout: .seconds(3))
            }

            Else {
                Fail("target missing")
            }
        }

        WaitFor(.absent(target), timeout: .seconds(4))

        Warn("target removed")
    }

    let rendered = try plan.canonicalSwiftDSL()

    #expect(rendered == """
    HeistPlan("RecordedTarget", targetParameter: "target") { target in
        Activate(target)
            .expect(.absent(target), timeout: .seconds(2))

        WaitFor(.present(target), timeout: .seconds(1))

        If(.present(target)) {
            CustomAction("Archive", on: target)
                .expect(.changed(.screen(where: .present(target))), timeout: .seconds(3))
        }
        .else {
            Fail("target missing")
        }

        WaitFor(.absent(target), timeout: .seconds(4))

        Warn("target removed")
    }
    """)

    #if SWIFT_PACKAGE && (os(macOS) || os(Linux))
    let source = """
    import ThePlans

    let heist = try \(rendered)
    """
    let compiled = try await compileCanonicalHeist(source)
    #expect(try compiled.canonicalSwiftDSL() == rendered)
    #endif
}

@Test
func rootStringPlanRendersDefinitionsRunHeistLoopsRefsAndBroadMatches() async throws {
    let plan = try rootStringPlanFixture()
    let rendered = try plan.canonicalSwiftDSL()

    #expect(rendered == rootStringCanonicalSwiftDSL)

    #if SWIFT_PACKAGE && (os(macOS) || os(Linux))
    let source = """
    import ThePlans

    let heist = try \(rendered)
    """
    let compiled = try await compileCanonicalHeist(source)
    let compiledCanonical = try compiled.canonicalSwiftDSL()
    #expect(compiledCanonical == rendered, "Compiled canonical:\n\(compiledCanonical)\nRendered canonical:\n\(rendered)")
    #endif
}

private func rootStringPlanFixture() throws -> HeistPlan {
    let enterDefinition = try HeistPlan(
        name: "enter",
        parameter: .string(name: "term"),
        body: [
            .action(try ActionStep(
                command: .typeText(text: .ref("term"), target: .label(.contains("Search"))),
                expectation: WaitStep(predicate: .present(.value(.ref("term"))), timeout: 2)
            )),
        ]
    )
    let pressRowDefinition = try HeistPlan(
        name: "pressRow",
        parameter: .elementTarget(name: "row"),
        body: [
            .action(try ActionStep(
                command: .activate(.ref("row")),
                expectation: WaitStep(predicate: .absent(.ref("row")), timeout: 1)
            )),
        ]
    )
    let rowPredicate = ElementPredicate.element(
        label: .contains("Result"),
        identifier: .prefix("row"),
        value: .suffix("available"),
        traits: [.button],
        excludeTraits: [.staticText]
    )
    let readyPredicate = ElementPredicateTemplate.element(
        label: .contains(.literal("Result")),
        identifier: .prefix(.literal("row")),
        value: .suffix(.literal("ready")),
        traits: [.button],
        excludeTraits: [.staticText]
    )
    let plan = try HeistPlan(
        name: "RootSearch",
        parameter: .string(name: "query"),
        definitions: [
            try HeistPlan(name: "Search", definitions: [enterDefinition], body: []),
            try HeistPlan(name: "Rows", definitions: [pressRowDefinition], body: []),
        ],
        body: [
            .invoke(HeistInvocationStep(path: ["Search", "enter"], argument: .string(.ref("query")))),
            .wait(WaitStep(predicate: .present(.label(.ref("query"))), timeout: 1)),
            .conditional(try ConditionalStep(
                cases: [
                    PredicateCase(
                        predicate: .present(readyPredicate),
                        body: [.warn(WarnStep(message: "ready"))]
                    ),
                ],
                elseBody: [.fail(FailStep(message: "not ready"))]
            )),
            .forEachString(try ForEachStringStep(
                values: ["Milk", "Eggs"],
                parameter: "item",
                body: [
                    .action(try ActionStep(
                        command: .typeText(text: .ref("item"), target: .label(.contains("Search"))),
                        expectation: WaitStep(predicate: .present(.label(.ref("item"))), timeout: 2)
                    )),
                ]
            )),
            .forEachElement(try ForEachElementStep(
                matching: rowPredicate,
                limit: 3,
                parameter: "target",
                body: [
                    .invoke(HeistInvocationStep(
                        path: ["Rows", "pressRow"],
                        argument: .elementTarget(.ref("target"))
                    )),
                ]
            )),
        ]
    )

    return plan
}

// swiftlint:disable line_length
private let rootStringCanonicalSwiftDSL = """
    HeistPlan("RootSearch", parameter: "query") { query in
        HeistDef<String>("Search.enter", parameter: "term") { term in
            TypeText(term, into: .label(.contains("Search")))
                .expect(.present(.value(term)), timeout: .seconds(2))
        }

        HeistDef<ElementTarget>("Rows.pressRow", parameter: "row") { row in
            Activate(row)
                .expect(.absent(row), timeout: .seconds(1))
        }

        RunHeist("Search.enter", query)

        WaitFor(.present(.label(query)), timeout: .seconds(1))

        If(.present(.element(label: .contains("Result"), identifier: .prefix("row"), value: .suffix("ready"), traits: [.button], excludeTraits: [.staticText]))) {
            Warn("ready")
        }
        .else {
            Fail("not ready")
        }

        ForEach(["Milk", "Eggs"]) { item in
            TypeText(item, into: .label(.contains("Search")))
                .expect(.present(.label(item)), timeout: .seconds(2))
        }

        ForEach(.matching(.element(label: .contains("Result"), identifier: .prefix("row"), value: .suffix("available"), traits: [.button], excludeTraits: [.staticText])), limit: 3) { target in
            RunHeist("Rows.pressRow", target)
        }
    }
    """
// swiftlint:enable line_length

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

    let plan = try HeistPlan("purchaseFlow") {
        try LibraryScreen.addToCart("Milk")
    }

    #expect(try plan.canonicalSwiftDSL() == """
    HeistPlan("purchaseFlow") {
        HeistDef<String>("LibraryScreen.addToCart", parameter: "item") { item in
            HeistDef<Void>("AddButton.tap") {
                Activate(.label("Add to Cart"))
            }

            Activate(.label(item))

            RunHeist("AddButton.tap")
        }

        RunHeist("LibraryScreen.addToCart", "Milk")
    }
    """)
}

@Test
func `canonical Swift renderer preserves composed expectation with string ref`() throws {
    enum SearchScreen {
        static let search = HeistDef<String>("SearchScreen.search", parameter: "query") { query in
            TypeText(query, into: .label("Search"))
                .expect(.present(.value(query)), timeout: .seconds(1))

            Activate(.label("Search"))
                .expect(.changed(.screen()))
                .expect(.present(.label(query)), timeout: .seconds(5))
        }
    }

    let plan = try HeistPlan("searchFlow") {
        try SearchScreen.search("milk")
    }

    #expect(try plan.canonicalSwiftDSL() == """
    HeistPlan("searchFlow") {
        HeistDef<String>("SearchScreen.search", parameter: "query") { query in
            TypeText(query, into: .label("Search"))
                .expect(.present(.value(query)), timeout: .seconds(1))

            Activate(.label("Search"))
                .expect(.changed(.screen(where: .present(.label(query)))), timeout: .seconds(5))
        }

        RunHeist("SearchScreen.search", "milk")
    }
    """)
}

@Test
func canonicalSwiftRendererRejectsRefsOutsideLoopScope() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .action(try ActionStep(command: .activate(.ref("target")))),
    ])

    do {
        _ = try raw.validatedForRuntimeSafety()
        Issue.record("Expected unresolved ref validation failure")
    } catch let error as HeistPlanRuntimeSafetyError {
        #expect(error.failures.contains { $0.contract == "target_ref must resolve in the current heist scope" })
    }
}

@Test
func decodedRuntimeLoopsRejectNonCanonicalSwiftParameters() throws {
    for json in [invalidElementLoopParameterJSON, invalidStringLoopParameterJSON] {
        let raw = try JSONDecoder().decode(HeistPlanAdmissionCandidate.self, from: Data(json.utf8))
        do {
            _ = try raw.validatedForRuntimeSafety()
            Issue.record("Expected invalid loop parameter validation failure")
        } catch let error as HeistPlanRuntimeSafetyError {
            #expect(error.failures.contains { $0.contract.contains("Swift-style identifier") })
        }
    }
}

@Test
func canonicalSwiftRendererRendersAmbientActions() throws {
    let plan = try HeistPlan(body: [
        .action(try ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "milk")))),
        .action(try ActionStep(command: .editAction(EditActionTarget(action: .paste)))),
        .action(try ActionStep(command: .dismissKeyboard)),
    ])
    #expect(try plan.canonicalSwiftDSL() == """
    HeistPlan {
        SetPasteboard("milk")

        Edit(.paste)

        DismissKeyboard()
    }
    """)
}

@Test
func canonicalSwiftRendererSeparatesSemanticAndMechanicalActions() throws {
    let plan = try HeistPlan(body: [
        .action(try ActionStep(command: .customAction(name: "Archive", target: .predicate(.label("Message"))))),
        .action(try ActionStep(command: .rotor(
            selection: .named("Headings"),
            target: .predicate(.label("Article")),
            direction: .next
        ))),
        .action(try ActionStep(command: .mechanicalTap(TapTarget(
            selection: .coordinate(ScreenPoint(x: 12, y: 34))
        )))),
    ])
    #expect(try plan.canonicalSwiftDSL() == """
    HeistPlan {
        CustomAction("Archive", on: .label("Message"))

        Rotor("Headings", on: .label("Article"), direction: .next)

        Mechanical.Tap(ScreenPoint(x: 12, y: 34))
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
    let plan = try HeistPlan(body: [.action(try ActionStep(command: command))])

    #expect(command.durableHeistActionFailure == nil)
    #expect(try plan.canonicalSwiftDSL() == """
    HeistPlan {
        Mechanical.Swipe(.label("Carousel"), from: UnitPoint(x: 0.8, y: 0.5), to: UnitPoint(x: 0.2, y: 0.5))
    }
    """)
}

@Test
func canonicalSwiftRendererRendersMechanicalActionForms() throws {
    let plan = try HeistPlan(body: [
        .action(try ActionStep(command: .mechanicalTap(TapTarget(
            selection: .element(.predicate(.label("Button")))
        )))),
        .action(try ActionStep(command: .mechanicalTap(TapTarget(
            selection: .elementUnitPoint(
                .predicate(.label("Cell")),
                UnitPoint(x: 0.25, y: 0.75)
            )
        )))),
        .action(try ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .coordinate(ScreenPoint(x: 1.25, y: 2.5)),
            duration: GestureDuration(seconds: 1.2)
        )))),
        .action(try ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .elementUnitPoint(
                .predicate(.label("Message")),
                UnitPoint(x: 0.5, y: 0.2)
            ),
            duration: GestureDuration(seconds: 1.4)
        )))),
        .action(try ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .elementDirection(
            .predicate(.label("List")),
            .up
        ))))),
        .action(try ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .point(
            start: .coordinate(ScreenPoint(x: 10, y: 20)),
            destination: .direction(.left)
        ))))),
        .action(try ActionStep(command: .mechanicalDrag(DragTarget(
            start: .element(.predicate(.label("Slider"))),
            end: ScreenPoint(x: 200, y: 40)
        )))),
        .action(try ActionStep(command: .mechanicalDrag(DragTarget(
            start: .elementUnitPoint(.predicate(.label("Slider")), UnitPoint(x: 0.8, y: 0.5)),
            end: ScreenPoint(x: 220, y: 40)
        )))),
        .action(try ActionStep(command: .mechanicalDrag(DragTarget(
            start: .coordinate(ScreenPoint(x: 3.3333333, y: 4)),
            end: ScreenPoint(x: 5, y: 6.5)
        )))),
    ])

    #expect(try plan.canonicalSwiftDSL() == """
    HeistPlan {
        Mechanical.Tap(.label("Button"))

        Mechanical.Tap(.label("Cell"), at: UnitPoint(x: 0.25, y: 0.75))

        Mechanical.LongPress(ScreenPoint(x: 1.25, y: 2.5), duration: GestureDuration(seconds: 1.2))

        Mechanical.LongPress(.label("Message"), at: UnitPoint(x: 0.5, y: 0.2), duration: GestureDuration(seconds: 1.4))

        Mechanical.Swipe(.label("List"), .up)

        Mechanical.Swipe(from: ScreenPoint(x: 10, y: 20), .left)

        Mechanical.Drag(.label("Slider"), to: ScreenPoint(x: 200, y: 40))

        Mechanical.Drag(.label("Slider"), from: UnitPoint(x: 0.8, y: 0.5), to: ScreenPoint(x: 220, y: 40))

        Mechanical.Drag(from: ScreenPoint(x: 3.333333, y: 4), to: ScreenPoint(x: 5, y: 6.5))
    }
    """)
}

@Test
func nonDurableActionShapeExecutesButFailsCanonicalRendering() throws {
    let command = HeistActionCommand.rotor(
        selection: .index(0),
        target: .target(.predicate(.label("Article"))),
        direction: .next
    )
    let plan = try HeistPlan(body: [.action(try ActionStep(command: command))])
    let reason = try #require(command.durableHeistActionFailure)

    // Durability is enforced at rendering, not execution: a non-durable shape is
    // runtime-valid but cannot be rendered to canonical Swift DSL.

    do {
        _ = try plan.canonicalSwiftDSL()
        Issue.record("Expected non-durable action to fail canonical rendering")
    } catch let error as HeistCanonicalSwiftDSLError {
        #expect(error == .unsupportedAction(reason))
    }
}

@Test
func viewportDebugActionsAreNotDurableHeistDSL() throws {
    let commands: [HeistActionCommand] = [
        .viewportScroll(ScrollTarget(direction: .down)),
        .viewportScroll(ScrollTarget(selection: .element(.predicate(.label("List"))), direction: .down)),
        .viewportScroll(ScrollTarget(selection: .container("scrollable_0_0_40_50"), direction: .down)),
        .viewportScrollToVisible(.target(.label("Checkout"))),
        .viewportScrollToEdge(ScrollToEdgeTarget(edge: .bottom)),
        .viewportScrollToEdge(ScrollToEdgeTarget(selection: .element(.predicate(.label("List"))), edge: .bottom)),
        .viewportScrollToEdge(ScrollToEdgeTarget(selection: .container("scrollable_0_0_40_50"), edge: .bottom)),
    ]

    for command in commands {
        let plan = try HeistPlan(body: [.action(try ActionStep(command: command))])
        let reason = try #require(command.durableHeistActionFailure)

        #expect(reason.contains("viewport debug command"))

        // Durability is a canonical DSL concern, not runtime safety:
        // viewport commands construct as runtime-valid plans but cannot render
        // to canonical Swift DSL.

        do {
            _ = try plan.canonicalSwiftDSL()
            Issue.record("Expected containerName viewport action to fail canonical rendering")
        } catch let error as HeistCanonicalSwiftDSLError {
            #expect(error == .unsupportedAction(reason))
        }
    }

    let jsonPlan = try JSONDecoder().decode(HeistPlan.self, from: Data("""
    {
      "version": 1,
      "body": [
        {
          "type": "action",
          "action": {
            "command": {
              "type": "scroll",
              "payload": {
                "container": "scrollable_0_0_40_50",
                "direction": "down"
              }
            }
          }
        }
      ]
    }
    """.utf8))

    // A decoded viewport plan is runtime-valid for execution but not renderable.
    #expect(throws: HeistCanonicalSwiftDSLError.self) {
        _ = try jsonPlan.canonicalSwiftDSL()
    }
}

#if SWIFT_PACKAGE && (os(macOS) || os(Linux))
private func compileCanonicalHeist(_ source: String) async throws -> HeistPlan {
    let tempDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("canonical-swift-compile-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDirectory) }
    let sourceURL = tempDirectory.appendingPathComponent("Canonical.swift")
    try source.write(to: sourceURL, atomically: true, encoding: .utf8)
    let result = await HeistCompiler(configuration: .init(packageRoot: buttonHeistPackageRoot()))
        .compileFile(sourceURL, entry: "heist")
    switch result {
    case .success(let plan, _):
        return plan
    case .failure(let diagnostics):
        throw CompileBackFailure(diagnostics: diagnostics.map(\.description))
    }
}

private func buttonHeistPackageRoot() -> URL {
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

private struct CompileBackFailure: Error, CustomStringConvertible {
    let diagnostics: [String]

    var description: String {
        diagnostics.joined(separator: "\n")
    }
}
#endif

private let fullASTJSON = """
{
  "version": 1,
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
      "type": "wait",
      "wait": {
        "predicate": { "type": "present", "element": { "label": "Results" } },
        "timeout": 8,
        "else_body": [
          { "type": "fail", "fail": { "message": "timeout" } }
        ]
      }
    },
    {
      "type": "warn",
      "warn": { "message": "results" }
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
  "version": 1,
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
  "version": 1,
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
HeistPlan {
    Activate(.label("Sign In"))
        .expect(.present(.label("Home")), timeout: .seconds(5))

    WaitFor(.absent(.label("Loading")), timeout: .seconds(1))

    If(.present(.label("Home"))) {
        Warn("home")
    }
    .else {
        Fail("unknown")
    }

    WaitFor(.present(.label("Results")), timeout: .seconds(8))
    .else {
        Fail("timeout")
    }

    Warn("results")

    ForEach(.matching(.label("Delete")), limit: 20) { target in
        Activate(target)
            .expect(.absent(target), timeout: .seconds(2))
    }

    ForEach(["Milk", "Eggs"]) { item in
        TypeText(item, into: .label("Add item"))
            .expect(.present(.label(item)), timeout: .seconds(2))
    }

    Warn("done")

    Fail("stop")
}
"""
