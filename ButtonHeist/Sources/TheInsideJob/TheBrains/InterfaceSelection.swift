#if canImport(UIKit)
import Foundation

import AccessibilitySnapshotModel
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
        let annotations = interface.annotations.elementByTraversalIndex
        let tree = interface.tree.subtrees { node, _ in
            guard case .element(let element, let traversalIndex) = node else { return false }
            return HeistElement(
                accessibilityElement: element,
                annotation: annotations[traversalIndex]
            ).matches(matcher)
        }
        return Interface(
            timestamp: interface.timestamp,
            tree: tree,
            annotations: leafAnnotations(for: tree)
        )
    }

    private func selectLeafSubtrees(withIds heistIds: Set<String>) -> Interface {
        let annotations = interface.annotations.elementByTraversalIndex
        let tree = interface.tree.subtrees { node, _ in
            guard case .element(_, let traversalIndex) = node,
                  let annotation = annotations[traversalIndex]
            else { return false }
            return heistIds.contains(annotation.heistId)
        }
        return Interface(
            timestamp: interface.timestamp,
            tree: tree,
            annotations: leafAnnotations(for: tree)
        )
    }

    private func select(_ subtree: SubtreeSelector) throws(InterfaceSelectionError) -> Interface {
        let elementAnnotations = interface.annotations.elementByTraversalIndex
        let containerAnnotations = interface.annotations.containerByPath
        let candidates = interface.tree.compactMapSubtrees { node, path -> InterfaceSubtreeCandidate? in
            switch node {
            case .element(let element, let traversalIndex):
                let projected = HeistElement(
                    accessibilityElement: element,
                    annotation: elementAnnotations[traversalIndex]
                )
                guard case .element(let matcher, _) = subtree, projected.matches(matcher) else { return nil }
                return InterfaceSubtreeCandidate(
                    node: node,
                    originalPath: path,
                    summary: projected.subtreeCandidateSummary
                )
            case .container(let container, _):
                let annotation = containerAnnotations[path]
                guard case .container(let matcher, _) = subtree,
                      container.matches(matcher, annotation: annotation)
                else { return nil }
                return InterfaceSubtreeCandidate(
                    node: node,
                    originalPath: path,
                    summary: container.subtreeCandidateSummary(annotation: annotation)
                )
            }
        }
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
            return selectedInterface(for: candidates[ordinal])
        }

        guard candidates.count == 1 else {
            throw .ambiguousSubtree(
                candidateCount: candidates.count,
                candidates: candidates.map(\.summary)
            )
        }

        return selectedInterface(for: candidates[0])
    }

    private func selectedInterface(for candidate: InterfaceSubtreeCandidate) -> Interface {
        Interface(
            timestamp: interface.timestamp,
            tree: [candidate.node],
            annotations: annotations(for: candidate)
        )
    }

    private func annotations(for candidate: InterfaceSubtreeCandidate) -> InterfaceAnnotations {
        interface.annotations(
            forSubtree: candidate.node,
            originalPath: candidate.originalPath,
            rootPath: TreePath([0])
        )
    }

    private func leafAnnotations(for tree: [AccessibilityHierarchy]) -> InterfaceAnnotations {
        let traversalIndices = Set(tree.indexedElements.map(\.traversalIndex))
        return InterfaceAnnotations(
            elements: interface.annotations.elements.filter { traversalIndices.contains($0.traversalIndex) }
        )
    }
}

private struct InterfaceSubtreeCandidate {
    let node: AccessibilityHierarchy
    let originalPath: TreePath
    let summary: String
}

private extension AccessibilityContainer {
    func subtreeCandidateSummary(annotation: InterfaceContainerAnnotation?) -> String {
        [
            "container",
            subtreeSummaryRequiredField("type", typeName.rawValue),
            subtreeSummaryField("stableId", annotation?.stableId),
            subtreeSummaryField("identifier", containerIdentifier),
            subtreeSummaryField("label", containerLabel),
            subtreeSummaryField("value", containerValue),
            isModalBoundary ? "isModalBoundary=true" : nil,
        ].compactMap { $0 }.joined(separator: " ")
    }

    var typeName: ContainerTypeName {
        switch type {
        case .semanticGroup:
            return .semanticGroup
        case .list:
            return .list
        case .landmark:
            return .landmark
        case .dataTable:
            return .dataTable
        case .tabBar:
            return .tabBar
        case .scrollable:
            return .scrollable
        }
    }

    var containerLabel: String? {
        if case .semanticGroup(let label, _, _) = type { return label }
        return nil
    }

    var containerValue: String? {
        if case .semanticGroup(_, let value, _) = type { return value }
        return nil
    }

    var containerIdentifier: String? {
        if case .semanticGroup(_, _, let identifier) = type { return identifier }
        return nil
    }

    func matches(_ matcher: ContainerMatcher, annotation: InterfaceContainerAnnotation?) -> Bool {
        if let stableId = matcher.stableId {
            if stableId.isEmpty { return false }
            guard annotation?.stableId == stableId else { return false }
        }
        if let type = matcher.type {
            guard typeName == type else { return false }
        }
        if let label = matcher.label {
            if label.isEmpty { return false }
            guard ElementMatcher.stringEquals(containerLabel ?? "", label) else { return false }
        }
        if let value = matcher.value {
            if value.isEmpty { return false }
            guard ElementMatcher.stringEquals(containerValue ?? "", value) else { return false }
        }
        if let identifier = matcher.identifier {
            if identifier.isEmpty { return false }
            guard ElementMatcher.stringEquals(containerIdentifier ?? "", identifier) else { return false }
        }
        if let isModalBoundary = matcher.isModalBoundary {
            guard self.isModalBoundary == isModalBoundary else { return false }
        }
        return true
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
