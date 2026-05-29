#if canImport(UIKit)
#if DEBUG
import Foundation

import AccessibilitySnapshotParser

import TheScore

// MARK: - Target Resolution

extension TheStash {

    /// Result of resolving an ElementTarget to known semantic target data.
    ///
    /// This does not prove the backing UIKit object, frame, or activation
    /// point are still live. Actions must resolve a `LiveActionTarget`
    /// immediately before dispatch.
    struct ResolvedTarget {
        let screenElement: ScreenElement

        var element: AccessibilityElement { screenElement.element }
    }

    /// Which part of the committed interface state a lookup should read.
    enum InterfaceElementScope {
        /// Elements in the live accessibility hierarchy from the most recent parse.
        case visible
        /// Elements retained on the committed screen value, including an exploration union.
        case known
    }

    enum ResolutionScope: String {
        case known
        case provided
        case visible
    }

    /// Three-case result from `resolveTarget` — diagnostics are produced
    /// inline during resolution, not via a separate re-scan.
    enum TargetResolution {
        case resolved(ResolvedTarget)
        case notFound(diagnostics: String)
        case ambiguous(candidates: [String], diagnostics: String)

        var resolved: ResolvedTarget? {
            if case .resolved(let resolved) = self { return resolved }
            return nil
        }

        var diagnostics: String {
            switch self {
            case .resolved: return ""
            case .notFound(let message): return message
            case .ambiguous(_, let message): return message
            }
        }
    }

    /// Semantic container match selected from committed screen state.
    ///
    /// The backing UIKit object is intentionally excluded. Container actions
    /// must acquire a `LiveContainerTarget` immediately before dispatch.
    struct ResolvedContainerTarget {
        let container: AccessibilityContainer
        let path: TreePath
        let stableId: HeistContainer?
        let contentFrame: CGRect?
    }

    enum ContainerTargetResolution {
        case resolved(ResolvedContainerTarget)
        case notFound(diagnostics: String)
        case ambiguous(candidates: [String], diagnostics: String)

        var diagnostics: String {
            switch self {
            case .resolved: return ""
            case .notFound(let message): return message
            case .ambiguous(_, let message): return message
            }
        }
    }

    /// Resolve a target to a unique element. Returns `.resolved` on success,
    /// `.notFound` or `.ambiguous` with diagnostics on failure.
    ///
    /// Resolution reads the committed semantic state. If an element is not in
    /// `currentScreen.knownInterface`, resolution fails with a near-miss
    /// suggestion. Live coordinate revalidation happens later in action execution.
    func resolveTarget(_ target: ElementTarget) -> TargetResolution {
        resolveTarget(target, in: currentScreen, resolutionScope: .known)
    }

    /// Resolve a target against a supplied screen value. Used by callers that
    /// intentionally preserved a known semantic snapshot across a fresh visible
    /// parse.
    func resolveTarget(_ target: ElementTarget, in screen: Screen) -> TargetResolution {
        resolveTarget(target, in: screen, resolutionScope: .provided)
    }

    /// Resolve a target only against the latest live hierarchy. This preserves
    /// full target semantics (ambiguity and explicit ordinal) while excluding
    /// known-only entries retained from exploration.
    func resolveVisibleTarget(_ target: ElementTarget) -> TargetResolution {
        resolveTarget(target, in: currentScreen.visibleOnly, resolutionScope: .visible)
    }

    func resolveContainerTarget(_ matcher: ContainerMatcher, ordinal: Int?) -> ContainerTargetResolution {
        guard matcher.hasPredicates else {
            return .notFound(diagnostics: "container target requires stableId, type, label, value, or identifier")
        }
        let matches = currentScreen.semantic.containers.values
            .sorted { $0.path.indices.lexicographicallyPrecedes($1.path.indices) }
            .compactMap { item -> ResolvedContainerTarget? in
                let annotation = InterfaceContainerAnnotation(
                    path: item.path,
                    stableId: item.stableId
                )
                guard item.container.matches(matcher, annotation: annotation) else { return nil }
                return ResolvedContainerTarget(
                    container: item.container,
                    path: item.path,
                    stableId: annotation.stableId,
                    contentFrame: item.contentFrame
                )
            }
        if let ordinal {
            guard matches.indices.contains(ordinal) else {
                return .notFound(diagnostics: "container target ordinal \(ordinal) is outside \(matches.count) matching container(s)")
            }
            return .resolved(matches[ordinal])
        }
        switch matches.count {
        case 1:
            return .resolved(matches[0])
        case 0:
            return .notFound(diagnostics: "no semantic container matched \(matcher)")
        default:
            let candidates = matches.map(Self.containerCandidateSummary)
            return .ambiguous(
                candidates: candidates,
                diagnostics: "container target matched \(matches.count) containers; provide ordinal. Candidates: \(candidates.joined(separator: "; "))"
            )
        }
    }

    /// HeistIds for either the live hierarchy or the committed known screen.
    func ids(in scope: InterfaceElementScope) -> Set<HeistId> {
        switch scope {
        case .visible:
            return currentScreen.liveCapture.heistIds
        case .known:
            return currentScreen.knownInterface.heistIds
        }
    }

    /// Looks up an element by heistId in the selected scope.
    ///
    /// `.known` reads the committed semantic element map, including any
    /// exploration union. `.visible` only returns ids backed by the latest live
    /// hierarchy parse.
    func screenElement(heistId: HeistId, in scope: InterfaceElementScope) -> ScreenElement? {
        guard let entry = currentScreen.knownInterface.findElement(heistId: heistId) else { return nil }
        switch scope {
        case .visible:
            return currentScreen.liveCapture.contains(heistId: heistId) ? entry : nil
        case .known:
            return entry
        }
    }

    /// Looks up the screen entry for a live accessibility element.
    ///
    /// Because the input is a live element, this first resolves through
    /// `heistIdByElement`. Off-screen known elements cannot be found with this
    /// overload.
    func screenElement(for element: AccessibilityElement, in scope: InterfaceElementScope) -> ScreenElement? {
        guard let heistId = currentScreen.liveCapture.heistId(for: element) else { return nil }
        return screenElement(heistId: heistId, in: scope)
    }

    /// Resolve a target using first-match semantics against only the live hierarchy.
    func resolveFirstVisibleMatch(_ target: ElementTarget) -> ResolvedTarget? {
        let effectiveTarget: ElementTarget
        switch target {
        case .heistId:
            effectiveTarget = target
        case .matcher(let matcher, _):
            effectiveTarget = .matcher(matcher, ordinal: 0)
        }
        return resolveVisibleTarget(effectiveTarget).resolved
    }

    /// Boolean existence check for callers that only need present-vs-missing
    /// target semantics. Ambiguous matches count as present, and explicit
    /// ordinals must resolve at the requested index instead of falling back to
    /// the first match.
    func hasTarget(_ target: ElementTarget) -> Bool {
        switch resolveTarget(target) {
        case .resolved, .ambiguous:
            return true
        case .notFound:
            return false
        }
    }

    func matcherNotFoundMessage(
        _ matcher: ElementMatcher,
        in screen: Screen? = nil,
        resolutionScope: ResolutionScope = .known
    ) -> String {
        let screen = screen ?? currentScreen
        return Diagnostics.matcherNotFound(
            matcher,
            screenElements: selectElements(in: screen),
            visibleHeistIds: screen.visibleIds,
            resolutionScope: resolutionScope
        )
    }

    func formatMatcher(_ matcher: ElementMatcher) -> String {
        Diagnostics.formatMatcher(matcher)
    }

    /// All elements in the current screen.
    ///
    /// Live elements appear first in hierarchy (depth-first) traversal order;
    /// any heistIds present in `currentScreen.semantic.elements` but not in the live
    /// hierarchy (post-exploration union) appear after, sorted by heistId so
    /// the snapshot order is stable across runs.
    func selectElements(in screen: Screen? = nil) -> [ScreenElement] {
        (screen ?? currentScreen).orderedElements
    }
}

private extension TheStash {

    func resolveTarget(
        _ target: ElementTarget,
        in screen: Screen,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        switch target {
        case .heistId(let heistId):
            guard let entry = screen.findElement(heistId: heistId) else {
                return .notFound(diagnostics: Diagnostics.heistIdNotFound(
                    heistId,
                    knownIds: screen.semantic.elements.keys,
                    knownCount: screen.semantic.elements.count
                ))
            }
            return .resolved(ResolvedTarget(screenElement: entry))
        case .matcher(let matcher, let ordinal):
            return resolveMatcher(matcher, ordinal: ordinal, in: screen, resolutionScope: resolutionScope)
        }
    }

    func resolveMatcher(
        _ matcher: ElementMatcher,
        ordinal: Int?,
        in screen: Screen,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        if let ordinal {
            guard ordinal >= 0 else {
                return .notFound(diagnostics: """
                    ordinal must be non-negative, got \(ordinal)
                    Next: remove ordinal, or use ordinal 0 after the target query resolves candidates.
                    """)
            }
            let matches = matchScreenElements(matcher, limit: ordinal + 1, in: screen)
            guard ordinal < matches.count else {
                let total = matches.count
                let nextMove: String
                if total == 0 {
                    nextMove = "Next: retry with an exact label, identifier, or current heistId."
                } else {
                    nextMove = "Next: use ordinal 0...\(total - 1), omit ordinal to inspect ambiguity, "
                        + "or target a listed element by exact label, identifier, or heistId."
                }
                return .notFound(diagnostics: """
                    ordinal \(ordinal) requested but only \(total) match\(total == 1 ? "" : "es") found
                    \(nextMove)
                    """)
            }
            return .resolved(ResolvedTarget(screenElement: matches[ordinal]))
        }
        let matches = matchScreenElements(matcher, limit: 2, in: screen)
        switch matches.count {
        case 0:
            return .notFound(diagnostics: matcherNotFoundMessage(
                matcher,
                in: screen,
                resolutionScope: resolutionScope
            ))
        case 1:
            return .resolved(ResolvedTarget(screenElement: matches[0]))
        default:
            let capped = matchScreenElements(matcher, limit: 11, in: screen)
            return ambiguousResolution(
                matcher,
                screenElements: capped,
                visibleHeistIds: screen.visibleIds,
                resolutionScope: resolutionScope
            )
        }
    }

    func ambiguousResolution(
        _ matcher: ElementMatcher,
        screenElements: [ScreenElement],
        visibleHeistIds: Set<HeistId>,
        resolutionScope: ResolutionScope
    ) -> TargetResolution {
        let candidates = screenElements.prefix(10).map { screenElement -> String in
            let element = screenElement.element
            var parts: [String] = []
            if let label = element.label, !label.isEmpty { parts.append("\"\(label)\"") }
            if let identifier = element.identifier, !identifier.isEmpty { parts.append("id=\(identifier)") }
            if let value = element.value, !value.isEmpty { parts.append("value=\(value)") }
            parts.append(Diagnostics.availabilityDescription(for: screenElement, visibleHeistIds: visibleHeistIds))
            return parts.joined(separator: " ")
        }
        let query = formatMatcher(matcher)
        let countLabel = screenElements.count > 10 ? "10+" : "\(screenElements.count)"
        let rangeLabel = screenElements.count > 10 ? "0, 1, 2, ..." : "0–\(screenElements.count - 1)"
        var lines = [
            "\(countLabel) elements match: \(query) (scope: \(resolutionScope.rawValue)) — use ordinal \(rangeLabel) to select one"
        ]
        lines.append(contentsOf: candidates.map { "  \($0)" })
        if screenElements.count > 10 {
            lines.append("  ... and more")
        }
        return .ambiguous(candidates: candidates, diagnostics: lines.joined(separator: "\n"))
    }
}

extension TheStash {

    static func containerCandidateSummary(_ target: ResolvedContainerTarget) -> String {
        [
            target.stableId.map { "stableId=\"\($0)\"" },
            "type=\(target.container.typeName.rawValue)",
            target.container.containerIdentifier.map { "identifier=\"\($0)\"" },
            target.container.containerLabel.map { "label=\"\($0)\"" },
            target.container.containerValue.map { "value=\"\($0)\"" },
        ].compactMap { $0 }.joined(separator: " ")
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
