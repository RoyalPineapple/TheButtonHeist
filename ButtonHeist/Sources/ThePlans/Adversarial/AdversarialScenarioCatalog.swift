/// Canonical fixture, plan, and outcome contracts for the BH Demo adversarial lab.
@_spi(AdversarialLab)
public enum AdversarialScenarioCatalog {
    public enum Route: String, CaseIterable, Identifiable, Sendable {
        case asyncReveal = "/async-reveal"
        case offscreenCheckout = "/offscreen-checkout"
        case duplicateLabels = "/duplicate-labels"
        case dynamicCells = "/dynamic-cells"
        case textFieldFallback = "/text-field-fallback"
        case staleLiveObject = "/stale-live-object"
        case modalObstruction = "/modal-obstruction"
        case nestedScroll = "/nested-scroll"

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .asyncReveal: "Async Reveal"
            case .offscreenCheckout: "Offscreen Checkout"
            case .duplicateLabels: "Duplicate Labels"
            case .dynamicCells: "Dynamic Cells"
            case .textFieldFallback: "Text Field Fallback"
            case .staleLiveObject: "Stale Live Object"
            case .modalObstruction: "Modal Obstruction"
            case .nestedScroll: "Nested Scroll"
            }
        }
    }

    public enum Classification: String, Codable, Sendable {
        case deterministic
        case statistical
    }

    public enum ExpectedOutcome: String, Codable, Sendable {
        case commandSucceeds = "command-succeeds"
        case commandFailsWithDiagnostic = "command-fails-with-diagnostic"
    }

    public struct Evidence: Codable, Equatable, Sendable {
        public enum Kind: String, Codable, Sendable {
            case diagnostic
            case element
            case notification
        }

        public let kind: Kind
        public let label: String
        public let value: String?

        public static func element(_ label: String, value: String? = nil) -> Self {
            Self(kind: .element, label: label, value: value)
        }

        public static func diagnostic(_ text: String) -> Self {
            Self(kind: .diagnostic, label: text, value: nil)
        }

        public static func notification(_ text: String) -> Self {
            Self(kind: .notification, label: text, value: nil)
        }
    }

    public struct Manifest: Codable, Equatable, Sendable {
        public let name: String
        public let route: String
        public let classification: Classification
        public let expectedOutcome: ExpectedOutcome
        public let expectedEvidence: [Evidence]
        public let plan: String
    }
}
