#if canImport(UIKit)
#if DEBUG
import Foundation

import TheScore

enum FailureEvidencePolicy: Equatable, Sendable {
    case hierarchy
    case screenshot
    case accessibilitySnapshot

    var label: String {
        switch self {
        case .hierarchy:
            return "hierarchy"
        case .screenshot:
            return "screenshot"
        case .accessibilitySnapshot:
            return "accessibilitySnapshot"
        }
    }

    init?(rawValue: String) {
        switch rawValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "hierarchy":
            self = .hierarchy
        case "hierarchy+accessibilitysnapshot", "accessibility", "accessibilitysnapshot":
            self = .accessibilitySnapshot
        case "screenshot":
            self = .screenshot
        default:
            return nil
        }
    }

    var captureMode: ScreenCaptureMode? {
        switch self {
        case .hierarchy: nil
        case .screenshot: .raw
        case .accessibilitySnapshot: .accessibility
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
