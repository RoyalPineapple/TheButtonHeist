import Foundation

import TheScore

public extension ServerError {
    internal var failureDetails: FailureDetails {
        kind.failureDetails
    }

    var errorCode: String {
        failureDetails.errorCode
    }

    var phase: FailurePhase {
        failureDetails.phase
    }

    var retryable: Bool {
        failureDetails.retryable
    }

    var hint: String? {
        failureDetails.hint
    }
}

extension ErrorKind {
    var failureDetails: FailureDetails {
        switch self {
        case .accessibilityTreeUnavailable:
            return FailureDetails(code: .requestAccessibilityTreeUnavailable)
        case .elementNotFound:
            return FailureDetails(code: .requestElementNotFound)
        case .timeout:
            return FailureDetails(
                code: .requestTimeout,
                hint: "The request timed out; retry on the same session if the app is responsive."
            )
        case .validationError:
            return FailureDetails(code: .requestValidationError)
        case .actionFailed:
            return FailureDetails(code: .requestActionFailed)
        case .authFailure:
            return FailureDetails(code: .authFailed)
        case .general:
            return FailureDetails(code: .serverGeneral)
        }
    }
}
