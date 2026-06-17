#if canImport(UIKit)
#if DEBUG
import CryptoKit
import UIKit

import TheScore

import AccessibilitySnapshotParser

// MARK: - Semantic Screen

/// Durable settled-world UI state retained across exploration.
///
/// `SemanticScreen` contains targetable accessibility identity and value-only
/// reveal evidence. It must not hold UIKit objects, viewport geometry as live
/// authority, activation points, or weak refs. Live action geometry is acquired
/// from `LiveCapture` for each operation.
struct SemanticScreen: Equatable {
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

    /// Content-space location derived while walking the hierarchy. This is
    /// durable settled-world evidence: the element's content origin and the
    /// scroll container that owns that coordinate space. It deliberately does
    /// not carry a UIKit object, frame, or activation point.
    struct ScrollContentLocation: Sendable, Equatable {
        let origin: CGPoint
        let scrollContainer: ContainerName
    }

    // `@unchecked Sendable` rationale: contains `AccessibilityElement`, whose
    // parser model is used only behind the main-actor stash at runtime.
    // swiftlint:disable:next agent_unchecked_sendable_no_comment
    struct Element: @unchecked Sendable, Equatable {
        let heistId: HeistId
        let scrollContentLocation: ScrollContentLocation?
        /// Parsed accessibility identity/value retained in the settled world.
        /// Do not treat its frame or activation point as live action geometry.
        let element: AccessibilityElement

        var contentSpaceOrigin: CGPoint? {
            scrollContentLocation?.origin
        }

        init(
            heistId: HeistId,
            scrollContentLocation: ScrollContentLocation?,
            element: AccessibilityElement
        ) {
            self.heistId = heistId
            self.scrollContentLocation = scrollContentLocation
            self.element = element
        }

        init(
            heistId: HeistId,
            contentSpaceOrigin: CGPoint?,
            scrollContainerName: ContainerName? = nil,
            element: AccessibilityElement
        ) {
            self.heistId = heistId
            self.scrollContentLocation = Self.scrollContentLocation(
                origin: contentSpaceOrigin,
                scrollContainer: scrollContainerName
            )
            self.element = element
        }

        private static func scrollContentLocation(
            origin: CGPoint?,
            scrollContainer: ContainerName?
        ) -> ScrollContentLocation? {
            guard let origin, let scrollContainer else { return nil }
            return ScrollContentLocation(origin: origin, scrollContainer: scrollContainer)
        }
    }

    // MARK: - Container Entry

    /// Durable settled-world container identity and content-space evidence.
    ///
    /// The path and content frame are capture-local semantic evidence used to
    /// derive a reveal plan. UIKit object refs and live activation geometry
    /// remain in `LiveCapture` and are acquired only at dispatch time.
    struct Container: Equatable {
        let container: AccessibilityContainer
        let path: TreePath
        let containerName: ContainerName?
        let contentFrame: CGRect?
        let scrollContentLocation: ScrollContentLocation?

        var contentSpaceOrigin: CGPoint? {
            scrollContentLocation?.origin
        }

        init(
            container: AccessibilityContainer,
            path: TreePath,
            containerName: ContainerName?,
            contentFrame: CGRect?,
            scrollContentLocation: ScrollContentLocation? = nil
        ) {
            self.container = container
            self.path = path
            self.containerName = containerName
            self.contentFrame = contentFrame
            self.scrollContentLocation = scrollContentLocation
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
