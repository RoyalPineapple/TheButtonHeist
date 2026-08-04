#if canImport(UIKit)
import ButtonHeistTesting
import TheInsideJob
@_spi(AdversarialLab) import ThePlans
import TheScore

package enum ExpectedHeistFailureError: Error, Equatable {
    case heistPassed(HeistDefinitionPath)
}

@MainActor
package func expectHeistFailure(
    _ name: HeistDefinitionPath,
    @HeistBuilder content: @escaping () throws -> HeistContent
) async throws -> Heist.Failure {
    do {
        _ = try await runHeist(name, content)
        throw ExpectedHeistFailureError.heistPassed(name)
    } catch let failure as Heist.Failure {
        return failure
    }
}

package enum AdversarialScenarioExecutionError: Error, Equatable {
    case expectedSuccess(AdversarialScenarioCatalog.Scenario)
    case expectedFailure(AdversarialScenarioCatalog.Scenario)
    case missingDiagnosticContract(AdversarialScenarioCatalog.Scenario)
    case diagnosticMismatch(AdversarialScenarioCatalog.Scenario, String)
}

extension Interface {
    package func containsElement(label: String, value: String? = nil) -> Bool {
        projectedElements.contains {
            $0.semantics.assertable.label == label
                && (value == nil || $0.semantics.assertable.value == value)
        }
    }
}

@MainActor
package func runAdversarialScenario(
    _ scenario: AdversarialScenarioCatalog.Scenario,
    opening route: @MainActor (AdversarialScenarioCatalog.Route) async throws -> Void
) async throws -> Heist {
    guard scenario.expectedOutcome == .commandSucceeds else {
        throw AdversarialScenarioExecutionError.expectedSuccess(scenario)
    }
    try await route(scenario.route)
    return try await runHeist(scenario.plan())
}

@MainActor
package func runFailingAdversarialScenario(
    _ scenario: AdversarialScenarioCatalog.Scenario,
    opening route: @MainActor (AdversarialScenarioCatalog.Route) async throws -> Void
) async throws -> Heist.Failure {
    guard scenario.expectedOutcome == .commandFailsWithDiagnostic else {
        throw AdversarialScenarioExecutionError.expectedFailure(scenario)
    }
    try await route(scenario.route)
    do {
        _ = try await runHeist(scenario.plan())
        throw AdversarialScenarioExecutionError.expectedFailure(scenario)
    } catch let failure as Heist.Failure {
        guard let diagnostic = scenario.expectedEvidence.first(where: {
            $0.kind == .diagnostic
        })?.label else {
            throw AdversarialScenarioExecutionError.missingDiagnosticContract(scenario)
        }
        guard failure.description.localizedCaseInsensitiveContains(diagnostic) else {
            throw AdversarialScenarioExecutionError.diagnosticMismatch(scenario, diagnostic)
        }
        return failure
    }
}

package enum DogfoodHome {
    package static let openScreen = HeistDef<String>("DemoHome.openScreen", parameter: "screen") { screen in
        let destinationTitle = ElementPredicate(label: .exact(screen), traits: [.header])
        let backToRoot = try DemoNavigation.backToRootIfNeeded()

        If {
            Case(.exists(.predicate(destinationTitle))) {
                WaitFor(.exists(.predicate(destinationTitle)))
            }
            Else {
                backToRoot

                Activate(.predicate(ElementPredicate(label: .exact(screen), traits: [.button])))
                    .expect(.screenChanged, timeout: 8)
                WaitFor(.exists(.predicate(destinationTitle)), timeout: 8)
            }
        }
    }
}

package enum ControlsDemoScreen {
    package static let openScreen = HeistDef<String>("ControlsDemo.openScreen", parameter: "screen") { screen in
        Activate(.predicate(ElementPredicate(label: .exact(screen), traits: [.button])))
            .expect(.screenChanged, timeout: 8)
        WaitFor(.exists(.label(screen)), timeout: 8)
    }
}

package enum TextInputScreen {
    private static let nameField = AccessibilityTarget.element(.value("Name"), traits: [.textEntry])
    private static let emailField = AccessibilityTarget.element(.value("Email"), traits: [.textEntry])

    package static let fillProfile = HeistDef<String>("TextInputScreen.fillProfile", parameter: "name") { name in
        TypeText(name, into: nameField)
            .expect(.exists(.value(name)), timeout: 4)

        dismissKeyboard()
            .withoutExpectation("Ends the first field edit before focusing the email field")

        TypeText("dogfood@example.com", into: emailField)
            .expect(.exists(.value("dogfood@example.com")), timeout: 4)

        dismissKeyboard()
            .withoutExpectation("Keyboard dismissal only prepares navigation")
    }

}

package enum TodoScreen {
    package static let completeItem = HeistDef<String>("TodoScreen.completeItem", parameter: "item") { item in
        let completedItem = ElementPredicate(
            label: .exact(item),
            value: .exact("Completed")
        )
        let visibleItem = ElementPredicate(label: .exact(item))

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
            .expect(.exists(.label("0")))

        Activate(.element(.label("7"), .traits([.button])))
            .expect(.exists(.label("7")))

        Activate(.element(.label("+"), .traits([.button])))
            .expect(.elementsChanged)

        Activate(.element(.label("5"), .traits([.button])))
            .expect(.exists(.label("5")))

        Activate(.element(.label("equals"), .traits([.button])))
            .expect(.exists(.label("12")))
    }
}

package enum AlertsSheetScreen {
    package static let presentAndDismiss = HeistDef<Void>("AlertsSheetScreen.presentAndDismiss") {
        oneFingerTap(.label("Show Sheet"))
            .expect(.exists(.label("Sheet Content")), timeout: 8)

        Activate(.label("Dismiss"))
            .expect(.exists(.label("Last action: Sheet dismissed")), timeout: 8)

        WaitFor(.missing(.label("Sheet Content")), timeout: 8)
    }
}

package enum TransientFlowScreen {
    package static let lifecycle = AccessibilityPredicate.elementsChanged([
        .appeared(.label("Processing")),
        .disappeared(.label("Submit")),
    ])
    package static let announcement = AccessibilityPredicate.notification("Ticket saved.")
    package static let exactToastText = AccessibilityPredicate.exists(.label("Ticket saved."))
}

#endif // canImport(UIKit)
