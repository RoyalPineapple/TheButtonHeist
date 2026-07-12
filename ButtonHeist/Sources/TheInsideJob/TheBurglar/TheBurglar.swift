#if canImport(UIKit)
#if DEBUG
import UIKit

import TheScore

import AccessibilitySnapshotParser

/// The crew member who breaks in and takes what he finds.
///
/// TheBurglar reads the live accessibility tree and assigns heistIds. Pure
/// helpers — he has no mutable state. TheStash invokes
/// him via `parse()` to obtain a `InterfaceObservation` value, then commits or merges it on
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
        let objectsByPath: [TreePath: NSObject]
        let containerObjectsByPath: [TreePath: NSObject]
        let scrollViewsByPath: [TreePath: UIScrollView]
        let screenCoordinateOffsetsByPath: [TreePath: CGPoint]

        init(
            hierarchy: [AccessibilityHierarchy],
            objectsByPath: [TreePath: NSObject] = [:],
            containerObjectsByPath: [TreePath: NSObject] = [:],
            scrollViewsByPath: [TreePath: UIScrollView] = [:],
            screenCoordinateOffsetsByPath: [TreePath: CGPoint] = [:]
        ) {
            self.hierarchy = hierarchy
            self.objectsByPath = objectsByPath
            self.containerObjectsByPath = containerObjectsByPath
            self.scrollViewsByPath = scrollViewsByPath
            self.screenCoordinateOffsetsByPath = screenCoordinateOffsetsByPath
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
        var objectsByPath: [TreePath: NSObject] = [:]
        var containerObjectsByPath: [TreePath: NSObject] = [:]
        var scrollViewsByPath: [TreePath: UIScrollView] = [:]
        var screenCoordinateOffsetsByPath: [TreePath: CGPoint] = [:]

        let isMultiWindow = windows.count > 1

        for entry in windows {
            let window = entry.window
            let rootView = entry.rootView
            let containsModalBoundary = autoreleasepool { () -> Bool in
                let captured = parser.parseAccessibilityHierarchy(
                    in: rootView,
                    rotorResultLimit: 0,
                    makeElement: { element, traversalIndex, source in
                        CapturedNode.element(element, traversalIndex: traversalIndex, source: source)
                    },
                    makeContainer: { container, children, source in
                        CapturedNode.container(container, children: children, source: source)
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

        return ParseResult(
            hierarchy: allHierarchy,
            objectsByPath: objectsByPath,
            containerObjectsByPath: containerObjectsByPath,
            scrollViewsByPath: scrollViewsByPath,
            screenCoordinateOffsetsByPath: screenCoordinateOffsetsByPath
        )
    }

    /// Parse one live accessibility object by pumping it through the regular
    /// hierarchy parser with a temporary accessibility root. The object may be
    /// a custom rotor result that VoiceOver can focus even though it is not
    /// discoverable by walking the current app hierarchy.
    func parseObject(_ object: NSObject) -> AccessibilityElement? {
        let root = SingleElementParsingRoot(object: object)
        let captured = parser.parseAccessibilityHierarchy(
            in: root,
            rotorResultLimit: 0,
            makeElement: { element, traversalIndex, source in
                CapturedNode.element(element, traversalIndex: traversalIndex, source: source)
            },
            makeContainer: { container, children, source in
                CapturedNode.container(container, children: children, source: source)
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
        _ node: CapturedNode,
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

#endif // DEBUG
#endif // canImport(UIKit)
