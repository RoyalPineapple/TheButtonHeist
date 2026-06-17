#if canImport(UIKit)
#if DEBUG

/// Latest parser evidence and failed-settle diagnostic evidence.
///
/// This is intentionally separate from `WorldStore`: latest observed evidence
/// can power visible/debug reads, but it is not semantic truth unless the
/// observation stream commits it.
struct ObservedState {
    private(set) var semanticWorld: SemanticScreen = .empty
    private(set) var failedSettleDiagnosticEvidence: Screen?

    mutating func record(_ screen: Screen) {
        semanticWorld = screen.semantic
    }

    mutating func recordFailedSettleDiagnosticEvidence(_ screen: Screen?) {
        failedSettleDiagnosticEvidence = screen
        if let screen {
            record(screen)
        }
    }

    mutating func clearFailedSettleDiagnosticEvidence() {
        failedSettleDiagnosticEvidence = nil
    }

    mutating func reset() {
        semanticWorld = .empty
        failedSettleDiagnosticEvidence = nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
