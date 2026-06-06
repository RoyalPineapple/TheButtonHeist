import os.log
import TheScore

private let heistRecordingLogger = Logger(subsystem: "com.buttonheist.fence", category: "heist")

extension TheFence {
    /// Record the executed command as a durable heist step when recording is
    /// active. Driven by the one-step heist execution evidence — the action's
    /// own `ActionResult` and the server-evaluated `ExpectationResult` — not a
    /// reconstructed action response. `actionResult`/`expectation` are `nil`
    /// for non-action commands (the composition decides discard/ignore from the
    /// command alone before touching them).
    func recordHeistStep(
        _ request: ParsedRequest,
        actionResult: ActionResult?,
        expectation: ExpectationResult?
    ) {
        guard heistStore.isRecordingHeist else { return }

        let effect: HeistRecordingEffect
        do {
            effect = try HeistRecordingComposition(
                request: request,
                actionResult: actionResult,
                expectation: expectation
            ).effect()
        } catch {
            heistRecordingLogger.error(
                "Skipped heist step for \(request.command.rawValue): composition failed: \(String(describing: error))"
            )
            return
        }

        do {
            try heistRecording.apply(effect, to: heistStore)
        } catch {
            heistRecordingLogger.error(
                "Failed to encode heist step for \(request.command.rawValue): \(error.localizedDescription)"
            )
        }
    }
}
