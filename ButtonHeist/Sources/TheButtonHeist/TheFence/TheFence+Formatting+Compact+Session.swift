import Foundation

extension FenceResponse {

    static func compactSessionState(_ payload: SessionStatePayload) -> String {
        switch payload.state {
        case .connected:
            return "session: connected"
        case .connecting:
            return "session: connecting"
        case .failed(let failure):
            return compactSessionStateFailure(failure, label: "failed") ?? "session: failed"
        case .disconnected(let lastFailure):
            return compactSessionStateFailure(lastFailure, label: "disconnected") ?? "session: not connected"
        }
    }

    private static func compactSessionStateFailure(_ failure: SessionFailurePayload?, label: String) -> String? {
        guard let failure else { return nil }
        var text = "session: \(label)"
        text += " (\(failure.code))"
        if let hint = failure.hint {
            text += ": \(hint)"
        } else if let message = failure.message {
            text += ": \(message)"
        }
        return text
    }

}
