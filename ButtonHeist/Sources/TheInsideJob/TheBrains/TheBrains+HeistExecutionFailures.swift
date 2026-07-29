#if canImport(UIKit)
#if DEBUG
import TheScore

extension TheBrains {
    internal func childFailureDetail(
        category: HeistFailureCategory,
        childPath: HeistExecutionPath
    ) -> HeistFailureDetail {
        HeistFailureDetail(
            category: category,
            contract: "child execution completes without failure",
            observed: "child failed at \(childPath)",
            expected: "all executed child steps pass"
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
