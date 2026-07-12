import ThePlans

// MARK: - Combined Traces

public extension AccessibilityTrace {
    /// Build one combined trace from per-step action traces.
    ///
    /// Adjacent duplicate captures are collapsed so a batch `[A->B, B->C]`
    /// becomes `[A, B, C]`. Parent links are normalized by
    /// `AccessibilityTrace(captures:)`; capture hashes still describe the
    /// captured interface/context content.
    static func combinedTrace(from traces: [AccessibilityTrace]) -> AccessibilityTrace? {
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

}

extension AccessibilityTrace.Capture {
    var screenName: String? {
        InterfaceSummary.screenTitle(for: interface)
    }

    var screenId: String? {
        context.screenId ?? InterfaceSummary.screenId(for: interface)
    }
}
