import Foundation
import AccessibilitySnapshotModel

// MARK: - Interface

/// Position of a node in an accessibility hierarchy forest.
///
/// Paths are root-relative child indexes. The first root is `[0]`; its second
/// child is `[0, 1]`. They are capture-local, not durable identities.
public struct TreePath: Codable, Equatable, Hashable, Sendable {
    public let indices: [Int]

    public init(_ indices: [Int]) {
        self.indices = indices
    }

    public static let root = TreePath([])

    public func appending(_ index: Int) -> TreePath {
        TreePath(indices + [index])
    }
}

extension TreePath: Comparable {
    public static func < (lhs: TreePath, rhs: TreePath) -> Bool {
        for (left, right) in zip(lhs.indices, rhs.indices) where left != right {
            return left < right
        }
        return lhs.indices.count < rhs.indices.count
    }
}

/// Button Heist metadata attached to one parser element.
///
/// `AccessibilityElement` is the accessibility fact. These annotations are
/// BH affordances derived from a parse: targeting handle plus supported action
/// names. They are keyed by capture-local tree path so the accessibility tree
/// itself stays full-fidelity and unmodified.
public struct InterfaceElementAnnotation: Codable, Equatable, Hashable, Sendable {
    public let path: TreePath
    public let heistId: HeistId
    public let actions: [ElementAction]

    public init(path: TreePath, heistId: HeistId, actions: [ElementAction]) {
        self.path = path
        self.heistId = heistId
        self.actions = actions
    }
}

/// Button Heist metadata attached to one parser container.
///
/// Container type, modal state, and geometry live on `AccessibilityContainer`.
/// The only BH addition is the capture-local stable id used for subtree
/// targeting and tree-diff references.
public struct InterfaceContainerAnnotation: Codable, Equatable, Hashable, Sendable {
    public let path: TreePath
    public let stableId: HeistContainer?
    public let actions: [ElementAction]

    public init(path: TreePath, stableId: HeistContainer?, actions: [ElementAction] = []) {
        self.path = path
        self.stableId = stableId
        self.actions = actions
    }
}

/// Button Heist annotations for an `AccessibilityHierarchy` capture.
public struct InterfaceAnnotations: Codable, Equatable, Hashable, Sendable {
    public static let empty = InterfaceAnnotations()

    public let elements: [InterfaceElementAnnotation]
    public let containers: [InterfaceContainerAnnotation]

    public init(
        elements: [InterfaceElementAnnotation] = [],
        containers: [InterfaceContainerAnnotation] = []
    ) {
        self.elements = elements
        self.containers = containers
    }

    public var elementByPath: [TreePath: InterfaceElementAnnotation] {
        Dictionary(elements.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
    }

    public var containerByPath: [TreePath: InterfaceContainerAnnotation] {
        Dictionary(containers.map { ($0.path, $0) }, uniquingKeysWith: { _, latest in latest })
    }
}

/// A snapshot of the current accessibility interface returned by the server.
///
/// The wire shape carries the parser's full-fidelity `AccessibilityHierarchy`
/// plus Button Heist annotations. There is no parallel lossy tree on the wire;
/// `elements` is a projection for matching and formatting.
public struct Interface: Codable, Equatable, Sendable {
    public let timestamp: Date
    public let tree: [AccessibilityHierarchy]
    public let annotations: InterfaceAnnotations

    // MARK: - Computed Properties

    /// Button Heist element projection in VoiceOver traversal order.
    ///
    /// Computed from `tree + annotations`; not stored as a second source of
    /// truth on the wire.
    public var elements: [HeistElement] {
        let annotationsByPath = annotations.elementByPath
        return tree.pathIndexedElements.map { element, path, _ in
            HeistElement(
                accessibilityElement: element,
                annotation: annotationsByPath[path]
            )
        }
    }

    /// Deterministic one-line screen summary built from element metadata.
    /// Format: "{screen name} — {interactive element counts}"
    public var screenDescription: String {
        Self.buildScreenDescription(from: elements)
    }

    /// Slugified screen name for machine use (e.g. "controls_demo").
    /// Derived from the topmost header element's label.
    public var screenId: String? {
        slugify(Self.primaryHeaderLabel(from: elements))
    }

    /// Structured navigation context extracted from element traits.
    /// Provides screen title, back button, and tab bar items with heistIds
    /// so agents can orient and navigate without scanning the element list.
    public var navigation: NavigationContext {
        Self.buildNavigation(from: elements)
    }

    public init(
        timestamp: Date,
        tree: [AccessibilityHierarchy],
        annotations: InterfaceAnnotations = .empty
    ) {
        self.timestamp = timestamp
        self.tree = tree
        self.annotations = annotations
    }

    public func annotations(
        forSubtree node: AccessibilityHierarchy,
        originalPath: TreePath,
        rootPath: TreePath
    ) -> InterfaceAnnotations {
        let elementsByPath = annotations.elementByPath
        let elements = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceElementAnnotation? in
            guard case .element = node else { return nil }
            let relativePath = Array(newPath.indices.dropFirst(rootPath.indices.count))
            let oldPath = TreePath(originalPath.indices + relativePath)
            guard let annotation = elementsByPath[oldPath] else { return nil }
            return InterfaceElementAnnotation(
                path: newPath,
                heistId: annotation.heistId,
                actions: annotation.actions
            )
        }
        let containersByPath = annotations.containerByPath
        let containers = node.compactMapSubtrees(path: rootPath) { node, newPath -> InterfaceContainerAnnotation? in
            guard case .container = node else { return nil }
            let relativePath = Array(newPath.indices.dropFirst(rootPath.indices.count))
            let oldPath = TreePath(originalPath.indices + relativePath)
            guard let annotation = containersByPath[oldPath] else { return nil }
            return InterfaceContainerAnnotation(
                path: newPath,
                stableId: annotation.stableId,
                actions: annotation.actions
            )
        }
        return InterfaceAnnotations(elements: elements, containers: containers)
    }

    // MARK: - Navigation Context

    static func buildNavigation(from elements: [HeistElement]) -> NavigationContext {
        let screenTitle = Self.primaryHeaderLabel(from: elements)

        let backButton = elements
            .first(where: { $0.traits.contains(.backButton) })
            .map { NavigationContext.NavigationItem(heistId: $0.heistId, label: $0.label, value: $0.value) }

        let tabBarItems = elements
            .filter { $0.traits.contains(.tabBarItem) }
            .map { element in
                NavigationContext.TabBarItem(
                    heistId: element.heistId,
                    label: element.label,
                    value: element.value,
                    selected: element.traits.contains(.selected)
                )
            }

        return NavigationContext(
            screenTitle: screenTitle,
            backButton: backButton,
            tabBarItems: tabBarItems.isEmpty ? nil : tabBarItems
        )
    }

    // MARK: - Deterministic Screen Description

    /// Build a one-line screen summary from element metadata.
    static func buildScreenDescription(from elements: [HeistElement]) -> String {
        let screenName = Self.primaryHeaderLabel(from: elements)

        var textFields = 0
        var buttons = 0
        var switches = 0
        var sliders = 0
        var searchFields = 0
        var links = 0
        var secureFields = 0

        for element in elements {
            let traits = element.traits
            if traits.contains(.secureTextField) {
                secureFields += 1
            } else if traits.contains(.textEntry) {
                textFields += 1
            } else if traits.contains(.searchField) {
                searchFields += 1
            } else if traits.contains(.switchButton) {
                switches += 1
            } else if traits.contains(.adjustable) {
                sliders += 1
            } else if traits.contains(.link) {
                links += 1
            } else if traits.contains(.button) && !traits.contains(.backButton) {
                buttons += 1
            }
        }

        var parts: [String] = []
        if textFields > 0 { parts.append("\(textFields) text field\(textFields == 1 ? "" : "s")") }
        if secureFields > 0 { parts.append("\(secureFields) password field\(secureFields == 1 ? "" : "s")") }
        if searchFields > 0 { parts.append("\(searchFields) search field\(searchFields == 1 ? "" : "s")") }
        if buttons > 0 { parts.append("\(buttons) button\(buttons == 1 ? "" : "s")") }
        if switches > 0 { parts.append("\(switches) toggle\(switches == 1 ? "" : "s")") }
        if sliders > 0 { parts.append("\(sliders) slider\(sliders == 1 ? "" : "s")") }
        if links > 0 { parts.append("\(links) link\(links == 1 ? "" : "s")") }

        let summary = parts.joined(separator: ", ")

        if let name = screenName, !summary.isEmpty {
            return "\(name) — \(summary)"
        } else if let name = screenName {
            return name
        } else if !summary.isEmpty {
            return summary
        } else {
            return "\(elements.count) elements"
        }
    }

    private static func primaryHeaderLabel(from elements: [HeistElement]) -> String? {
        elements
            .enumerated()
            .compactMap { index, element -> (index: Int, element: HeistElement)? in
                guard element.traits.contains(.header), element.label != nil else { return nil }
                return (index, element)
            }
            .min { left, right in
                if left.element.frameY != right.element.frameY { return left.element.frameY < right.element.frameY }
                if left.element.frameX != right.element.frameX { return left.element.frameX < right.element.frameX }
                return left.index < right.index
            }?
            .element
            .label
    }
}

// MARK: - Navigation Context

/// Structured navigation context derived from element traits.
/// Gives agents immediate orientation — screen title, back button, and tab bar —
/// with heistIds for direct activation.
public struct NavigationContext: Codable, Equatable, Sendable {
    public struct NavigationItem: Codable, Equatable, Sendable {
        public let heistId: HeistId
        public let label: String?
        public let value: String?

        public init(heistId: HeistId, label: String?, value: String?) {
            self.heistId = heistId
            self.label = label
            self.value = value
        }
    }

    public struct TabBarItem: Codable, Equatable, Sendable {
        public let heistId: HeistId
        public let label: String?
        public let value: String?
        public let selected: Bool

        public init(heistId: HeistId, label: String?, value: String?, selected: Bool) {
            self.heistId = heistId
            self.label = label
            self.value = value
            self.selected = selected
        }
    }

    public let screenTitle: String?
    public let backButton: NavigationItem?
    public let tabBarItems: [TabBarItem]?

    public init(screenTitle: String?, backButton: NavigationItem?, tabBarItems: [TabBarItem]?) {
        self.screenTitle = screenTitle
        self.backButton = backButton
        self.tabBarItems = tabBarItems
    }
}
// MARK: - Parser Hierarchy Algebra

public extension AccessibilityHierarchy {
    func pathIndexedElements(path: TreePath = .root) -> [(element: AccessibilityElement, path: TreePath, traversalIndex: Int)] {
        switch self {
        case .element(let element, let traversalIndex):
            return [(element, path, traversalIndex)]
        case .container(_, let children):
            return children.enumerated().flatMap { index, child in
                child.pathIndexedElements(path: path.appending(index))
            }
        }
    }

    func folded<Result>(
        onElement: (AccessibilityElement, Int) -> Result,
        onContainer: (AccessibilityContainer, [Result]) -> Result
    ) -> Result {
        switch self {
        case .element(let element, let traversalIndex):
            return onElement(element, traversalIndex)
        case .container(let container, let children):
            return onContainer(
                container,
                children.map { $0.folded(onElement: onElement, onContainer: onContainer) }
            )
        }
    }

    func compactMapSubtrees<Result>(
        path: TreePath = .root,
        _ transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) -> [Result] {
        var results: [Result] = []
        if let result = transform(self, path) {
            results.append(result)
        }
        if case .container(_, let children) = self {
            for (index, child) in children.enumerated() {
                results.append(contentsOf: child.compactMapSubtrees(path: path.appending(index), transform))
            }
        }
        return results
    }

}

public extension Array where Element == AccessibilityHierarchy {
    var pathIndexedElements: [(element: AccessibilityElement, path: TreePath, traversalIndex: Int)] {
        enumerated()
            .flatMap { index, root in root.pathIndexedElements(path: TreePath([index])) }
            .sorted {
                if $0.traversalIndex != $1.traversalIndex {
                    return $0.traversalIndex < $1.traversalIndex
                }
                return $0.path < $1.path
            }
    }

    func compactMapSubtrees<Result>(
        _ transform: (AccessibilityHierarchy, TreePath) -> Result?
    ) -> [Result] {
        enumerated().flatMap { index, root in
            root.compactMapSubtrees(path: TreePath([index]), transform)
        }
    }
}

public extension AccessibilityTraits {
    private static let heistKnownTraits: [(trait: AccessibilityTraits, name: String)] = [
        (.button, HeistTrait.button.rawValue),
        (.link, HeistTrait.link.rawValue),
        (.image, HeistTrait.image.rawValue),
        (.selected, HeistTrait.selected.rawValue),
        (.playsSound, HeistTrait.playsSound.rawValue),
        (.keyboardKey, HeistTrait.keyboardKey.rawValue),
        (.staticText, HeistTrait.staticText.rawValue),
        (.summaryElement, HeistTrait.summaryElement.rawValue),
        (.notEnabled, HeistTrait.notEnabled.rawValue),
        (.updatesFrequently, HeistTrait.updatesFrequently.rawValue),
        (.searchField, HeistTrait.searchField.rawValue),
        (.startsMediaSession, HeistTrait.startsMediaSession.rawValue),
        (.adjustable, HeistTrait.adjustable.rawValue),
        (.allowsDirectInteraction, HeistTrait.allowsDirectInteraction.rawValue),
        (.causesPageTurn, HeistTrait.causesPageTurn.rawValue),
        (.header, HeistTrait.header.rawValue),
        (.tabBar, HeistTrait.tabBar.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 17), HeistTrait.webContent.rawValue),
        (.textEntry, HeistTrait.textEntry.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 19), HeistTrait.pickerElement.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 20), HeistTrait.radioButton.rawValue),
        (.isEditing, HeistTrait.isEditing.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 22), HeistTrait.launchIcon.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 23), HeistTrait.statusBarElement.rawValue),
        (.secureTextField, HeistTrait.secureTextField.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 25), HeistTrait.inactive.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 26), HeistTrait.footer.rawValue),
        (.backButton, HeistTrait.backButton.rawValue),
        (.tabBarItem, HeistTrait.tabBarItem.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 29), HeistTrait.autoCorrectCandidate.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 30), HeistTrait.deleteKey.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 31), HeistTrait.selectionDismissesItem.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 32), HeistTrait.visited.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 34), HeistTrait.spacer.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 35), HeistTrait.tableIndex.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 36), HeistTrait.map.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 37), HeistTrait.textOperationsAvailable.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 38), HeistTrait.draggable.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 40), HeistTrait.popupButton.rawValue),
        (.textArea, HeistTrait.textArea.rawValue),
        (AccessibilityTraits(rawValue: UInt64(1) << 52), HeistTrait.menuItem.rawValue),
        (.switchButton, HeistTrait.switchButton.rawValue),
        (.alert, HeistTrait.alert.rawValue),
    ]

    static var knownTraitNames: Set<String> {
        Set(heistKnownTraits.map(\.name))
    }

    static func fromNames(_ names: [String]) -> AccessibilityTraits {
        var value: UInt64 = 0
        for name in names {
            if let known = heistKnownTraits.first(where: { $0.name == name }) {
                value |= known.trait.rawValue
            }
        }
        return AccessibilityTraits(rawValue: value)
    }

    var heistTraits: [HeistTrait] {
        namesIncludingUnknownBits.map { HeistTrait(rawValue: $0) ?? .unknown($0) }
    }

    var namesIncludingUnknownBits: [String] {
        var result: [String] = []
        var remaining = rawValue
        for (trait, name) in Self.heistKnownTraits where contains(trait) {
            result.append(name)
            remaining &= ~trait.rawValue
        }
        if remaining != 0 {
            result.append("unknown(0x\(String(remaining, radix: 16)))")
        }
        return result
    }
}
