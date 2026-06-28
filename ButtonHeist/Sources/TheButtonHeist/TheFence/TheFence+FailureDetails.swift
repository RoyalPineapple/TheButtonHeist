import Foundation

import TheScore

struct ServerFailureDescriptor: Sendable {
    let details: FailureDetails

    var errorCode: String { details.errorCode }
    var phase: FailurePhase { details.phase }
    var retryable: Bool { details.retryable }
    var hint: String? { details.hint }
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

extension ErrorKind {
    var failureDetails: FailureDetails {
        failureDescriptor.details
    }

    var failureDescriptor: ServerFailureDescriptor {
        switch self {
        case .accessibilityTreeUnavailable:
            return ServerFailureDescriptor(
                details: FailureDetails(code: .requestAccessibilityTreeUnavailable)
            )
        case .elementNotFound:
            return ServerFailureDescriptor(
                details: FailureDetails(code: .requestElementNotFound)
            )
        case .timeout:
            return ServerFailureDescriptor(
                details: FailureDetails(
                    code: .requestTimeout,
                    hint: "The request timed out; retry on the same session if the app is responsive."
                )
            )
        case .validationError:
            return ServerFailureDescriptor(
                details: FailureDetails(code: .requestValidationError)
            )
        case .actionFailed:
            return ServerFailureDescriptor(
                details: FailureDetails(code: .requestActionFailed)
            )
        case .authFailure:
            return ServerFailureDescriptor(
                details: FailureDetails(code: .authFailed)
            )
        case .general:
            return ServerFailureDescriptor(
                details: FailureDetails(code: .serverGeneral)
            )
        }
    }
}
