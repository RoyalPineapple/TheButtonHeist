#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore
import ThePlans

import AccessibilitySnapshotParser

// MARK: - Semantic Screen

/// Durable settled-world UI state retained across exploration.
///
/// `SemanticScreen` contains targetable accessibility identity and value-only
/// reveal evidence. It must not hold UIKit objects, viewport geometry as live
/// authority, live activation points, or weak refs. Live action geometry is
/// acquired from `LiveCapture` for each operation.
struct SemanticScreen: Sendable, Equatable {
    let elements: [HeistId: Element]
    let containers: [TreePath: Container]

    static let empty = SemanticScreen(elements: [:], containers: [:])

    init(
        elements: [HeistId: Element],
        containers: [TreePath: Container] = [:]
    ) {
        self.elements = elements
        self.containers = containers
    }

    var heistIds: Set<HeistId> {
        Set(elements.keys)
    }

    func findElement(heistId: HeistId) -> Element? {
        elements[heistId]
    }

    /// Hash of semantic accessibility state. Deliberately excludes
    /// viewport-only facts like live object refs, visible ids, current scroll
    /// offset, and live geometry.
    var semanticHash: String {
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

    // MARK: - Element Entry

    /// Durable scroll-container membership derived while walking the hierarchy.
    ///
    /// This is semantic placement evidence, not live action geometry: it records
    /// the owning scroll container and the optional accessibility container index
    /// reported by UIKit. It deliberately cannot express an absolute scroll-content point.
    struct ScrollMembership: Sendable, Equatable {
        let containerPath: TreePath
        let index: Int?
    }

    /// Scroll-content coordinate captured for an element's activation point
    /// while that element was visible in its scroll view.
    ///
    /// This is reveal evidence only. It is not current screen geometry, and it
    /// must not be projected into wire `frame` / `activationPoint` fields for
    /// off-viewport elements.
    struct ObservedScrollContentActivationPoint: Sendable, Equatable {
        let point: ScrollContentPoint

        init?(_ point: CGPoint) {
            guard point.x.isFinite, point.y.isFinite else { return nil }
            self.point = ScrollContentPoint(point)
        }

        init?(_ point: ScrollContentPoint) {
            guard point.x.isFinite, point.y.isFinite else { return nil }
            self.point = point
        }
    }

    struct Element: Sendable, Equatable {
        let heistId: HeistId
        let scrollMembership: ScrollMembership?
        let observedScrollContentActivationPoint: ObservedScrollContentActivationPoint?
        /// Parsed accessibility identity/value retained in the settled world.
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
            scrollMembership: ScrollMembership?,
            observedScrollContentActivationPoint: ObservedScrollContentActivationPoint? = nil,
            element: AccessibilityElement
        ) {
            self.heistId = heistId
            self.scrollMembership = scrollMembership
            self.observedScrollContentActivationPoint = observedScrollContentActivationPoint
            self.element = element
        }
    }

    // MARK: - Container Entry

    /// Durable settled-world container identity and scroll inventory evidence.
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
                contentRect: contentFrame.map(ContentRect.init),
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
            rotors: element.customRotors.map { $0.name }.filter { !$0.isEmpty }
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
