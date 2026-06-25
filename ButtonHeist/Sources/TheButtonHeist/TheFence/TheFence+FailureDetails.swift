import Foundation

import TheScore

struct ServerFailureDescriptor: Sendable {
    let errorCode: String
    let phase: FailurePhase
    let retryable: Bool
    let hint: String?
}

public extension ServerError {
    internal var failureDescriptor: ServerFailureDescriptor {
        kind.failureDescriptor
    }

    var errorCode: String {
        failureDescriptor.errorCode
    }

    var phase: FailurePhase {
        failureDescriptor.phase
    }

    var retryable: Bool {
        failureDescriptor.retryable
    }

    var hint: String? {
        failureDescriptor.hint
    }
}

private extension ErrorKind {
    var failureDescriptor: ServerFailureDescriptor {
        switch self {
        case .elementNotFound:
            return ServerFailureDescriptor(
                errorCode: "request.element_not_found",
                phase: .request,
                retryable: false,
                hint: "Refresh the interface and verify the target's accessibility properties."
            )
        case .timeout:
            return ServerFailureDescriptor(
                errorCode: "request.timeout",
                phase: .request,
                retryable: true,
                hint: "The request timed out; retry on the same session if the app is responsive."
            )
        case .validationError:
            return ServerFailureDescriptor(
                errorCode: "request.validation_error",
                phase: .request,
                retryable: false,
                hint: "Fix the request so it satisfies the server-side validation rules."
            )
        case .actionFailed:
            return ServerFailureDescriptor(
                errorCode: "request.action_failed",
                phase: .request,
                retryable: false,
                hint: nil
            )
        case .authFailure:
            return ServerFailureDescriptor(
                errorCode: "auth.failed",
                phase: .authentication,
                retryable: false,
                hint: nil
            )
        case .general:
            return ServerFailureDescriptor(
                errorCode: "server.general",
                phase: .server,
                retryable: false,
                hint: nil
            )
        }
    }
}
