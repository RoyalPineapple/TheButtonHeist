#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Interface Tree

/// Button Heist's durable, targetable representation of the accessibility tree.
///
/// `InterfaceTree` contains targetable accessibility identity and value-only
/// reveal evidence. Its viewport snapshot records the latest parser hierarchy
/// and path identity used to reconcile the next observation; semantic values
/// are not projected into a second store. Live UIKit references remain in
/// `InterfaceObservation.liveCapture` and are reacquired for every action.
struct InterfaceTree: Sendable, Equatable {
    let elements: [HeistId: Element]
    let containers: [TreePath: Container]
    let viewportCapture: LiveCapture.Snapshot

    static let empty = InterfaceTree(elements: [:], containers: [:], viewportCapture: .empty)

    init(
        elements: [HeistId: Element],
        containers: [TreePath: Container] = [:],
        viewportCapture: LiveCapture.Snapshot = .empty
    ) {
        self.elements = elements
        self.containers = containers
        self.viewportCapture = viewportCapture
    }

    var elementIDs: Set<HeistId> {
        Set(elements.keys)
    }

    var viewportElementIDs: Set<HeistId> {
        viewportCapture.heistIds
    }

    var firstResponderHeistId: HeistId? {
        viewportCapture.firstResponderHeistId.flatMap { elements[$0]?.heistId }
    }

    var elementCount: Int {
        elements.count
    }

    func findElement(heistId: HeistId) -> Element? {
        elements[heistId]
    }

    /// Hash of semantic accessibility state. Deliberately excludes
    /// viewport-only facts like live object refs, visible ids, current scroll
    /// offset, and live geometry.
    var interfaceHash: String {
        let fingerprints = elements.values
            .map(Self.semanticElementFingerprint)
            .sorted { $0.heistId < $1.heistId }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "Infinity",
            negativeInfinity: "-Infinity",
            nan: "NaN"
        )
        let data = Self.stableSemanticHashData(fingerprints, encoder: encoder)
        return "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    var summaryElement: AccessibilityElement? {
        let viewportElements = viewportCapture.hierarchy.sortedElements.filter { $0.visibility == .onscreen }
        if let explicit = viewportElements.first(where: { $0.traits.contains(.summaryElement) }) {
            return explicit
        }
        return viewportElements
            .enumerated()
            .compactMap { index, element -> (index: Int, element: AccessibilityElement)? in
                guard element.traits.contains(.header), element.label != nil else { return nil }
                return (index, element)
            }
            .min { left, right in
                let leftFrame = left.element.shape.frame
                let rightFrame = right.element.shape.frame
                if leftFrame.minY != rightFrame.minY { return leftFrame.minY < rightFrame.minY }
                if leftFrame.minX != rightFrame.minX { return leftFrame.minX < rightFrame.minX }
                return left.index < right.index
            }?
            .element
    }

    var name: String? {
        summaryElement?.label
    }

    var id: String? {
        TheScore.slugify(name)
    }

    var orderedContainers: [Container] {
        containers.values.sorted { left, right in
            left.path.indices.lexicographicallyPrecedes(right.path.indices)
        }
    }

    var orderedElements: [Element] {
        var seen = Set<HeistId>()
        let visible = viewportCapture.hierarchy.pathIndexedElements.compactMap { indexed -> Element? in
            guard let heistID = viewportCapture.heistIdsByPath[indexed.path],
                  viewportElementIDs.contains(heistID),
                  let element = elements[heistID],
                  seen.insert(heistID).inserted
            else { return nil }
            return element
        }
        let offViewport = elements
            .filter { !seen.contains($0.key) }
            .map(\.value)
            .sorted { $0.heistId < $1.heistId }
        return visible + offViewport
    }

    var viewportOnly: InterfaceTree {
        let containerPaths = Set(viewportCapture.hierarchy.pathIndexedContainers.map(\.path))
        return InterfaceTree(
            elements: elements.filter { viewportElementIDs.contains($0.key) },
            containers: containers.filter { containerPaths.contains($0.key) },
            viewportCapture: viewportCapture
        )
    }

    func merging(_ other: InterfaceTree) -> InterfaceTree {
        InterfaceTree(
            elements: elements.merging(other.elements) { _, new in new },
            containers: containers.merging(other.containers) { _, new in new },
            viewportCapture: other.viewportCapture
        )
    }

    @MainActor
    func updatingViewport(with observation: InterfaceObservation) -> InterfaceTree {
        guard observation.tree != .empty else { return .empty }
        let next = observation.tree
        let previousVisible = viewportElementIDs
        let disappearedVisible = previousVisible.subtracting(next.viewportElementIDs)
        let previousContainerPaths = Set(viewportCapture.hierarchy.pathIndexedContainers.map(\.path))
        let nextContainerPaths = Set(next.viewportCapture.hierarchy.pathIndexedContainers.map(\.path))
        let disappearedContainers = previousContainerPaths.subtracting(nextContainerPaths)
        return InterfaceTree(
            elements: elements
                .filter { !disappearedVisible.contains($0.key) }
                .merging(next.elements) { _, new in new },
            containers: containers
                .filter { !disappearedContainers.contains($0.key) }
                .merging(next.containers) { _, new in new },
            viewportCapture: next.viewportCapture
        )
    }

    // MARK: - Element Entry

    /// Durable scroll-container membership derived while walking the hierarchy.
    ///
    /// This is semantic placement evidence, not live action geometry: it records
    /// the owning scroll container and optional accessibility container index
    /// reported by UIKit. It deliberately cannot express an absolute scroll-content point.
    struct ScrollMembership: Sendable, Equatable {
        let containerPath: TreePath
        let index: Int?
    }

    /// Scroll-content coordinate captured whenever the parser delivers an
    /// element under its scroll view, including off-viewport elements.
    ///
    /// This is reveal evidence only. It is not current screen geometry, and it
    /// must not be projected into wire `frame` / `activationPoint` fields for
    /// off-viewport elements.
    struct ObservedScrollContentActivationPoint: Sendable, Equatable {
        let point: ScrollContentPoint

        init?(_ point: CGPoint) {
            guard let point = try? ScrollContentPoint(validating: point) else { return nil }
            self.point = point
        }

        init?(_ point: ScrollContentPoint) {
            self.point = point
        }
    }

    struct Element: Sendable, Equatable {
        let heistId: HeistId
        let path: TreePath
        let scrollMembership: ScrollMembership?
        let observedScrollContentActivationPoint: ObservedScrollContentActivationPoint?
        /// Parsed accessibility identity/value retained in the interface tree.
        /// Do not treat its frame or activation point as live action geometry.
        let element: AccessibilityElement

        var scrollContainerPath: TreePath? {
            scrollMembership?.containerPath
        }

        var scrollIndex: Int? {
            scrollMembership?.index
        }

        init(
            heistId: HeistId,
            path: TreePath = .root,
            scrollMembership: ScrollMembership?,
            observedScrollContentActivationPoint: ObservedScrollContentActivationPoint? = nil,
            element: AccessibilityElement
        ) {
            self.heistId = heistId
            self.path = path
            self.scrollMembership = scrollMembership
            self.observedScrollContentActivationPoint = observedScrollContentActivationPoint
            self.element = element
        }
    }

    // MARK: - Container Entry

    /// Durable interface-tree container identity and scroll inventory evidence.
    ///
    /// UIKit object refs and live activation geometry remain in `LiveCapture`
    /// and are acquired only at dispatch time.
    struct Container: Sendable, Equatable {
        let container: AccessibilityContainer
        let path: TreePath
        let containerName: ContainerName?
        let contentFrame: ContentRect?
        let scrollMembership: ScrollMembership?
        let observedScrollContentActivationPoint: ObservedScrollContentActivationPoint?
        let scrollInventory: ScrollInventory?

        init(
            container: AccessibilityContainer,
            path: TreePath,
            containerName: ContainerName?,
            contentFrame: CGRect?,
            scrollMembership: ScrollMembership? = nil,
            observedScrollContentActivationPoint: ObservedScrollContentActivationPoint? = nil,
            scrollInventory: ScrollInventory? = nil
        ) {
            self.init(
                container: container,
                path: path,
                containerName: containerName,
                contentRect: contentFrame.flatMap { try? ContentRect(validating: $0) },
                scrollMembership: scrollMembership,
                observedScrollContentActivationPoint: observedScrollContentActivationPoint,
                scrollInventory: scrollInventory
            )
        }

        init(
            container: AccessibilityContainer,
            path: TreePath,
            containerName: ContainerName?,
            contentRect: ContentRect?,
            scrollMembership: ScrollMembership? = nil,
            observedScrollContentActivationPoint: ObservedScrollContentActivationPoint? = nil,
            scrollInventory: ScrollInventory? = nil
        ) {
            self.container = container
            self.path = path
            self.containerName = containerName
            self.contentFrame = contentRect
            self.scrollMembership = scrollMembership
            self.observedScrollContentActivationPoint = observedScrollContentActivationPoint
            self.scrollInventory = scrollInventory
        }
    }

    // MARK: - Fingerprint

    private struct SemanticElementFingerprint: Codable, Hashable {
        let heistId: HeistId
        let description: String
        let label: String?
        let value: String?
        let identifier: String?
        let hint: String?
        let traits: [String]
        let respondsToUserInteraction: Bool
        let customContent: [SemanticCustomContentFingerprint]
        let rotors: [String]
    }

    private struct SemanticCustomContentFingerprint: Codable, Hashable {
        let label: String
        let value: String
        let isImportant: Bool
    }

    private static func semanticElementFingerprint(_ entry: Element) -> SemanticElementFingerprint {
        let element = entry.element
        let customContent = element.customContent
            .filter { !$0.label.isEmpty || !$0.value.isEmpty }
            .map {
                SemanticCustomContentFingerprint(
                    label: $0.label,
                    value: $0.value,
                    isImportant: $0.isImportant
                )
            }
        return SemanticElementFingerprint(
            heistId: entry.heistId,
            description: element.description,
            label: element.label,
            value: element.value,
            identifier: element.identifier,
            hint: element.hint,
            traits: element.traits.heistTraitNames,
            respondsToUserInteraction: element.respondsToUserInteraction,
            customContent: customContent,
            rotors: element.customRotors.map(\.name).filter { !$0.isEmpty }
        )
    }

    private static func stableSemanticHashData<T: Encodable>(_ value: T, encoder: JSONEncoder) -> Data {
        switch Result(catching: { try encoder.encode(value) }) {
        case .success(let data):
            return data
        case .failure(let error):
            preconditionFailure("Stable semantic screen hash payload failed to encode: \(error)")
        }
    }
}

#endif // DEBUG
#endif // canImport(UIKit)
