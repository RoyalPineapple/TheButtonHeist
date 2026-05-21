import Foundation

extension FenceResponse {

    static func compactSessionState(_ payload: SessionStatePayload) -> String {
        switch payload.phase {
        case .connected:
            return "session: connected"
        case .connecting:
            return "session: connecting"
        case .failed:
            return compactSessionStateFailure(payload.lastFailure, label: "failed") ?? "session: failed"
        case .disconnected:
            return compactSessionStateFailure(payload.lastFailure, label: "disconnected") ?? "session: not connected"
        }
    }

    private static func compactSessionStateFailure(_ failure: SessionFailurePayload?, label: String) -> String? {
        guard let failure else { return nil }
        var text = "session: \(label)"
        text += " (\(failure.errorCode))"
        if let hint = failure.hint {
            text += ": \(hint)"
        } else if let message = failure.message {
            text += ": \(message)"
        }
        return text
    }

}
