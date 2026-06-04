import TheScore

/// Owns transient recording assembly for TheFence.
///
/// Composition decides what an interaction means for recording. This lifecycle
/// only keeps deferred setup while a recording is active and writes the exact
/// steps it is handed.
@ButtonHeistActor
final class FenceHeistRecordingLifecycle {
    private var deferredSetupSteps: [HeistStep] = []

    func begin() {
        deferredSetupSteps.removeAll()
    }

    func abandon() {
        deferredSetupSteps.removeAll()
    }

    func apply(_ effect: HeistRecordingEffect, to store: HeistStore) throws {
        switch effect {
        case .ignore:
            return
        case .discardDeferredSetup:
            deferredSetupSteps.removeAll()
        case .deferUntilFinish(let steps):
            deferredSetupSteps.append(contentsOf: steps)
        case .appendReplacingDeferredSetup(let steps):
            deferredSetupSteps.removeAll()
            try store.appendSteps(steps)
        case .appendAfterDeferredSetup(let steps):
            try flushDeferredSetup(to: store)
            try store.appendSteps(steps)
        }
    }

    func finish(using store: HeistStore) throws -> HeistPlan {
        defer { deferredSetupSteps.removeAll() }
        try flushDeferredSetup(to: store)
        return try store.finishRecording()
    }

    private func flushDeferredSetup(to store: HeistStore) throws {
        guard !deferredSetupSteps.isEmpty else { return }
        let steps = deferredSetupSteps
        deferredSetupSteps.removeAll()
        try store.appendSteps(steps)
    }
}
