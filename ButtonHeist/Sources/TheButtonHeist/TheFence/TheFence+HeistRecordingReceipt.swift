import os.log
import TheScore

private let heistRecordingLogger = Logger(subsystem: "com.buttonheist.fence", category: "heist")

extension TheFence {
    func recordHeistStep(
        _ request: ParsedRequest,
        dispatchedResponse: FenceResponse,
        validatedResponse: FenceResponse
    ) {
        guard playback.isIdle else { return }
        guard heistStore.isRecordingHeist else { return }

        let effect: HeistRecordingEffect
        do {
            effect = try HeistRecordingComposition(
                request: request,
                dispatchedResponse: dispatchedResponse,
                validatedResponse: validatedResponse
            ).effect()
        } catch {
            heistRecordingLogger.error(
                "Skipped heist step for \(request.command.rawValue): composition failed: \(String(describing: error))"
            )
            return
        }

        do {
            try heistStore.applyRecordingEffect(effect)
        } catch {
            heistRecordingLogger.error(
                "Failed to encode heist step for \(request.command.rawValue): \(error.localizedDescription)"
            )
        }
    }
}
