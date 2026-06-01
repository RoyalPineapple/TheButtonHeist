import XCTest
import TheScore

final class HeistSwiftRendererTests: XCTestCase {
    func testRendersSimpleAction() throws {
        let step = try ActionStep(command: .activate(.predicate(ElementPredicate(label: "Login"))))
        let output = try render(plan([.action(step)]))

        XCTAssertEqual(output, """
        Heist {
            Activate(.label("Login"))
        }
        """)
    }

    func testRendersTapTypeTextAndScrollActions() throws {
        let tap = try ActionStep(command: .oneFingerTap(TapTarget(selection: .coordinate(ScreenPoint(x: 10.5, y: 20)))))
        let typeWithoutTarget = try ActionStep(command: .typeText(TypeTextTarget(text: "hello")))
        let typeIntoTarget = try ActionStep(command: .typeText(TypeTextTarget(
            text: "world",
            elementTarget: .predicate(ElementPredicate(identifier: "field"))
        )))
        let scroll = try ActionStep(command: .scroll(ScrollTarget(direction: .up)))
        let targetedScroll = try ActionStep(command: .scroll(ScrollTarget(
            elementTarget: .predicate(ElementPredicate(label: "List")),
            direction: .down
        )))

        let output = try render(plan([
            .action(tap),
            .action(typeWithoutTarget),
            .action(typeIntoTarget),
            .action(scroll),
            .action(targetedScroll),
        ]))

        XCTAssertEqual(output, """
        Heist {
            Tap(.point(x: 10.5, y: 20))
            TypeText("hello")
            TypeText("world", into: .identifier("field"))
            Scroll(.up)
            Scroll(.down, in: .label("List"))
        }
        """)
    }

    func testRendersActionExpectationOnNextIndentedLine() throws {
        let step = try ActionStep(
            command: .activate(.predicate(ElementPredicate(label: "Submit"))),
            expectation: WaitStep(
                predicate: .state(.present(ElementPredicate(identifier: "receipt"))),
                timeout: 2.5
            )
        )
        let output = try render(plan([.action(step)]))

        XCTAssertEqual(output, """
        Heist {
            Activate(.label("Submit"))
                .expect(.present(.identifier("receipt")), timeout: .seconds(2.5))
        }
        """)
    }

    func testRendersWaitWarnAndFailSteps() throws {
        let output = try render(plan([
            .wait(WaitStep(predicate: .state(.present(ElementPredicate(label: "Ready"))), timeout: 3)),
            .warn(WarnStep(message: "not ideal")),
            .fail(FailStep(message: "stop now")),
        ]))

        XCTAssertEqual(output, """
        Heist {
            WaitFor(.present(.label("Ready")), timeout: .seconds(3))
            Warn("not ideal")
            Fail("stop now")
        }
        """)
    }

    func testRendersSingleFieldPredicates() throws {
        let output = try render(plan([
            .wait(WaitStep(predicate: .state(.present(ElementPredicate(label: "Title"))), timeout: 1)),
            .wait(WaitStep(predicate: .state(.present(ElementPredicate(identifier: "primary.save"))), timeout: 2)),
            .wait(WaitStep(predicate: .state(.present(ElementPredicate(value: "Ready"))), timeout: 3)),
        ]))

        XCTAssertEqual(output, """
        Heist {
            WaitFor(.present(.label("Title")), timeout: .seconds(1))
            WaitFor(.present(.identifier("primary.save")), timeout: .seconds(2))
            WaitFor(.present(.value("Ready")), timeout: .seconds(3))
        }
        """)
    }

    func testRendersMultiFieldElementPredicate() throws {
        let predicate = ElementPredicate(
            label: "Save",
            identifier: "primary.save",
            value: "Ready",
            traits: [.selected, .button],
            excludeTraits: [.notEnabled]
        )
        let output = try render(plan([
            .wait(WaitStep(predicate: .state(.present(predicate)), timeout: 1)),
        ]))
        let waitLine = "WaitFor(.present(.element(label: \"Save\", identifier: \"primary.save\", value: \"Ready\", " +
            "traits: [.button, .selected], excludeTraits: [.notEnabled])), timeout: .seconds(1))"

        XCTAssertEqual(output, """
        Heist {
            \(waitLine)
        }
        """)
    }

    func testRendersAllStatePredicate() throws {
        let output = try render(plan([
            .wait(WaitStep(
                predicate: .state(.all([
                    .present(ElementPredicate(label: "Ready")),
                    .absent(ElementPredicate(identifier: "loading")),
                ])),
                timeout: 4
            )),
        ]))

        XCTAssertEqual(output, """
        Heist {
            WaitFor(.all([.present(.label("Ready")), .absent(.identifier("loading"))]), timeout: .seconds(4))
        }
        """)
    }

    func testRendersChangedScreenPredicate() throws {
        let output = try render(plan([
            .wait(WaitStep(
                predicate: .changed(.screen(where: .present(ElementPredicate(label: "Receipt")))),
                timeout: 5
            )),
        ]))

        XCTAssertEqual(output, """
        Heist {
            WaitFor(.changed(.screen(where: .present(.label("Receipt")))), timeout: .seconds(5))
        }
        """)
    }

    func testEscapesSwiftStringLiterals() throws {
        let step = try ActionStep(command: .typeText(TypeTextTarget(
            text: "say \"hi\"\\there\nnext\tend\0",
            elementTarget: .predicate(ElementPredicate(label: "Field \"A\""))
        )))
        let output = try render(plan([
            .action(step),
            .warn(WarnStep(message: "path \\tmp\\file")),
        ]))

        XCTAssertEqual(output, #"""
        Heist {
            TypeText("say \"hi\"\\there\nnext\tend\0", into: .label("Field \"A\""))
            Warn("path \\tmp\\file")
        }
        """#)
    }

    func testThrowsForUnsupportedCommand() throws {
        let step = try ActionStep(command: .increment(.predicate(ElementPredicate(label: "Stepper"))))
        let renderedPlan = plan([.action(step)])

        do {
            _ = try render(renderedPlan)
            XCTFail("Expected unsupported command failure")
        } catch let error as HeistSwiftRendererError {
            XCTAssertEqual(error, .unsupportedCommand("increment"))
        } catch {
            XCTFail("Expected HeistSwiftRendererError, got \(error)")
        }
    }

    private func render(_ plan: HeistPlan) throws -> String {
        try HeistSwiftRenderer().render(plan)
    }

    private func plan(_ steps: [HeistStep]) -> HeistPlan {
        HeistPlan(steps: steps)
    }
}
