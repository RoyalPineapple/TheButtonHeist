import ThePlans

// MARK: - Endpoint Trace Facts
//
// Captures are the durable source of truth; these are derived facts callers
// read for action receipts, expectations, and formatting.

public extension AccessibilityTrace {
    /// The compact delta between this trace's first and final capture.
    var endpointDelta: AccessibilityTrace.Delta? {
        guard captures.count >= 2,
              let first = captures.first,
              let last = captures.last
        else { return nil }
        return .between(first, last)
    }

    /// The endpoint delta with silent no-change edges dropped.
    ///
    /// Silent no-change edges are omitted because they do not carry useful
    /// background evidence. Transient-bearing no-change edges are preserved.
    var meaningfulEndpointDelta: AccessibilityTrace.Delta? {
        guard let delta = endpointDelta else { return nil }
        return Self.meaningfulEndpointDelta(delta)
    }

    /// Build one combined endpoint trace from per-step action traces.
    ///
    /// Adjacent duplicate captures are collapsed so a batch `[A->B, B->C]`
    /// becomes `[A, B, C]`. Parent links are normalized by
    /// `AccessibilityTrace(captures:)`; capture hashes still describe the
    /// captured interface/context content.
    static func endpointTrace(from traces: [AccessibilityTrace]) -> AccessibilityTrace? {
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

    var endpointScreenName: String? {
        captures.last?.screenName
    }

    var endpointScreenId: String? {
        captures.last?.screenId
    }

    private static func meaningfulEndpointDelta(
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
    var screenName: String? {
        InterfaceSummary.screenTitle(for: interface)
    }

    var screenId: String? {
        context.screenId ?? InterfaceSummary.screenId(for: interface)
    }
}
