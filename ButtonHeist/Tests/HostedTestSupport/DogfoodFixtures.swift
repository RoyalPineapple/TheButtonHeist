#if canImport(UIKit)
import ButtonHeistTesting
import TheInsideJob
import ThePlans
import TheScore

package enum ExpectedHeistFailureError: Error, Equatable {
    case heistPassed(String)
}

@MainActor
package func expectHeistFailure<Content: HeistContent>(
    _ name: String,
    @HeistBuilder content: @escaping () throws -> Content
) async throws -> Heist.Failure {
    do {
        _ = try await runHeist(name, content)
        throw ExpectedHeistFailureError.heistPassed(name)
    } catch let failure as Heist.Failure {
        return failure
    }
}

package enum DogfoodHome {
    package static let openScreen = HeistDef<String>("DemoHome.openScreen", parameter: "screen") { screen in
        let destinationTitle = ElementPredicateTemplate(label: .exact(screen), traits: [.header])
        let backToRoot = try DemoNavigation.backToRootIfNeeded()

        If {
            Case(.exists(.predicate(destinationTitle))) {
                WaitFor(.exists(.predicate(destinationTitle)))
            }
            Else {
                backToRoot

                Activate(.predicate(ElementPredicateTemplate(label: .exact(screen), traits: [.button])))
                    .expect(.changed(.screen([.exists(.predicate(destinationTitle))])), timeout: .seconds(8))
            }
        }
    }
}

package enum ControlsDemoScreen {
    package static let openScreen = HeistDef<String>("ControlsDemo.openScreen", parameter: "screen") { screen in
        Activate(.predicate(ElementPredicateTemplate(label: .exact(screen), traits: [.button])))
            .expect(.changed(.screen([.exists(.label(screen))])), timeout: .seconds(8))
    }
}

package enum TextInputScreen {
    private static let nameField = AccessibilityTarget.element(.value("Name"), traits: [.textEntry])
    private static let emailField = AccessibilityTarget.element(.value("Email"), traits: [.textEntry])

    package static let fillProfile = HeistDef<String>("TextInputScreen.fillProfile", parameter: "name") { name in
        TypeText(name, into: nameField)
            .expect(.exists(.value(name)), timeout: .seconds(2))

        DismissKeyboard()
            .withoutExpectation("Ends the first field edit before focusing the email field")

        TypeText("dogfood@example.com", into: emailField)
            .expect(.exists(.value("dogfood@example.com")), timeout: .seconds(4))

        DismissKeyboard()
            .withoutExpectation("Keyboard dismissal only prepares navigation")
    }

    package static let pasteName = HeistDef<Void>("TextInputScreen.pasteName") {
        ClearText(nameField)
            .withoutExpectation("Focuses the name field through the text input pipeline before paste")

        SetPasteboard("Dogfood clipboard name")
            .withoutExpectation("Seeds pasteboard for the public Edit(.paste) action")

        Edit(.paste)
            .expect(.exists(.value("Dogfood clipboard name")), timeout: .seconds(2))

        DismissKeyboard()
            .withoutExpectation("Keyboard dismissal only prepares navigation")
    }
}

package enum TodoScreen {
    package static let completeItem = HeistDef<String>("TodoScreen.completeItem", parameter: "item") { item in
        let completedItem = ElementPredicateTemplate(
            label: .exact(item),
            value: .exact(.literal("Completed"))
        )
        let visibleItem = ElementPredicateTemplate(label: .exact(item))

        WaitFor(.exists(.predicate(visibleItem)), timeout: .seconds(4))

        If {
            Case(.exists(.predicate(completedItem))) {
                WaitFor(.exists(.predicate(completedItem)), timeout: .seconds(1))
            }
            Else {
                CustomAction("Toggle", on: .label(item))
                    .withoutExpectation("Completion is proven by the following wait")

                WaitFor(.exists(.predicate(completedItem)), timeout: .seconds(4))
            }
        }
    }
}

package enum CalculatorScreen {
    package static let addSevenAndFive = HeistDef<Void>("CalculatorScreen.addSevenAndFive") {
        Activate(.element(.label("all clear"), .traits([.button])))
            .expect(.exists(.label("0")), timeout: .seconds(1))

        Activate(.element(.label("7"), .traits([.button])))
            .expect(.exists(.label("7")), timeout: .seconds(1))

        Activate(.element(.label("+"), .traits([.button])))
            .expect(.changed(.elements()), timeout: .seconds(1))

        Activate(.element(.label("5"), .traits([.button])))
            .expect(.exists(.label("5")), timeout: .seconds(1))

        Activate(.element(.label("equals"), .traits([.button])))
            .expect(.exists(.label("12")), timeout: .seconds(1))
    }
}

package enum TogglePickerScreen {
    package static let subscribe = HeistDef<Void>("TogglePickerScreen.subscribe") {
        Activate(.label("Subscribe to newsletter"))
            .expect(.exists(.label("Last action: Toggle: ON")), timeout: .seconds(2))
    }
}

package enum AlertsScreen {
    package static let acceptSimpleAlert = HeistDef<Void>("AlertsScreen.acceptSimpleAlert") {
        Activate(.element(.label("Show Alert"), .traits([.button])))
            .expect(.exists(.label("Alert Title")), timeout: .seconds(2))

        Activate(.element(.label("OK"), .traits([.button])))
            .expect(.missing(.label("Alert Title")), timeout: .seconds(2))

        WaitFor(.exists(.label("Last action: Alert: OK")), timeout: .seconds(2))
    }
}

package enum AdjustableControlsScreen {
    package static let adjustVolume = HeistDef<Void>("AdjustableControls.adjustVolume") {
        Increment(.label("Volume"))
            .expect(.exists(.value("60")), timeout: .seconds(2))

        Decrement(.label("Volume"))
            .expect(.exists(.value("50")), timeout: .seconds(2))
    }

    package static let driveVolumeToMaximum = HeistDef<Void>("AdjustableControls.driveVolumeToMaximum") {
        RepeatUntil(.exists(.element(.label("Volume"), .value("100"))), timeout: .seconds(8)) {
            Increment(.label("Volume"))
        }.else {
            Fail("volume did not reach 100")
        }
    }
}

package enum CustomRotorsScreen {
    package static let findFirstError = HeistDef<Void>("CustomRotors.findFirstError") {
        Rotor("Errors", on: .label("Rotor Host"))
            .expect(.exists(.label("Rotor Result: Missing amount")), timeout: .seconds(2))
    }
}

package enum TouchCanvasScreen {
    private static let canvas = AccessibilityTarget.element(.label("Touch Canvas"), .traits([.allowsDirectInteraction]))

    package static let exerciseMechanicalGestures = HeistDef<Void>("TouchCanvas.exerciseMechanicalGestures") {
        Mechanical.Tap(canvas)
            .withoutExpectation("Canvas drawing is intentionally spatial, not semantic")

        Mechanical.LongPress(canvas)
            .withoutExpectation("Long press gesture delivery is the behavior under test")

        Mechanical.Swipe(canvas, .left)
            .withoutExpectation("Swipe gesture delivery is the behavior under test")

        Mechanical.Drag(
            from: ScreenPoint(x: 120, y: 360),
            to: ScreenPoint(x: 260, y: 460)
        )
        .withoutExpectation("Drag gesture delivery is the behavior under test")
    }
}

package enum LongListScreen {
    private static let topRow = ElementPredicateTemplate(label: .exact("Widget 0, Hardware"))

    package static let openTopAnchor = HeistDef<Void>("LongList.openTopAnchor") {
        WaitFor(.exists(.predicate(topRow)), timeout: .seconds(8))
    }
}

package extension HeistExecutionResult {
    var actionMethods: [ActionMethod] {
        steps.flatMap(\.actionMethods)
    }

    var repeatUntilSteps: [HeistExecutionStepResult] {
        steps.flatMap(\.repeatUntilSteps)
    }
}

private extension HeistExecutionStepResult {
    var actionMethods: [ActionMethod] {
        (actionEvidence?.dispatchResult.map { [$0.method] } ?? []) + children.flatMap(\.actionMethods)
    }

    var repeatUntilSteps: [HeistExecutionStepResult] {
        (kind == .repeatUntil ? [self] : []) + children.flatMap(\.repeatUntilSteps)
    }
}
#endif // canImport(UIKit)
