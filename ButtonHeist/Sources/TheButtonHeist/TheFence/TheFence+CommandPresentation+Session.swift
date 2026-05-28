import Foundation

extension TheFence.Command {
    static func sessionPresentationDescription(for toolName: String) -> String? {
        switch toolName {
        case Self.help.rawValue:
            return "Return descriptor-backed help for the current Button Heist command surface."

        case Self.quit.rawValue:
            return "End the interactive CLI session."

        case Self.startRecording.rawValue:
            return "Start an H.264/MP4 screen recording. Recording runs until max duration unless inactivity_timeout is explicitly supplied."

        case Self.stopRecording.rawValue:
            return """
                Stop an in-progress screen recording. Returns artifact path and metadata by default. \
                Set inlineData=true and/or includeInteractionLog=true for a capped expanded JSON response.
                """

        case Self.listDevices.rawValue:
            return """
                List iOS devices discovered via Bonjour plus named targets from .buttonheist.json. \
                Empty when Bonjour is blocked and no config targets exist — use connect(device:token:) directly.
                """

        case Self.getSessionState.rawValue:
            return """
                Inspect the current Button Heist session: connection status, device/app identity, \
                recording state, client timeouts, and a lightweight summary of the last action.
                """

        case Self.connect.rawValue:
            return """
                Establish or switch the active connection to an iOS app with Button Heist enabled. \
                Three patterns: target=NAME from .buttonheist.json, device=HOST:PORT + token, or \
                BUTTONHEIST_DEVICE/BUTTONHEIST_TOKEN env vars. Tears down any existing session first. \
                Returns session state; call get_interface explicitly to observe UI hierarchy.
                """

        case Self.listTargets.rawValue:
            return """
                List named connection targets from .buttonheist.json (or ~/.config/buttonheist/config.json), \
                including each target's address and which one is the default.
                """

        case Self.runBatch.rawValue:
            return """
                Execute multiple commands in one call. Each step is a JSON object with 'command' set \
                to a canonical TheFence.Command name plus that command's parameters. Attach 'expect' per step \
                to verify inline. Returns ordered per-step results. \
                policy=stop_on_error (default) or continue_on_error.
                """

        case Self.getSessionLog.rawValue:
            return "Return the current session log snapshot: commands executed and artifacts produced."

        case Self.archiveSession.rawValue:
            return "Close and compress the current session into a .tar.gz archive; returns the path."

        case Self.startHeist.rawValue:
            return """
                Start recording a heist. Successful commands become steps in a .heist file; \
                the recorder derives minimum matcher fields for durable element targeting; heistId remains recording evidence only. \
                Attach 'expect' to validate outcomes during playback.
                """

        case Self.stopHeist.rawValue:
            return """
                Stop recording and save the heist as a self-contained JSON playback script. \
                Returns the file path and step count. At least one step must have been recorded.
                """

        case Self.playHeist.rawValue:
            return """
                Play back a .heist file. Steps execute sequentially; playback stops on the first \
                failed step. On failure, returns full diagnostics: command, target, error, action \
                result, expectation result, and a complete interface snapshot at the failure point.
                """

        default:
            return nil
        }
    }
}
