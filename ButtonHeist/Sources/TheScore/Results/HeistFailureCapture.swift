import ThePlans

/// Terminal screenshot evidence captured after heist execution has failed.
package enum HeistFailureCapture: Sendable, Equatable {
    case captured(ScreenPayload)
    case unavailable(kind: ActionFailure.Kind, message: String?)

    package var payload: ScreenPayload? {
        guard case .captured(let payload) = self else { return nil }
        return payload
    }

    package var message: String? {
        guard case .unavailable(_, let message) = self else { return nil }
        return message
    }
}
