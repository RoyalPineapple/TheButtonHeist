import ThePlans

// MARK: - Combined Traces

public extension AccessibilityTrace {
    /// Build one combined trace from per-step action traces.
    ///
    /// Adjacent duplicate captures are collapsed so a batch `[A->B, B->C]`
    /// becomes a new canonical `[A, B, C]` trace whose identities are assigned
    /// by this source constructor.
    static func combinedTrace(from traces: [AccessibilityTrace]) -> AccessibilityTrace? {
        var captures: [Capture] = []
        for trace in traces {
            for source in trace.captures where captures.last?.hash != source.hash {
                captures.append(Capture(
                    sequence: captures.count + 1,
                    interface: source.interface,
                    parentHash: captures.last?.hash,
                    context: source.context,
                    transition: source.transition
                ))
            }
        }
        return captures.count >= 2 ? AccessibilityTrace(captures: captures) : nil
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
