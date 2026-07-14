#if canImport(UIKit)
import Foundation

import ThePlans
import TheScore

import AccessibilitySnapshotModel

enum InterfaceSelectionError: Error, Equatable {
    case invalidSubtree(String)
    case subtreeNotFound
    case subtreeOrdinalOutOfRange(ordinal: Int, candidateCount: Int, candidates: [String])
    case ambiguousSubtree(candidateCount: Int, candidates: [String])

    var message: String {
        switch self {
        case .invalidSubtree(let reason):
            return "get_interface subtree could not be resolved: \(reason)"
        case .subtreeNotFound:
            return """
                get_interface subtree matched no nodes; refine subtree using a container \
                or element target from get_interface.
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
        guard let subtree = query.subtree else { return interface }
        do {
            return try select(subtree.resolve(in: .empty))
        } catch let error as InterfaceSelectionError {
            throw error
        } catch {
            throw .invalidSubtree(String(describing: error))
        }
    }

    private func select(_ subtree: ResolvedAccessibilityTarget) throws(InterfaceSelectionError) -> Interface {
        let graph = interface.graph
        let resolution = InterfaceSubtreeResolution(subtree)
        let selectedTargetPaths = ElementMatchGraph(interface: interface).resolve(resolution.target).paths
        let candidates = graph.nodesInPathOrder.compactMap { record -> InterfaceSubtreeCandidate? in
            guard selectedTargetPaths.contains(record.path) else { return nil }
            switch record.kind {
            case .element(let elementRecord):
                let projected = elementRecord.projectedElement
                return InterfaceSubtreeCandidate(
                    node: record.node,
                    originalPath: record.path,
                    traversalIndex: elementRecord.traversalIndex,
                    summary: projected.subtreeCandidateSummary
                )

            case .container(let containerRecord):
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

        if let ordinal = resolution.ordinal {
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
        let annotations = annotations(for: candidate)
        let traceIdentities = traceIdentities(for: candidate)
        return Interface(
            timestamp: interface.timestamp,
            projecting: [candidate.node],
            diagnostics: interface.diagnostics,
            elementMetadata: { path, _, _ in
                guard let annotation = annotations.elementByPath[path] else { return nil }
                return InterfaceElementProjectionMetadata(
                    actions: annotation.actions,
                    traceIdentity: traceIdentities[path]
                )
            },
            containerMetadata: { path, _ in
                guard let annotation = annotations.containerByPath[path] else { return nil }
                return InterfaceContainerProjectionMetadata(
                    containerName: annotation.containerName,
                    scrollInventory: annotation.scrollInventory
                )
            }
        )
    }

    private func annotations(for candidate: InterfaceSubtreeCandidate) -> InterfaceAnnotations {
        interface.graph.annotationsForSubtree(originalPath: candidate.originalPath, rootPath: TreePath([0]))
    }

    private func traceIdentities(for candidate: InterfaceSubtreeCandidate) -> InterfaceTraceIdentities {
        interface.graph.traceIdentitiesForSubtree(originalPath: candidate.originalPath, rootPath: TreePath([0]))
    }
}

private struct InterfaceSubtreeResolution {
    let target: ResolvedAccessibilityTarget
    let ordinal: Int?

    init(_ target: ResolvedAccessibilityTarget) {
        switch target {
        case .predicate(let predicate, let ordinal):
            self.target = .predicate(predicate)
            self.ordinal = ordinal
        case .container(let predicate, let ordinal):
            self.target = .container(predicate)
            self.ordinal = ordinal
        case .within:
            self.target = target
            self.ordinal = nil
        }
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
        let facts = containerPredicateFacts
        let semanticFields: [String?]
        switch facts.role {
        case .semanticGroup(let label, let value):
            semanticFields = [
                subtreeSummaryField("label", label),
                subtreeSummaryField("value", value),
            ]
        case .none, .list, .landmark, .dataTable, .tabBar, .series:
            semanticFields = []
        }
        return ([
            "container",
            subtreeSummaryRequiredField("type", facts.role.kind.rawValue),
            subtreeSummaryField("containerName", annotation?.containerName?.rawValue),
            subtreeSummaryField("identifier", facts.identifier),
        ] + semanticFields + [
            facts.isModalBoundary ? "isModalBoundary=true" : nil,
            facts.isScrollable ? "isScrollable=true" : nil,
        ])
            .compactMap { $0 }
            .joined(separator: " ")
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
