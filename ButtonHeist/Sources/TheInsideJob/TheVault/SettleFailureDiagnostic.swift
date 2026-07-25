#if canImport(UIKit)
#if DEBUG

@MainActor enum SettleFailureDiagnostic {
    static func message(for settleResult: SettleSession.Result) -> String {
        var parts = ["settle \(settleResult.outcome.outcomeDescription)"]
        if let finalObservation = settleResult.finalObservation {
            parts.append("last parsed: \(finalObservation.tree.viewportCapture.hierarchy.sortedElements.count) elements")
        } else {
            parts.append("last parsed: no accessibility tree")
        }
        if let instability = settleResult.delta.changeDescription {
            parts.append(instability)
        }
        return parts.joined(separator: "; ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
