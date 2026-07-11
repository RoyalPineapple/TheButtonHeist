#if canImport(UIKit)
#if DEBUG

import TheScore

enum AccessibilityObservationFallbackLog {
    enum Source: String, Sendable {
        case settledObservation = "settled-observation"
        case postAction = "post-action"
    }

    private static let logger = ButtonHeistLog.logger(.insideJob(.accessibility))

    static func record(
        _ reason: AccessibilityObservationFallbackReason,
        source: Source
    ) {
        logger.info(
            "Accessibility observation used heuristic fallback: reason=\(reason.rawValue, privacy: .public) source=\(source.rawValue, privacy: .public)"
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
