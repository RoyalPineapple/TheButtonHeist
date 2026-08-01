import SwiftUI
@_spi(AdversarialLab) import ThePlans

struct AdversarialLabView: View {
    var body: some View {
        List(AdversarialScenarioCatalog.Route.allCases) { scenario in
            NavigationLink(scenario.title) {
                AdversarialScenarioView(scenario: scenario)
            }
        }
        .navigationTitle("Adversarial Lab")
    }
}

struct AdversarialScenarioView: View {
    let scenario: AdversarialScenarioCatalog.Route

    var body: some View {
        switch scenario {
        case .asyncReveal:
            AsyncRevealScenarioView()
        case .offscreenCheckout:
            OffscreenCheckoutScenarioView()
        case .duplicateLabels:
            DuplicateLabelsScenarioView()
        case .dynamicCells:
            DynamicCellsScenarioView()
        case .textFieldFallback:
            TextFieldFallbackScenarioView()
        case .keyboardViewport:
            KeyboardViewportScenarioView()
        case .staleLiveObject:
            StaleLiveObjectScenarioView()
        case .modalObstruction:
            ModalObstructionScenarioView()
        case .nestedScroll:
            NestedScrollScenarioView()
        }
    }
}
