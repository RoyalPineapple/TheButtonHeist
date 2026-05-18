#if canImport(UIKit)
import Foundation

import TheScore

enum InterfaceSelectionError: Error, Equatable {
    case subtreeNotFound
    case subtreeOrdinalOutOfRange(ordinal: Int, candidateCount: Int, candidates: [String])
    case ambiguousSubtree(candidateCount: Int, candidates: [String])

    var message: String {
        switch self {
        case .subtreeNotFound:
            return """
                get_interface subtree matched no nodes; refine subtree using a container \
                stableId/type/label/identifier or a leaf heistId/matcher from get_interface.
                """
        case .subtreeOrdinalOutOfRange(let ordinal, let candidateCount, let candidates):
            let range = candidateCount == 1 ? "0" : "0...\(candidateCount - 1)"
            return """
                get_interface subtree ordinal \(ordinal) is out of range for \(candidateCount) matches; \
                use \(range) or refine subtree. Candidates: \(Self.diagnosticList(candidates))
                """
        case .ambiguousSubtree(let candidateCount, let candidates):
            return """
                get_interface subtree matched \(candidateCount) nodes; add subtree.ordinal \
                0...\(candidateCount - 1) or refine subtree. Candidates: \(Self.diagnosticList(candidates))
                """
        }
    }

    private static func diagnosticList(_ candidates: [String]) -> String {
        candidates.enumerated().map { index, candidate in
            "[\(index)] \(candidate)"
        }.joined(separator: "; ")
    }
}

struct InterfaceSelector {
    let interface: Interface

    func select(_ query: InterfaceQuery) throws(InterfaceSelectionError) -> Interface {
        if let subtree = query.subtree {
            return try select(subtree)
        }

        if query.matcher.hasPredicates {
            return selectLeafSubtrees(matching: query.matcher)
        }

        if let elementIds = query.elementIds, !elementIds.isEmpty {
            return selectLeafSubtrees(withIds: Set(elementIds))
        }

        return interface
    }

    private func selectLeafSubtrees(matching matcher: ElementMatcher) -> Interface {
        Interface(
            timestamp: interface.timestamp,
            tree: interface.tree.flatMap { $0.leafSubtreeNodes(matching: matcher) }
        )
    }

    private func selectLeafSubtrees(withIds heistIds: Set<String>) -> Interface {
        Interface(
            timestamp: interface.timestamp,
            tree: interface.tree.flatMap { $0.leafSubtreeNodes(withIds: heistIds) }
        )
    }

    private func select(_ subtree: SubtreeSelector) throws(InterfaceSelectionError) -> Interface {
        let candidates = interface.tree.flatMap { $0.subtreeCandidates(matching: subtree) }
        guard !candidates.isEmpty else {
            throw .subtreeNotFound
        }

        if let ordinal = subtree.ordinal {
            guard candidates.indices.contains(ordinal) else {
                throw .subtreeOrdinalOutOfRange(
                    ordinal: ordinal,
                    candidateCount: candidates.count,
                    candidates: candidates.map(\.summary)
                )
            }
            return Interface(timestamp: interface.timestamp, tree: [candidates[ordinal].node])
        }

        guard candidates.count == 1 else {
            throw .ambiguousSubtree(
                candidateCount: candidates.count,
                candidates: candidates.map(\.summary)
            )
        }

        return Interface(timestamp: interface.timestamp, tree: [candidates[0].node])
    }
}

private struct InterfaceSubtreeCandidate {
    let node: InterfaceNode
    let summary: String
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
#endif
