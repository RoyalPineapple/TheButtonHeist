import Foundation
import os.log

import TheScore

private let playbackDiagnosticsLogger = Logger(subsystem: "com.buttonheist.fence", category: "playback")

@ButtonHeistActor
extension TheFence {
    func captureInterfaceSnapshot() async throws -> Interface {
        let parsed = try parseRequest(
            command: .getInterface,
            arguments: CommandArgumentEnvelope(values: [:])
        )
        let response = try await execute(parsed: parsed)
        guard case .interface(let snapshot, _) = response else {
            throw FenceError.invalidRequest("Expected get_interface response while capturing playback diagnostics")
        }
        return snapshot
    }
}

@ButtonHeistActor
extension PlaybackFailure {
    func withPlaybackDiagnostics(capturingWith fence: TheFence) async -> PlaybackFailure {
        do {
            let interface = try await fence.captureInterfaceSnapshot()
            return withInterface(interface)
        } catch let fenceError as FenceError {
            if case .invalidRequest = fenceError {
                return withDiagnosticCaptureFailure(fenceError.displayMessage)
            }
            playbackDiagnosticsLogger.error(
                "Failed to capture interface for playback diagnostics: \(fenceError.displayMessage)"
            )
            return withDiagnosticCaptureFailure(fenceError.displayMessage)
        } catch {
            playbackDiagnosticsLogger.error("Failed to capture interface for playback diagnostics: \(error.displayMessage)")
            return withDiagnosticCaptureFailure(error.displayMessage)
        }
    }
}
