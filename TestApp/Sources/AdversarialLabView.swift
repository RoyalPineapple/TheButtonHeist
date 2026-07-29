import SwiftUI
@_spi(AdversarialLab) import ThePlans

typealias AdversarialScenario = AdversarialScenarioCatalog.Route

struct AdversarialLabView: View {
    var body: some View {
        List(AdversarialScenario.allCases) { scenario in
            NavigationLink(scenario.title) {
                AdversarialScenarioView(scenario: scenario)
            }
        }
        .navigationTitle("Adversarial Lab")
    }
}

struct AdversarialScenarioView: View {
    let scenario: AdversarialScenario

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
        case .staleLiveObject:
            StaleLiveObjectScenarioView()
        case .modalObstruction:
            ModalObstructionScenarioView()
        case .nestedScroll:
            NestedScrollScenarioView()
        }
    }
}
