import Foundation
import Testing
@_spi(ButtonHeistInternals) import ThePlans

@Test
func swiftDSLAndJSONProjectToEquivalentCanonicalSwift() throws {
    let swiftPlan = try HeistPlan {
        Activate(.label("Sign In"))
            .expect(.exists(.label("Home")), timeout: 5)

        WaitFor(.missing(.label("Loading")), timeout: 1)

        If {
            Case(.exists(.label("Home"))) {
                Warn("home")
            }

            Else {
                Fail("unknown")
            }
        }

        WaitFor(.exists(.label("Results")), timeout: 8)
            .else {
                Fail("timeout")
            }

        Warn("results")

        ForEach(.label("Delete"), limit: 20) { target in
            Activate(target)
                .expect(.missing(target), timeout: 2)
        }

        ForEach("Milk", "Eggs") { item in
            TypeText(item, into: .label("Add item"))
                .expect(.exists(.label(item)), timeout: 2)
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
func rootAccessibilityTargetPlanRendersCanonicalSwiftAndCompilesBack() async throws {
    let plan = try HeistPlan("RecordedTarget", targetParameter: "target") { target in
        Activate(target)
            .expect(.missing(target), timeout: 2)

        WaitFor(.exists(target), timeout: 1)

        If {
            Case(.exists(target)) {
                CustomAction("Archive", on: target)
                    .expect(.changed(.screen([.exists(target)])), timeout: 3)
            }

            Else {
                Fail("target missing")
            }
        }

        WaitFor(.missing(target), timeout: 4)

        Warn("target removed")
    }

    let rendered = try plan.canonicalSwiftDSL()

    #expect(rendered == """
    HeistPlan("RecordedTarget", targetParameter: "target") { target in
        Activate(target)
            .expect(.missing(target), timeout: 2)

        WaitFor(.exists(target), timeout: 1)

        If(.exists(target)) {
            CustomAction("Archive", on: target)
                .expect(.changed(.screen([.exists(target)])), timeout: 3)
        }
        .else {
            Fail("target missing")
        }

        WaitFor(.missing(target), timeout: 4)

        Warn("target removed")
    }
    """)

    #if SWIFT_PACKAGE && (os(macOS) || os(Linux))
    let source = """
    import ThePlans

    func heist() throws -> HeistPlan {
        try \(rendered)
    }
    """
    let compiled = try await compileCanonicalHeist(source)
    #expect(try compiled.canonicalSwiftDSL() == rendered)
    #endif
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
                .expect(.exists(.value(query)))

            Activate(.label("Search"))
                .expect(.changed(.screen()))
                .expect(.exists(.label(query)), timeout: 5)
        }
    }

    let plan = try HeistPlan("searchFlow") {
        try SearchScreen.search("milk")
    }

    #expect(try plan.canonicalSwiftDSL() == """
    HeistPlan("searchFlow") {
        HeistDef<String>("SearchScreen.search", parameter: "query") { query in
            TypeText(query, into: .label("Search"))
                .expect(.exists(.value(query)))

            Activate(.label("Search"))
                .expect(.changed(.screen([.exists(.label(query))])), timeout: 5)
        }

        RunHeist("SearchScreen.search", "milk")
    }
    """)
}

@Test
func canonicalSwiftRendererRejectsRefsOutsideLoopScope() throws {
    let raw = HeistPlanAdmissionCandidate(body: [
        .action(ActionStep(command: .activate(.ref("target")))),
    ])

    do {
        _ = try raw.validatedForRuntimeSafety()
        Issue.record("Expected unresolved ref validation failure")
    } catch let error as HeistPlanRuntimeSafetyError {
        #expect(error.failures.contains { $0.contract == "target ref must resolve in the current heist scope" })
    }
}

@Test
func canonicalSwiftRendererRendersAmbientActions() throws {
    let plan = try HeistPlan(body: [
        .action(ActionStep(command: .setPasteboard(SetPasteboardTarget(text: "milk")))),
        .action(ActionStep(command: .editAction(EditActionTarget(action: .paste)))),
        .action(ActionStep(command: .dismissKeyboard)),
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
        .action(ActionStep(command: .customAction(name: "Archive", target: .predicate(.label("Message"))))),
        .action(ActionStep(command: .rotor(
            selection: .named("Headings"),
            target: .predicate(.label("Article")),
            direction: .next
        ))),
        .action(ActionStep(command: .mechanicalTap(TapTarget(
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
    let plan = try HeistPlan(body: [.action(ActionStep(command: command))])

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
        .action(ActionStep(command: .mechanicalTap(TapTarget(
            selection: .element(.predicate(.label("Button")))
        )))),
        .action(ActionStep(command: .mechanicalTap(TapTarget(
            selection: .elementUnitPoint(
                .predicate(.label("Cell")),
                UnitPoint(x: 0.25, y: 0.75)
            )
        )))),
        .action(ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .coordinate(ScreenPoint(x: 1.25, y: 2.5)),
            duration: 1.2
        )))),
        .action(ActionStep(command: .mechanicalLongPress(LongPressTarget(
            selection: .elementUnitPoint(
                .predicate(.label("Message")),
                UnitPoint(x: 0.5, y: 0.2)
            ),
            duration: 1.4
        )))),
        .action(ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .elementDirection(
            .predicate(.label("List")),
            .up
        ))))),
        .action(ActionStep(command: .mechanicalSwipe(SwipeTarget(selection: .pointDirection(
            start: ScreenPoint(x: 10, y: 20),
            direction: .left
        ))))),
        .action(ActionStep(command: .mechanicalDrag(DragTarget(
            start: .element(.predicate(.label("Slider"))),
            end: ScreenPoint(x: 200, y: 40)
        )))),
        .action(ActionStep(command: .mechanicalDrag(DragTarget(
            start: .elementUnitPoint(.predicate(.label("Slider")), UnitPoint(x: 0.8, y: 0.5)),
            end: ScreenPoint(x: 220, y: 40)
        )))),
        .action(ActionStep(command: .mechanicalDrag(DragTarget(
            start: .coordinate(ScreenPoint(x: 3.3333333, y: 4)),
            end: ScreenPoint(x: 5, y: 6.5)
        )))),
    ])

    #expect(try plan.canonicalSwiftDSL() == """
    HeistPlan {
        Mechanical.Tap(.label("Button"))

        Mechanical.Tap(.label("Cell"), at: UnitPoint(x: 0.25, y: 0.75))

        Mechanical.LongPress(ScreenPoint(x: 1.25, y: 2.5), duration: 1.2)

        Mechanical.LongPress(.label("Message"), at: UnitPoint(x: 0.5, y: 0.2), duration: 1.4)

        Mechanical.Swipe(.label("List"), .up)

        Mechanical.Swipe(from: ScreenPoint(x: 10, y: 20), .left)

        Mechanical.Drag(.label("Slider"), to: ScreenPoint(x: 200, y: 40))

        Mechanical.Drag(.label("Slider"), from: UnitPoint(x: 0.8, y: 0.5), to: ScreenPoint(x: 220, y: 40))

        Mechanical.Drag(from: ScreenPoint(x: 3.333333, y: 4), to: ScreenPoint(x: 5, y: 6.5))
    }
    """)
}

@Test
func nonDurableActionShapeFailsPlanAdmission() throws {
    let command = HeistActionCommand.rotor(
        selection: .index(0),
        target: .predicate(.label("Article")),
        direction: .next
    )
    let reason = try #require(command.durableHeistActionFailure)

    do {
        _ = try HeistPlan(body: [.action(ActionStep(command: command))])
        Issue.record("Expected non-durable action to fail plan admission")
    } catch let error as HeistPlanRuntimeSafetyError {
        expectNonDurableHeistActionFailure(error.failures, observed: reason)
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
    }
}

@Test
func viewportDebugActionsAreNotDurableHeistDSL() throws {
    let commands: [HeistActionCommand] = [
        .viewportScroll(ScrollTarget(direction: .down)),
        .viewportScroll(ScrollTarget(selection: .element(.predicate(.label("List"))), direction: .down)),
        .viewportScroll(ScrollTarget(selection: .container("scrollable_0_0_40_50"), direction: .down)),
        .viewportScrollToVisible(.label("Checkout")),
        .viewportScrollToEdge(ScrollToEdgeTarget(edge: .bottom)),
        .viewportScrollToEdge(ScrollToEdgeTarget(selection: .element(.predicate(.label("List"))), edge: .bottom)),
        .viewportScrollToEdge(ScrollToEdgeTarget(selection: .container("scrollable_0_0_40_50"), edge: .bottom)),
    ]

    for command in commands {
        let reason = try #require(command.durableHeistActionFailure)

        #expect(reason.contains("viewport debug command"))

        do {
            _ = try HeistPlan(body: [.action(ActionStep(command: command))])
            Issue.record("Expected viewport action to fail plan admission")
        } catch let error as HeistPlanRuntimeSafetyError {
            expectNonDurableHeistActionFailure(error.failures, observed: reason)
        } catch {
            Issue.record("Expected runtime safety error, got \(error)")
        }
    }

    do {
        _ = try JSONDecoder().decode(HeistPlan.self, from: Data("""
    {
      "version": 2,
      "body": [
        {
          "type": "action",
          "action": {
            "command": {
              "type": "scroll",
              "payload": {
                "containerName": "scrollable_0_0_40_50",
                "direction": "down"
              }
            }
          }
        }
      ]
    }
    """.utf8))
        Issue.record("Expected viewport JSON action to fail plan admission")
    } catch let error as HeistPlanRuntimeSafetyError {
        expectNonDurableHeistActionFailure(
            error.failures,
            observed: "scroll is a viewport debug command, not a durable heist action"
        )
    } catch {
        Issue.record("Expected runtime safety error, got \(error)")
    }
}

private let nonDurableHeistActionRepairHint =
    "Use a direct client command for viewport/debug/session actions, or replace " +
    "this with a canonical durable DSL action."

private func expectNonDurableHeistActionFailure(
    _ failures: [HeistPlanRuntimeSafetyFailure],
    observed: String,
    path: String = "$.body[0].action.command"
) {
    #expect(failures.contains {
        $0.path.description == path
            && $0.contract == "durable heist action"
            && $0.observed == observed
            && $0.correction == nonDurableHeistActionRepairHint
    }, "\(failures)")
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
        .deletingLastPathComponent()
}

private struct CompileBackFailure: Error, CustomStringConvertible {
    let diagnostics: [String]

    var description: String {
        diagnostics.joined(separator: "\n")
    }
}
#endif
