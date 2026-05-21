import Foundation

import TheScore

public extension ServerError {
    var errorCode: String {
        kind.errorCode
    }

    var phase: FailurePhase {
        kind.phase
    }

    var retryable: Bool {
        kind.retryable
    }

    var hint: String? {
        if kind == .authFailure {
            return FenceError.authFailureRecoveryHint(for: message)
        }
        return kind.hint
    }
}

private extension ErrorKind {
    var errorCode: String {
        switch self {
        case .elementNotFound:
            return "request.element_not_found"
        case .timeout:
            return "request.timeout"
        case .unsupported:
            return "request.unsupported"
        case .inputError:
            return "request.input_error"
        case .validationError:
            return "request.validation_error"
        case .actionFailed:
            return "request.action_failed"
        case .authFailure:
            return "auth.failed"
        case .authApprovalPending:
            return "auth.approval_pending"
        case .recording:
            return "recording.failed"
        case .general:
            return "server.general"
        }
    }

    var phase: FailurePhase {
        switch self {
        case .elementNotFound, .timeout, .unsupported, .inputError,
             .validationError, .actionFailed:
            return .request
        case .authFailure, .authApprovalPending:
            return .authentication
        case .recording:
            return .recording
        case .general:
            return .server
        }
    }

    var retryable: Bool {
        switch self {
        case .timeout:
            return true
        case .authApprovalPending:
            return true
        case .elementNotFound, .unsupported, .inputError, .validationError,
             .actionFailed, .authFailure, .recording, .general:
            return false
        }
    }

    var hint: String? {
        switch self {
        case .elementNotFound:
            return "Refresh the interface and verify the target's accessibility properties."
        case .timeout:
            return "The request timed out; retry on the same session if the app is responsive."
        case .unsupported:
            return "Use a supported command or target for this element."
        case .inputError:
            return "Fix the request input before retrying."
        case .validationError:
            return "Fix the request so it satisfies the server-side validation rules."
        case .actionFailed:
            return nil
        case .authFailure:
            return nil
        case .authApprovalPending:
            return "Waiting for approval on the device. Tap Allow on the iOS device to continue."
        case .recording:
            return "Stop any in-progress recording and retry after resolving the recording error."
        case .general:
            return nil
        }
    }
}
