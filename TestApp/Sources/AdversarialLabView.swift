import SwiftUI

enum AdversarialScenario: String, CaseIterable, Identifiable {
    case asyncReveal = "/async-reveal"
    case offscreenCheckout = "/offscreen-checkout"
    case duplicateLabels = "/duplicate-labels"
    case dynamicCells = "/dynamic-cells"
    case textFieldFallback = "/text-field-fallback"
    case staleLiveObject = "/stale-live-object"
    case modalObstruction = "/modal-obstruction"
    case nestedScroll = "/nested-scroll"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .asyncReveal: "Async Reveal"
        case .offscreenCheckout: "Offscreen Checkout"
        case .duplicateLabels: "Duplicate Labels"
        case .dynamicCells: "Dynamic Cells"
        case .textFieldFallback: "Text Field Fallback"
        case .staleLiveObject: "Stale Live Object"
        case .modalObstruction: "Modal Obstruction"
        case .nestedScroll: "Nested Scroll"
        }
    }
}

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
