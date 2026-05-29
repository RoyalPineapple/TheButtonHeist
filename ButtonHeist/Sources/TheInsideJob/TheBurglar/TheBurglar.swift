#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The crew member who breaks in and takes what he finds.
///
/// TheBurglar reads the live accessibility tree and assigns heistIds. Pure
/// helpers — he has no mutable state. TheStash invokes
/// him via `parse()` to obtain a `Screen` value, then commits or merges it on
/// its own schedule.
///
/// Intentionally module-internal so TheInsideJob unit tests can validate parse
/// behavior. Production call sites should always go through TheStash facades.
@MainActor
final class TheBurglar {

    private let parser = AccessibilityHierarchyParser()
    private let tripwire: TheTripwire

    init(tripwire: TheTripwire) {
        self.tripwire = tripwire
    }

    // MARK: - Parse Result (internal)

    /// Internal parse intermediate — raw output from the AccessibilitySnapshotParser
    /// walk before heistId assignment. Tests use it to inject pre-parsed data.
    /// The hierarchy is the source of element order; callers derive flat
    /// element lists from it instead of carrying a parallel array.
    struct ParseResult {
        let hierarchy: [AccessibilityHierarchy]
        let objects: [AccessibilityElement: NSObject]
        let objectsByPath: [TreePath: NSObject]
        let containerObjectsByPath: [TreePath: NSObject]
        let scrollViews: [AccessibilityContainer: UIView]
        let scrollViewsByPath: [TreePath: UIView]

        init(
            hierarchy: [AccessibilityHierarchy],
            objects: [AccessibilityElement: NSObject],
            objectsByPath: [TreePath: NSObject] = [:],
            containerObjectsByPath: [TreePath: NSObject] = [:],
            scrollViews: [AccessibilityContainer: UIView],
            scrollViewsByPath: [TreePath: UIView] = [:]
        ) {
            self.hierarchy = hierarchy
            self.objects = objects
            self.objectsByPath = objectsByPath
            self.containerObjectsByPath = containerObjectsByPath
            self.scrollViews = scrollViews
            self.scrollViewsByPath = scrollViewsByPath
        }
    }

    // MARK: - Parse (read-only)

    /// Read the live accessibility tree without mutating any state.
    /// Returns a ParseResult value or nil if no accessible windows exist.
    func parse() -> ParseResult? {
        let windows = tripwire.getAccessibleWindows()
        guard !windows.isEmpty else {
            insideJobLogger.debug("TheBurglar.parse(): no accessible windows — returning nil")
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
                insideJobLogger.info("TheBurglar.parse(): \(parseMs)ms (\(windows.count) window(s))")
            } else {
                insideJobLogger.debug("TheBurglar.parse(): \(parseMs)ms (\(windows.count) window(s))")
            }
        }

        var allHierarchy: [AccessibilityHierarchy] = []
        var allObjects: [AccessibilityElement: NSObject] = [:]
        var objectCandidates: [AccessibilityElement: [NSObject]] = [:]
        var containerObjectCandidates: [AccessibilityContainer: [NSObject]] = [:]
        var scrollViewCandidates: [AccessibilityContainer: [UIView]] = [:]

        for (window, rootView) in windows {
            let containsModalBoundary = autoreleasepool { () -> Bool in
                var containsModalBoundary = false
                let windowTree: [AccessibilityHierarchy] = parser.parseAccessibilityHierarchy(
                    in: rootView,
                    rotorResultLimit: 0,
                    makeElement: { element, traversalIndex, object in
                        allObjects[element] = object
                        objectCandidates[element, default: []].append(object)
                        return AccessibilityHierarchy.element(element, traversalIndex: traversalIndex)
                    },
                    makeContainer: { container, children, object in
                        containerObjectCandidates[container, default: []].append(object)
                        if case .scrollable = container.type, let view = object as? UIView {
                            scrollViewCandidates[container, default: []].append(view)
                        }
                        if container.isModalBoundary {
                            containsModalBoundary = true
                        }
                        return AccessibilityHierarchy.container(container, children: children)
                    }
                )

                if windows.count > 1 {
                    let windowName = NSStringFromClass(type(of: window))
                    let container = AccessibilityContainer(
                        type: .semanticGroup(
                            label: windowName,
                            value: "windowLevel: \(window.windowLevel.rawValue)",
                            identifier: nil
                        ),
                        frame: AccessibilityRect(window.frame)
                    )
                    allHierarchy.append(.container(container, children: windowTree))
                } else {
                    allHierarchy.append(contentsOf: windowTree)
                }

                return containsModalBoundary
            }

            if containsModalBoundary {
                break
            }
        }

        let allScrollViewsByPath = Self.scrollViewsByPath(
            hierarchy: allHierarchy,
            scrollViewCandidates: scrollViewCandidates
        )
        let allObjectsByPath = Self.objectsByPath(
            hierarchy: allHierarchy,
            objectCandidates: objectCandidates
        )
        let allContainerObjectsByPath = Self.containerObjectsByPath(
            hierarchy: allHierarchy,
            objectCandidates: containerObjectCandidates
        )
        return ParseResult(
            hierarchy: allHierarchy,
            objects: allObjects,
            objectsByPath: allObjectsByPath,
            containerObjectsByPath: allContainerObjectsByPath,
            scrollViews: Self.scrollViewsByContainerForCurrentCapture(
                hierarchy: allHierarchy,
                scrollViewsByPath: allScrollViewsByPath
            ),
            scrollViewsByPath: allScrollViewsByPath
        )
    }

    /// Parse one live accessibility object by pumping it through the regular
    /// hierarchy parser with a temporary accessibility root. The object may be
    /// a custom rotor result that VoiceOver can focus even though it is not
    /// discoverable by walking the current app hierarchy.
    func parseObject(_ object: NSObject) -> AccessibilityElement? {
        let root = RotorResultParsingRoot(object: object)
        var parsedResult: AccessibilityElement?
        let hierarchy: [AccessibilityHierarchy] = parser.parseAccessibilityHierarchy(
            in: root,
            rotorResultLimit: 0,
            makeElement: { element, traversalIndex, parsedObject in
                if parsedObject === object {
                    parsedResult = element
                }
                return AccessibilityHierarchy.element(element, traversalIndex: traversalIndex)
            },
            makeContainer: { container, children, _ in
                AccessibilityHierarchy.container(container, children: children)
            }
        )
        if let parsedResult {
            return parsedResult
        }
        return hierarchy.sortedElements.first
    }

    private static func objectsByPath(
        hierarchy: [AccessibilityHierarchy],
        objectCandidates: [AccessibilityElement: [NSObject]]
    ) -> [TreePath: NSObject] {
        var consumedCounts: [AccessibilityElement: Int] = [:]
        var result: [TreePath: NSObject] = [:]
        for (element, path, _) in hierarchy.pathIndexedElements {
            let nextIndex = consumedCounts[element, default: 0]
            if let objects = objectCandidates[element], objects.indices.contains(nextIndex) {
                result[path] = objects[nextIndex]
            }
            consumedCounts[element] = nextIndex + 1
        }
        return result
    }

    private static func scrollViewsByPath(
        hierarchy: [AccessibilityHierarchy],
        scrollViewCandidates: [AccessibilityContainer: [UIView]]
    ) -> [TreePath: UIView] {
        var consumedCounts: [AccessibilityContainer: Int] = [:]
        var result: [TreePath: UIView] = [:]
        for (container, path) in parserVisitorScrollableContainerPaths(hierarchy: hierarchy) {
            let nextIndex = consumedCounts[container, default: 0]
            if let views = scrollViewCandidates[container], views.indices.contains(nextIndex) {
                result[path] = views[nextIndex]
            }
            consumedCounts[container] = nextIndex + 1
        }
        return result
    }

    private static func containerObjectsByPath(
        hierarchy: [AccessibilityHierarchy],
        objectCandidates: [AccessibilityContainer: [NSObject]]
    ) -> [TreePath: NSObject] {
        var consumedCounts: [AccessibilityContainer: Int] = [:]
        var result: [TreePath: NSObject] = [:]
        for (container, path) in parserVisitorContainerPaths(hierarchy: hierarchy) {
            let nextIndex = consumedCounts[container, default: 0]
            if let objects = objectCandidates[container], objects.indices.contains(nextIndex) {
                result[path] = objects[nextIndex]
            }
            consumedCounts[container] = nextIndex + 1
        }
        return result
    }

    private static func parserVisitorContainerPaths(
        hierarchy: [AccessibilityHierarchy]
    ) -> [(container: AccessibilityContainer, path: TreePath)] {
        hierarchy.enumerated().flatMap { index, node in
            parserVisitorContainerPaths(node: node, path: TreePath([index]))
        }
    }

    private static func parserVisitorContainerPaths(
        node: AccessibilityHierarchy,
        path: TreePath
    ) -> [(container: AccessibilityContainer, path: TreePath)] {
        guard case .container(let container, let children) = node else { return [] }

        var result = children.enumerated().flatMap { index, child in
            parserVisitorContainerPaths(node: child, path: path.appending(index))
        }
        result.append((container, path))
        return result
    }

    private static func parserVisitorScrollableContainerPaths(
        hierarchy: [AccessibilityHierarchy]
    ) -> [(container: AccessibilityContainer, path: TreePath)] {
        hierarchy.enumerated().flatMap { index, node in
            parserVisitorScrollableContainerPaths(node: node, path: TreePath([index]))
        }
    }

    private static func parserVisitorScrollableContainerPaths(
        node: AccessibilityHierarchy,
        path: TreePath
    ) -> [(container: AccessibilityContainer, path: TreePath)] {
        guard case .container(let container, let children) = node else { return [] }

        var result = children.enumerated().flatMap { index, child in
            parserVisitorScrollableContainerPaths(node: child, path: path.appending(index))
        }
        if container.isScrollable {
            result.append((container, path))
        }
        return result
    }

    private static func scrollViewsByContainerForCurrentCapture(
        hierarchy: [AccessibilityHierarchy],
        scrollViewsByPath: [TreePath: UIView]
    ) -> [AccessibilityContainer: UIView] {
        var result: [AccessibilityContainer: UIView] = [:]
        for (container, path) in hierarchy.containerPaths where container.isScrollable {
            guard result[container] == nil, let view = scrollViewsByPath[path] else { continue }
            result[container] = view
        }
        return result
    }

}

private final class RotorResultParsingRoot: UIView {
    private let rotorResultObject: NSObject

    init(object: NSObject) {
        self.rotorResultObject = object
        super.init(frame: ScreenMetrics.current.bounds)
        isAccessibilityElement = false
        accessibilityElements = [rotorResultObject]
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        return nil
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
