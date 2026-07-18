#if canImport(UIKit)
#if DEBUG

@MainActor enum SettleFailureDiagnostic {
    static func message(
        for outcome: SettleSession.Result,
        layerGateWasClear: Bool? = nil
    ) -> String {
        var parts = ["settle \(outcome.outcome.outcomeDescription)"]
        if let finalObservation = outcome.finalObservation {
            parts.append("last parsed: \(finalObservation.tree.viewportCapture.hierarchy.sortedElements.count) elements")
        } else {
            parts.append("last parsed: no accessibility tree")
        }
        if let instability = outcome.instabilityDescription {
            parts.append(instability)
        }
        if layerGateWasClear == false {
            parts.append("layer motion still active while AX settle ran")
        }
        return parts.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
