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

public extension AccessibilityTrace {
    func validated() throws -> ValidatedAccessibilityTrace {
        try ValidatedAccessibilityTrace(trace: self)
    }

    /// Raw compact projection between this trace's first and final capture.
    ///
    /// Captures remain the durable source of truth; this is the compact view
    /// callers use for action receipts, expectations, and formatting.
    var endpointDeltaProjection: AccessibilityTrace.Delta? {
        guard captures.count >= 2,
              let first = captures.first,
              let last = captures.last
        else { return nil }
        return .between(first, last)
    }

    /// Background/summary projection between this trace's endpoints.
    ///
    /// Silent no-change edges are omitted because they do not carry useful
    /// background evidence. Transient-bearing no-change edges are preserved.
    var meaningfulEndpointDeltaProjection: AccessibilityTrace.Delta? {
        guard let delta = endpointDeltaProjection else { return nil }
        return Self.meaningfulEndpointDeltaProjection(delta)
    }

    /// Build one source trace projection from per-step action traces.
    ///
    /// Adjacent duplicate captures are collapsed so a batch `[A->B, B->C]`
    /// becomes `[A, B, C]`. Parent links are normalized by
    /// `AccessibilityTrace(captures:)`; capture hashes still describe the
    /// captured interface/context content.
    static func endpointTraceProjection(from traces: [AccessibilityTrace]) -> AccessibilityTrace? {
        var captures: [AccessibilityTrace.Capture] = []
        for trace in traces {
            for capture in trace.captures {
                guard captures.last?.hash != capture.hash else { continue }
                captures.append(capture)
            }
        }
        guard captures.count >= 2 else { return nil }
        return AccessibilityTrace(captures: captures)
    }

    /// Raw compact projection across a set of per-step traces.
    static func endpointDeltaProjection(from traces: [AccessibilityTrace]) -> AccessibilityTrace.Delta? {
        endpointTraceProjection(from: traces)?.endpointDeltaProjection
    }

    /// Background/summary projection across a set of per-step traces.
    static func meaningfulEndpointDeltaProjection(from traces: [AccessibilityTrace]) -> AccessibilityTrace.Delta? {
        endpointTraceProjection(from: traces)?.meaningfulEndpointDeltaProjection
    }

    var endpointScreenNameProjection: String? {
        captures.last?.screenNameProjection
    }

    var endpointScreenIdProjection: String? {
        captures.last?.screenIdProjection
    }

    private static func meaningfulEndpointDeltaProjection(
        _ delta: AccessibilityTrace.Delta
    ) -> AccessibilityTrace.Delta? {
        switch delta {
        case .noChange(let payload) where payload.transient.isEmpty:
            return nil
        case .noChange, .elementsChanged, .screenChanged:
            return delta
        }
    }
}

extension AccessibilityTrace.Capture {
    var screenNameProjection: String? {
        InterfaceSummary.screenTitle(from: interface.elements)
    }

    var screenIdProjection: String? {
        context.screenId ?? InterfaceSummary.screenId(for: interface)
    }
}
