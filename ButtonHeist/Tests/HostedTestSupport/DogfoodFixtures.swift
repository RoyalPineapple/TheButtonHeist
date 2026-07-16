#if canImport(UIKit)
import ButtonHeistTesting
import TheInsideJob
import ThePlans
import TheScore

package enum ExpectedHeistFailureError: Error, Equatable {
    case heistPassed(HeistDefinitionPath)
}

@MainActor
package func expectHeistFailure<Content: HeistContent>(
    _ name: HeistDefinitionPath,
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
                    .expect(.changed(.screen([.exists(.predicate(destinationTitle))])), timeout: 8)
            }
        }
    }
}

package enum ControlsDemoScreen {
    package static let openScreen = HeistDef<String>("ControlsDemo.openScreen", parameter: "screen") { screen in
        Activate(.predicate(ElementPredicateTemplate(label: .exact(screen), traits: [.button])))
            .expect(.changed(.screen([.exists(.label(screen))])), timeout: 8)
    }
}

package enum TextInputScreen {
    private static let nameField = AccessibilityTarget.element(.value("Name"), traits: [.textEntry])
    private static let emailField = AccessibilityTarget.element(.value("Email"), traits: [.textEntry])

    package static let fillProfile = HeistDef<String>("TextInputScreen.fillProfile", parameter: "name") { name in
        TypeText(name, into: nameField)
            .expect(.exists(.value(name)), timeout: 2)

        DismissKeyboard()
            .withoutExpectation("Ends the first field edit before focusing the email field")

        TypeText("dogfood@example.com", into: emailField)
            .expect(.exists(.value("dogfood@example.com")), timeout: 4)

        DismissKeyboard()
            .withoutExpectation("Keyboard dismissal only prepares navigation")
    }

}

package enum TodoScreen {
    package static let completeItem = HeistDef<String>("TodoScreen.completeItem", parameter: "item") { item in
        let completedItem = ElementPredicateTemplate(
            label: .exact(item),
            value: .exact("Completed")
        )
        let visibleItem = ElementPredicateTemplate(label: .exact(item))

        WaitFor(.exists(.predicate(visibleItem)), timeout: 4)

        If {
            Case(.exists(.predicate(completedItem))) {
                WaitFor(.exists(.predicate(completedItem)), timeout: 1)
            }
            Else {
                CustomAction("Toggle", on: .label(item))
                    .withoutExpectation("Completion is proven by the following wait")

                WaitFor(.exists(.predicate(completedItem)), timeout: 4)
            }
        }
    }
}

package enum CalculatorScreen {
    package static let addSevenAndFive = HeistDef<Void>("CalculatorScreen.addSevenAndFive") {
        Activate(.element(.label("all clear"), .traits([.button])))
            .expect(.exists(.label("0")), timeout: 1)

        Activate(.element(.label("7"), .traits([.button])))
            .expect(.exists(.label("7")), timeout: 1)

        Activate(.element(.label("+"), .traits([.button])))
            .expect(.changed(.elements()), timeout: 1)

        Activate(.element(.label("5"), .traits([.button])))
            .expect(.exists(.label("5")), timeout: 1)

        Activate(.element(.label("equals"), .traits([.button])))
            .expect(.exists(.label("12")), timeout: 1)
    }
}

#endif // canImport(UIKit)
