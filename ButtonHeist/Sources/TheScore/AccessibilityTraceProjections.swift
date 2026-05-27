import Foundation

public struct ValidatedAccessibilityTrace: Sendable, Equatable {
    public let trace: AccessibilityTrace
    public let captures: [AccessibilityTrace.Capture]
    public let receipts: [AccessibilityTrace.Receipt]

    public init(trace: AccessibilityTrace) throws {
        let issues = trace.integrityIssues
        guard issues.isEmpty else {
            throw AccessibilityTraceValidationError.integrityIssues(issues)
        }
        self.trace = trace
        self.captures = trace.captures
        self.receipts = trace.receipts
    }
}

public enum AccessibilityTraceValidationError: Error, Sendable, Equatable, CustomStringConvertible {
    case integrityIssues([AccessibilityTrace.IntegrityIssue])

    public var description: String {
        switch self {
        case .integrityIssues(let issues):
            return "accessibility trace integrity failed with \(issues.count) issue(s)"
        }
    }
}

extension AccessibilityTrace {
    public func validated() throws -> ValidatedAccessibilityTrace {
        try ValidatedAccessibilityTrace(trace: self)
    }

    var captureEndpointScreenName: String? {
        captures.last?.screenNameProjection
    }

    var captureEndpointScreenId: String? {
        captures.last?.screenIdProjection
    }
}

extension AccessibilityTrace.Capture {
    var screenNameProjection: String? {
        interface.elements
            .first(where: { $0.traits.contains(.header) })
            .flatMap(\.label)
    }

    var screenIdProjection: String? {
        context.screenId ?? interface.screenId
    }
}
