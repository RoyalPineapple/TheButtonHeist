#if canImport(UIKit)
import Foundation
import ThePlans

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
                predicate or a leaf matcher from get_interface.
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

        return interface
    }

    private func selectLeafSubtrees(matching predicate: ElementPredicate) -> Interface {
        let candidates = interface.graph.elementsInTraversalOrder.compactMap { record -> InterfaceLeafCandidate? in
            guard record.projectedElement.matches(predicate) else { return nil }
            return InterfaceLeafCandidate(
                node: record.node,
                path: record.path,
                traversalIndex: record.traversalIndex,
                annotation: record.annotation,
                traceIdentity: record.traceIdentity
            )
        }
        return selectedInterface(forLeafCandidates: candidates)
    }

    private func select(_ subtree: SubtreeSelector) throws(InterfaceSelectionError) -> Interface {
        let graph = interface.graph
        let selectedElementPaths: Set<TreePath>?
        switch subtree {
        case .element(let target):
            selectedElementPaths = Set(ElementMatchGraph(interface: interface).resolve(target).orderedPaths)
        case .container:
            selectedElementPaths = nil
        }
        let candidates = graph.nodesInPathOrder.compactMap { record -> InterfaceSubtreeCandidate? in
            switch record.kind {
            case .element(let elementRecord):
                let projected = elementRecord.projectedElement
                guard case .element(let target) = subtree else { return nil }
                switch target {
                case .predicate(let predicate, _):
                    guard projected.matches(predicate) else { return nil }
                case .within:
                    guard selectedElementPaths?.contains(record.path) == true else { return nil }
                }
                return InterfaceSubtreeCandidate(
                    node: record.node,
                    originalPath: record.path,
                    traversalIndex: elementRecord.traversalIndex,
                    summary: projected.subtreeCandidateSummary
                )

            case .container(let containerRecord):
                guard case .container(let predicate, _) = subtree,
                      predicate.matches(containerRecord.container.containerPredicateFacts)
                else { return nil }
                return InterfaceSubtreeCandidate(
                    node: record.node,
                    originalPath: record.path,
                    traversalIndex: nil,
                    summary: containerRecord.container.subtreeCandidateSummary(annotation: containerRecord.annotation)
                )
            }
        }.sorted()
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
            annotations: annotations(for: candidate),
            diagnostics: interface.diagnostics,
            traceIdentities: traceIdentities(for: candidate)
        )
    }

    private func annotations(for candidate: InterfaceSubtreeCandidate) -> InterfaceAnnotations {
        interface.graph.annotationsForSubtree(originalPath: candidate.originalPath, rootPath: TreePath([0]))
    }

    private func traceIdentities(for candidate: InterfaceSubtreeCandidate) -> InterfaceTraceIdentities {
        interface.graph.traceIdentitiesForSubtree(originalPath: candidate.originalPath, rootPath: TreePath([0]))
    }

    private func selectedInterface(forLeafCandidates candidates: [InterfaceLeafCandidate]) -> Interface {
        let orderedCandidates = candidates.sorted()
        let tree = orderedCandidates.map(\.node)
        let elementAnnotations = orderedCandidates.enumerated().compactMap { index, candidate -> InterfaceElementAnnotation? in
            guard let annotation = candidate.annotation else { return nil }
            return InterfaceElementAnnotation(
                path: TreePath([index]),
                actions: annotation.actions
            )
        }
        let traceIdentities = Dictionary(uniqueKeysWithValues: orderedCandidates.enumerated().compactMap { index, candidate in
            candidate.traceIdentity.map { (TreePath([index]), $0) }
        })
        return Interface(
            timestamp: interface.timestamp,
            tree: tree,
            annotations: InterfaceAnnotations(elements: elementAnnotations),
            diagnostics: interface.diagnostics,
            traceIdentities: InterfaceTraceIdentities(traceIdentities)
        )
    }
}

private struct InterfaceLeafCandidate: Comparable {
    let node: AccessibilityHierarchy
    let path: TreePath
    let traversalIndex: Int
    let annotation: InterfaceElementAnnotation?
    let traceIdentity: TraceElementIdentity?

    static func == (lhs: InterfaceLeafCandidate, rhs: InterfaceLeafCandidate) -> Bool {
        lhs.traversalIndex == rhs.traversalIndex && lhs.path == rhs.path
    }

    static func < (lhs: InterfaceLeafCandidate, rhs: InterfaceLeafCandidate) -> Bool {
        if lhs.traversalIndex != rhs.traversalIndex {
            return lhs.traversalIndex < rhs.traversalIndex
        }
        return lhs.path < rhs.path
    }
}

private struct InterfaceSubtreeCandidate: Comparable {
    let node: AccessibilityHierarchy
    let originalPath: TreePath
    let traversalIndex: Int?
    let summary: String

    static func == (lhs: InterfaceSubtreeCandidate, rhs: InterfaceSubtreeCandidate) -> Bool {
        lhs.traversalIndex == rhs.traversalIndex && lhs.originalPath == rhs.originalPath
    }

    static func < (lhs: InterfaceSubtreeCandidate, rhs: InterfaceSubtreeCandidate) -> Bool {
        switch (lhs.traversalIndex, rhs.traversalIndex) {
        case let (left?, right?) where left != right:
            return left < right
        default:
            return lhs.originalPath < rhs.originalPath
        }
    }
}

private extension AccessibilityContainer {
    func subtreeCandidateSummary(annotation: InterfaceContainerAnnotation?) -> String {
        [
            "container",
            subtreeSummaryRequiredField("type", accessibilityContainerKind.rawValue),
            subtreeSummaryField("containerName", annotation?.containerName?.rawValue),
            subtreeSummaryField("identifier", containerPredicateIdentifier),
            subtreeSummaryField("label", containerPredicateLabel),
            subtreeSummaryField("value", containerPredicateValue),
            isModalBoundary ? "isModalBoundary=true" : nil,
        ].compactMap { $0 }.joined(separator: " ")
    }
}

private extension HeistElement {
    var subtreeCandidateSummary: String {
        [
            "element",
            subtreeSummaryRequiredField("element", description),
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
