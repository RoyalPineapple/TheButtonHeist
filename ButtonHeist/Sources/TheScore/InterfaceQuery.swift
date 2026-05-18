import Foundation

public struct InterfaceQuery: Codable, Sendable, Equatable {
    public let subtree: SubtreeSelector?
    public let matcher: ElementMatcher
    public let elementIds: [String]?

    public init(
        subtree: SubtreeSelector? = nil,
        matcher: ElementMatcher = ElementMatcher(),
        elementIds: [String]? = nil
    ) {
        self.subtree = subtree
        self.matcher = matcher
        self.elementIds = elementIds
    }
}

public struct InterfaceProjection: Sendable, Equatable {
    public let interface: Interface
    public let filteredFrom: Int?
    public let error: String?

    public init(interface: Interface, filteredFrom: Int? = nil, error: String? = nil) {
        self.interface = interface
        self.filteredFrom = filteredFrom
        self.error = error
    }
}

private struct InterfaceSubtreeCandidate {
    let node: InterfaceNode
    let summary: String
}

public extension Interface {
    func projecting(_ query: InterfaceQuery) -> InterfaceProjection {
        if let subtree = query.subtree {
            return projecting(subtree: subtree)
        }

        if query.matcher.hasPredicates {
            return InterfaceProjection(
                interface: projectingLeafSubtrees(matching: query.matcher),
                filteredFrom: elements.count
            )
        }

        if let elementIds = query.elementIds, !elementIds.isEmpty {
            return InterfaceProjection(
                interface: projectingLeafSubtrees(withIds: Set(elementIds)),
                filteredFrom: elements.count
            )
        }

        return InterfaceProjection(interface: self)
    }

    private func projectingLeafSubtrees(matching matcher: ElementMatcher) -> Interface {
        Interface(
            timestamp: timestamp,
            tree: tree.flatMap { $0.leafSubtreeNodes(matching: matcher) }
        )
    }

    private func projectingLeafSubtrees(withIds heistIds: Set<String>) -> Interface {
        Interface(
            timestamp: timestamp,
            tree: tree.flatMap { $0.leafSubtreeNodes(withIds: heistIds) }
        )
    }

    private func subtreeCandidates(matching selector: SubtreeSelector) -> [InterfaceSubtreeCandidate] {
        tree.flatMap { $0.subtreeCandidates(matching: selector) }
    }

    private func projecting(subtree candidate: InterfaceSubtreeCandidate) -> Interface {
        Interface(timestamp: timestamp, tree: [candidate.node])
    }

    private func projecting(subtree: SubtreeSelector) -> InterfaceProjection {
        let candidates = subtreeCandidates(matching: subtree)
        guard !candidates.isEmpty else {
            let message = """
                get_interface subtree matched no nodes; refine subtree using a container \
                stableId/type/label/identifier or a leaf heistId/matcher from get_interface.
                """
            return InterfaceProjection(interface: self, error: message)
        }

        if let ordinal = subtree.ordinal {
            guard candidates.indices.contains(ordinal) else {
                let range = candidates.count == 1 ? "0" : "0...\(candidates.count - 1)"
                let message = """
                    get_interface subtree ordinal \(ordinal) is out of range for \(candidates.count) matches; \
                    use \(range) or refine subtree. Candidates: \(candidates.diagnosticList)
                    """
                return InterfaceProjection(interface: self, error: message)
            }
            return InterfaceProjection(
                interface: projecting(subtree: candidates[ordinal]),
                filteredFrom: elements.count
            )
        }

        guard candidates.count == 1 else {
            let message = """
                get_interface subtree matched \(candidates.count) nodes; add subtree.ordinal \
                0...\(candidates.count - 1) or refine subtree. Candidates: \(candidates.diagnosticList)
                """
            return InterfaceProjection(interface: self, error: message)
        }
        return InterfaceProjection(
            interface: projecting(subtree: candidates[0]),
            filteredFrom: elements.count
        )
    }
}

private extension InterfaceNode {
    func leafSubtreeNodes(matching matcher: ElementMatcher) -> [InterfaceNode] {
        switch self {
        case .element(let element):
            return element.matches(matcher) ? [self] : []
        case .container(_, let children):
            return children.flatMap { $0.leafSubtreeNodes(matching: matcher) }
        }
    }

    func leafSubtreeNodes(withIds heistIds: Set<String>) -> [InterfaceNode] {
        switch self {
        case .element(let element):
            return heistIds.contains(element.heistId) ? [self] : []
        case .container(_, let children):
            return children.flatMap { $0.leafSubtreeNodes(withIds: heistIds) }
        }
    }

    func subtreeCandidates(matching selector: SubtreeSelector) -> [InterfaceSubtreeCandidate] {
        switch self {
        case .element(let element):
            guard case .element(let matcher, _) = selector, element.matches(matcher) else { return [] }
            return [InterfaceSubtreeCandidate(node: self, summary: element.subtreeCandidateSummary)]
        case .container(let info, let children):
            var candidates: [InterfaceSubtreeCandidate] = []
            if case .container(let matcher, _) = selector, info.matches(matcher) {
                candidates.append(InterfaceSubtreeCandidate(node: self, summary: info.subtreeCandidateSummary))
            }
            candidates.append(contentsOf: children.flatMap { $0.subtreeCandidates(matching: selector) })
            return candidates
        }
    }
}

private extension ContainerInfo {
    var subtreeCandidateSummary: String {
        [
            "container",
            subtreeSummaryRequiredField("type", typeName.rawValue),
            subtreeSummaryField("stableId", stableId),
            subtreeSummaryField("identifier", containerIdentifier),
            subtreeSummaryField("label", containerLabel),
            subtreeSummaryField("value", containerValue),
            isModalBoundary ? "isModalBoundary=true" : nil,
        ].compactMap { $0 }.joined(separator: " ")
    }
}

private extension HeistElement {
    var subtreeCandidateSummary: String {
        [
            "element",
            subtreeSummaryRequiredField("heistId", heistId),
            subtreeSummaryField("identifier", identifier),
            subtreeSummaryField("label", label),
            subtreeSummaryField("value", value),
            traits.isEmpty ? nil : subtreeSummaryRequiredField("traits", traits.map(\.rawValue).joined(separator: ",")),
        ].compactMap { $0 }.joined(separator: " ")
    }
}

private func subtreeSummaryField(_ name: String, _ value: String?) -> String? {
    guard let value, !value.isEmpty else { return nil }
    return subtreeSummaryRequiredField(name, value)
}

private func subtreeSummaryRequiredField(_ name: String, _ value: String) -> String {
    "\(name)=\"\(value)\""
}

private extension Array where Element == InterfaceSubtreeCandidate {
    var diagnosticList: String {
        enumerated().map { index, candidate in
            "[\(index)] \(candidate.summary)"
        }.joined(separator: "; ")
    }
}
