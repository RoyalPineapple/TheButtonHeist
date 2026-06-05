import ThePlans
public extension AccessibilityTrace {
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
        InterfaceSummary.screenTitle(for: interface)
    }

    var screenIdProjection: String? {
        context.screenId ?? InterfaceSummary.screenId(for: interface)
    }
}
