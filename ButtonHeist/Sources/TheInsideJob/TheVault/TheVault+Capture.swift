#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

enum InventoryEnumeration {
    enum ReportedCount: Equatable {
        case known(Int)
        case unknown

        init(_ rawValue: Int) {
            if rawValue == NSNotFound || rawValue < 0 {
                self = .unknown
            } else {
                self = .known(rawValue)
            }
        }

        var value: Int? {
            guard case .known(let count) = self else { return nil }
            return count
        }
    }

    struct Result {
        let reportedCountsByContainerPath: [TreePath: ReportedCount]
        let attemptedIndicesByContainerPath: [TreePath: [Int]]
        let offscreenElements: [TheVault.OffscreenScrollElement]
        let knownUnattemptedCount: Int

        init(
            reportedCountsByContainerPath: [TreePath: ReportedCount] = [:],
            attemptedIndicesByContainerPath: [TreePath: [Int]] = [:],
            offscreenElements: [TheVault.OffscreenScrollElement] = [],
            knownUnattemptedCount: Int = 0
        ) {
            self.reportedCountsByContainerPath = reportedCountsByContainerPath
            self.attemptedIndicesByContainerPath = attemptedIndicesByContainerPath
            self.offscreenElements = offscreenElements
            self.knownUnattemptedCount = knownUnattemptedCount
        }

        var attemptedCount: Int {
            attemptedIndicesByContainerPath.values.reduce(0) { $0 + $1.count }
        }
    }

    enum RequestDecision {
        case admitted
        case exhausted
    }

    struct RequestAdmission {
        private(set) var remainingRequests: Int

        init(budget: Int) {
            remainingRequests = max(0, budget)
        }

        mutating func admit() -> RequestDecision {
            guard remainingRequests > 0 else { return .exhausted }
            remainingRequests -= 1
            return .admitted
        }
    }
}

extension TheVault {
    struct OffscreenScrollElement {
        let path: TreePath
        let scrollContainerPath: TreePath
        let scrollIndex: Int
        let element: AccessibilityElement
        let observedScrollContentActivationPoint: InterfaceTree.ObservedScrollContentActivationPoint?
    }

    /// Capture-local UIKit evidence before identity assignment and durable projection.
    struct CaptureResult {
        let hierarchy: [AccessibilityHierarchy]
        let objectsByPath: [TreePath: NSObject]
        let containerObjectsByPath: [TreePath: NSObject]
        let scrollViewsByPath: [TreePath: UIScrollView]
        let screenCoordinateOffsetsByPath: [TreePath: CGPoint]
        let inventoryEnumeration: InventoryEnumeration.Result

        var offscreenScrollElements: [OffscreenScrollElement] {
            inventoryEnumeration.offscreenElements
        }

        init(
            hierarchy: [AccessibilityHierarchy],
            objectsByPath: [TreePath: NSObject] = [:],
            containerObjectsByPath: [TreePath: NSObject] = [:],
            scrollViewsByPath: [TreePath: UIScrollView] = [:],
            screenCoordinateOffsetsByPath: [TreePath: CGPoint] = [:],
            offscreenScrollElements: [OffscreenScrollElement] = []
        ) {
            self.hierarchy = hierarchy
            self.objectsByPath = objectsByPath
            self.containerObjectsByPath = containerObjectsByPath
            self.scrollViewsByPath = scrollViewsByPath
            self.screenCoordinateOffsetsByPath = screenCoordinateOffsetsByPath
            inventoryEnumeration = InventoryEnumeration.Result(
                offscreenElements: offscreenScrollElements
            )
        }

        init(
            hierarchy: [AccessibilityHierarchy],
            objectsByPath: [TreePath: NSObject] = [:],
            containerObjectsByPath: [TreePath: NSObject] = [:],
            scrollViewsByPath: [TreePath: UIScrollView] = [:],
            screenCoordinateOffsetsByPath: [TreePath: CGPoint] = [:],
            inventoryEnumeration: InventoryEnumeration.Result
        ) {
            self.hierarchy = hierarchy
            self.objectsByPath = objectsByPath
            self.containerObjectsByPath = containerObjectsByPath
            self.scrollViewsByPath = scrollViewsByPath
            self.screenCoordinateOffsetsByPath = screenCoordinateOffsetsByPath
            self.inventoryEnumeration = inventoryEnumeration
        }
    }

    private static let offscreenScrollInventoryPathIndexBase = 1_000_000

    // MARK: - Parse (read-only)

    /// Read the live accessibility tree without mutating any state.
    /// Returns capture-local evidence or nil if no accessible windows exist.
    func capture() -> CaptureResult? {
        let windows = tripwire.captureAccessibleWindows()
        guard !windows.isEmpty else {
            insideJobLogger.debug("TheVault.capture(): no accessible windows - returning nil")
            return nil
        }

        // Parse runs on the main thread (UIKit accessibility SPI). Long parses
        // here are the main culprit when the main actor stalls during a UIKit
        // transition, so log durations to make the cost visible. Slow parses
        // (>= 100ms) get info-level so they show up without enabling debug logs.
        let parseStart = CFAbsoluteTimeGetCurrent()
        defer {
            let parseMs = Int((CFAbsoluteTimeGetCurrent() - parseStart) * 1000)
            if parseMs >= 100 {
                insideJobLogger.info("TheVault.capture(): \(parseMs)ms (\(windows.count) window(s))")
            } else {
                insideJobLogger.debug("TheVault.capture(): \(parseMs)ms (\(windows.count) window(s))")
            }
        }

        var allHierarchy: [AccessibilityHierarchy] = []
        var objectsByPath: [TreePath: NSObject] = [:]
        var containerObjectsByPath: [TreePath: NSObject] = [:]
        var scrollViewsByPath: [TreePath: UIScrollView] = [:]
        var screenCoordinateOffsetsByPath: [TreePath: CGPoint] = [:]

        let isMultiWindow = windows.count > 1

        for entry in windows {
            let window = entry.window
            let rootView = entry.rootView
            let containsModalBoundary = autoreleasepool { () -> Bool in
                let captured = hierarchyParser.parseAccessibilityHierarchy(
                    in: rootView,
                    rotorResultLimit: 0,
                    makeElement: { element, traversalIndex, source in
                        CaptureNode.element(element, traversalIndex: traversalIndex, source: source)
                    },
                    makeContainer: { container, children, source in
                        CaptureNode.container(container, children: children, source: source)
                    }
                )

                let windowHierarchy = captured.map(\.hierarchy)

                // Collect live pointers at paths relative to their final position in
                // `allHierarchy`. In multi-window mode each window is wrapped in a synthetic
                // semantic-group container, so the window's roots sit one level deeper; that
                // wrapper carries no live source and is intentionally not collected.
                let rootPathPrefix: (Int) -> TreePath
                if isMultiWindow {
                    let wrapperIndex = allHierarchy.count
                    let windowName = NSStringFromClass(type(of: window))
                    let wrapper = AccessibilityContainer(
                        type: .semanticGroup(
                            label: windowName,
                            value: "windowLevel: \(window.windowLevel.rawValue)"
                        ),
                        frame: AccessibilityRect(window.frame)
                    )
                    allHierarchy.append(.container(wrapper, children: windowHierarchy))
                    rootPathPrefix = { localIndex in TreePath([wrapperIndex, localIndex]) }
                } else {
                    let offset = allHierarchy.count
                    allHierarchy.append(contentsOf: windowHierarchy)
                    rootPathPrefix = { localIndex in TreePath([offset + localIndex]) }
                }

                for (localIndex, root) in captured.enumerated() {
                    let rootPath = rootPathPrefix(localIndex)
                    screenCoordinateOffsetsByPath[rootPath] = rootView.convert(.zero, to: nil)
                    Self.collect(
                        root,
                        at: rootPath,
                        objectsByPath: &objectsByPath,
                        containerObjectsByPath: &containerObjectsByPath,
                        scrollViewsByPath: &scrollViewsByPath
                    )
                }

                return captured.contains { $0.containsModalBoundary }
            }

            if containsModalBoundary {
                break
            }
        }

        let canonicalScrollViewsByPath = Self.canonicalScrollViewsByPath(
            from: scrollViewsByPath,
            containerObjectsByPath: containerObjectsByPath
        )
        let inventoryEnumeration = enumerateOffscreenScrollInventory(
            objectsByPath: objectsByPath,
            scrollViewsByPath: canonicalScrollViewsByPath
        )

        return CaptureResult(
            hierarchy: allHierarchy,
            objectsByPath: objectsByPath,
            containerObjectsByPath: containerObjectsByPath,
            scrollViewsByPath: canonicalScrollViewsByPath,
            screenCoordinateOffsetsByPath: screenCoordinateOffsetsByPath,
            inventoryEnumeration: inventoryEnumeration
        )
    }

    func enumerateOffscreenScrollInventory(
        objectsByPath: [TreePath: NSObject],
        scrollViewsByPath: [TreePath: UIScrollView],
        budget: Int = ButtonHeistRuntimeKnobs.current.visibleElementBudget
    ) -> InventoryEnumeration.Result {
        let admittedInventories = scrollViewsByPath
            .sorted(by: { $0.key < $1.key })
            .compactMap { path, scrollView -> (TreePath, UIScrollView, InventoryEnumeration.ReportedCount)? in
                guard Self.admitsOffscreenInventory(from: scrollView) else { return nil }
                return (path, scrollView, InventoryEnumeration.ReportedCount(scrollView.accessibilityElementCount()))
            }
        let reportedCountsByContainerPath = Dictionary(
            uniqueKeysWithValues: admittedInventories.map { ($0.0, $0.2) }
        )
        var representedObjectIDs = Set(objectsByPath.values.map(ObjectIdentifier.init))
        var elements: [OffscreenScrollElement] = []
        var attemptedIndicesByContainerPath: [TreePath: [Int]] = [:]
        var requestAdmission = InventoryEnumeration.RequestAdmission(budget: budget)
        var knownUnattemptedCount = 0

        for (containerPath, scrollView, reportedCount) in admittedInventories {
            guard let count = reportedCount.value, count > 0 else { continue }

            for index in 0..<count {
                guard case .admitted = requestAdmission.admit() else {
                    knownUnattemptedCount = Self.saturatingSum(
                        knownUnattemptedCount,
                        count - index
                    )
                    break
                }
                attemptedIndicesByContainerPath[containerPath, default: []].append(index)

                guard let object = scrollView.accessibilityElement(at: index) as? NSObject,
                      representedObjectIDs.insert(ObjectIdentifier(object)).inserted
                else { continue }

                guard let element = captureObject(object)?.withVisibility(.offscreen) else { continue }
                elements.append(OffscreenScrollElement(
                    path: containerPath.appending(Self.offscreenScrollInventoryPathIndexBase + index),
                    scrollContainerPath: containerPath,
                    scrollIndex: index,
                    element: element,
                    observedScrollContentActivationPoint: observedScrollContentActivationPoint(
                        for: element,
                        in: scrollView
                    )
                ))
            }
        }

        let result = InventoryEnumeration.Result(
            reportedCountsByContainerPath: reportedCountsByContainerPath,
            attemptedIndicesByContainerPath: attemptedIndicesByContainerPath,
            offscreenElements: elements,
            knownUnattemptedCount: knownUnattemptedCount
        )
        logBoundedInventoryEnumeration(result, budget: max(0, budget))
        return result
    }

    private static func admitsOffscreenInventory(from scrollView: UIScrollView) -> Bool {
        !(scrollView is UITableView) && !(scrollView is UICollectionView)
    }

    private static func saturatingSum(_ lhs: Int, _ rhs: Int) -> Int {
        let (sum, overflow) = lhs.addingReportingOverflow(rhs)
        return overflow ? Int.max : sum
    }

    private func logBoundedInventoryEnumeration(
        _ result: InventoryEnumeration.Result,
        budget: Int
    ) {
        guard result.knownUnattemptedCount > 0 else { return }
        insideJobLogger.warning(
            """
            Bounded offscreen accessibility inventory at budget \(budget, privacy: .public): \
            attempted \(result.attemptedCount, privacy: .public) request(s), \
            omitted \(result.knownUnattemptedCount, privacy: .public) known request(s).
            """
        )
    }

    private func observedScrollContentActivationPoint(
        for element: AccessibilityElement,
        in scrollView: UIScrollView
    ) -> InterfaceTree.ObservedScrollContentActivationPoint? {
        let activationPoint = element.bhResolvedActivationPoint
        guard activationPoint.x.isFinite, activationPoint.y.isFinite else { return nil }
        return InterfaceTree.ObservedScrollContentActivationPoint(
            scrollView.convert(activationPoint, from: nil)
        )
    }

    private static func canonicalScrollViewsByPath(
        from scrollViewsByPath: [TreePath: UIScrollView],
        containerObjectsByPath: [TreePath: NSObject]
    ) -> [TreePath: UIScrollView] {
        let directlyOwnedScrollViews = Set(scrollViewsByPath.compactMap { path, scrollView in
            containerObjectsByPath[path] === scrollView ? ObjectIdentifier(scrollView) : nil
        })
        return scrollViewsByPath.filter { path, scrollView in
            !directlyOwnedScrollViews.contains(ObjectIdentifier(scrollView))
                || containerObjectsByPath[path] === scrollView
        }
    }

    /// Parse one live accessibility object by pumping it through the regular
    /// hierarchy parser with a temporary accessibility root. The object may be
    /// a custom rotor result that VoiceOver can focus even though it is not
    /// discoverable by walking the current app hierarchy.
    func captureObject(_ object: NSObject) -> AccessibilityElement? {
        let root = SingleElementParsingRoot(object: object)
        let captured = hierarchyParser.parseAccessibilityHierarchy(
            in: root,
            rotorResultLimit: 0,
            makeElement: { element, traversalIndex, source in
                CaptureNode.element(element, traversalIndex: traversalIndex, source: source)
            },
            makeContainer: { container, children, source in
                CaptureNode.container(container, children: children, source: source)
            }
        )
        if let match = captured.lazy.compactMap({ $0.firstElement(matchingSource: object) }).first {
            return match
        }
        return captured.map(\.hierarchy).sortedElements.first
    }

    /// Records the live source object for each element and container in a captured subtree, keyed
    /// by its `TreePath`. The path is assigned structurally during the descent, so duplicate
    /// element/container values at different positions never collide — there is no candidate
    /// reconciliation as there was with the visitor side channel.
    private static func collect(
        _ node: CaptureNode,
        at path: TreePath,
        objectsByPath: inout [TreePath: NSObject],
        containerObjectsByPath: inout [TreePath: NSObject],
        scrollViewsByPath: inout [TreePath: UIScrollView]
    ) {
        switch node {
        case let .element(_, _, source):
            objectsByPath[path] = source

        case let .container(container, children, source):
            containerObjectsByPath[path] = source
            if let scrollView = scrollDispatchView(for: container, source: source) {
                scrollViewsByPath[path] = scrollView
            }
            for (index, child) in children.enumerated() {
                collect(
                    child,
                    at: path.appending(index),
                    objectsByPath: &objectsByPath,
                    containerObjectsByPath: &containerObjectsByPath,
                    scrollViewsByPath: &scrollViewsByPath
                )
            }
        }
    }

    private static func scrollDispatchView(
        for container: AccessibilityContainer,
        source: NSObject
    ) -> UIScrollView? {
        guard let contentSize = container.scrollableContentSize,
              let sourceView = source as? UIView
        else { return nil }
        if let scrollView = sourceView as? UIScrollView {
            return scrollView
        }

        let expectedContentSize = contentSize.cgSize
        let candidates = ScrollViewHierarchySearch.descendantScrollViews(in: sourceView)
            .filter(\.isScrollEnabled)
        let contentSizeMatches = candidates.filter {
            ScrollViewHierarchySearch.contentSize($0.contentSize, matches: expectedContentSize)
        }
        if contentSizeMatches.count == 1 {
            return contentSizeMatches[0]
        }
        return candidates.count == 1 ? candidates[0] : nil
    }

}

private final class SingleElementParsingRoot: UIView {
    private let elementObject: NSObject

    init(object: NSObject) {
        self.elementObject = object
        super.init(frame: ScreenMetrics.current.bounds)
        isAccessibilityElement = false
        accessibilityElements = [elementObject]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

private extension AccessibilityElement {
    func withVisibility(_ visibility: AccessibilityVisibility) -> AccessibilityElement {
        AccessibilityElement(
            description: description,
            label: label,
            value: value,
            traits: traits,
            identifier: identifier,
            hint: hint,
            userInputLabels: userInputLabels,
            shape: shape,
            activationPoint: activationPoint,
            usesDefaultActivationPoint: usesDefaultActivationPoint,
            customActions: customActions,
            customContent: customContent,
            customRotors: customRotors,
            accessibilityLanguage: accessibilityLanguage,
            respondsToUserInteraction: respondsToUserInteraction,
            visibility: visibility
        )
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
