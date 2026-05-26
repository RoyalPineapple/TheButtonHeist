import Foundation
import CoreGraphics

import AccessibilitySnapshotModel
import TheScore

struct PublicInterfaceResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let detail: String
    let interface: PublicInterface

    init(interface: Interface, detail: InterfaceDetail) {
        self.detail = detail.rawValue
        self.interface = PublicInterface(interface: interface, detail: detail)
    }
}

struct PublicInterface: Encodable {
    let timestamp: String
    let screenDescription: String
    let screenId: String?
    let navigation: PublicNavigation
    let tree: [PublicTreeNode]

    init(interface: Interface, detail: InterfaceDetail) {
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.string(from: interface.timestamp)
        self.screenDescription = interface.screenDescription
        self.screenId = interface.screenId
        self.navigation = PublicNavigation(navigation: interface.navigation)
        let counter = PublicIndexCounter()
        self.tree = PublicTreeNode.nodes(
            from: interface.tree,
            detail: detail,
            counter: counter,
            elementAnnotations: interface.annotations.elementByPath,
            containerAnnotations: interface.annotations.containerByPath
        )
    }
}

struct PublicNavigation: Encodable {
    let screenTitle: String?
    let backButton: PublicNavigationItem?
    let tabBarItems: [PublicTabBarItem]?

    init(navigation: NavigationContext) {
        self.screenTitle = navigation.screenTitle
        self.backButton = navigation.backButton.map { PublicNavigationItem(item: $0) }
        self.tabBarItems = navigation.tabBarItems?.map { PublicTabBarItem(item: $0) }
    }
}

struct PublicNavigationItem: Encodable {
    let heistId: String
    let label: String?
    let value: String?

    init(item: NavigationContext.NavigationItem) {
        self.heistId = item.heistId
        self.label = item.label
        self.value = item.value
    }
}

struct PublicTabBarItem: Encodable {
    let heistId: String
    let label: String?
    let value: String?
    let selected: Bool?

    init(item: NavigationContext.TabBarItem) {
        self.heistId = item.heistId
        self.label = item.label
        self.value = item.value
        self.selected = item.selected ? true : nil
    }
}

final class PublicIndexCounter {
    var value = 0
}

enum PublicTreeNode: Encodable {
    case element(PublicElement)
    case container(PublicContainer)

    private enum CodingKeys: String, CodingKey {
        case element
        case container
    }

    static func nodes(
        from tree: [AccessibilityHierarchy],
        detail: InterfaceDetail,
        counter: PublicIndexCounter?,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> [PublicTreeNode] {
        tree.enumerated().map { index, node in
            Self.node(
                from: node,
                path: TreePath([index]),
                detail: detail,
                counter: counter,
                elementAnnotations: elementAnnotations,
                containerAnnotations: containerAnnotations
            )
        }
    }

    static func node(
        from node: AccessibilityHierarchy,
        path: TreePath,
        detail: InterfaceDetail,
        counter: PublicIndexCounter?,
        elementAnnotations: [TreePath: InterfaceElementAnnotation],
        containerAnnotations: [TreePath: InterfaceContainerAnnotation]
    ) -> PublicTreeNode {
        switch node {
        case .element(let element, _):
            let projected = HeistElement(
                accessibilityElement: element,
                annotation: elementAnnotations[path]
            )
            let order = counter?.value
            counter?.value += 1
            return .element(PublicElement(element: projected, detail: detail, order: order))
        case .container(let container, let children):
            let childNodes = children.enumerated().map { index, child in
                Self.node(
                    from: child,
                    path: path.appending(index),
                    detail: detail,
                    counter: counter,
                    elementAnnotations: elementAnnotations,
                    containerAnnotations: containerAnnotations
                )
            }
            return .container(PublicContainer(
                container: container,
                annotation: containerAnnotations[path],
                detail: detail,
                children: childNodes
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .element(let element):
            try container.encode(element, forKey: .element)
        case .container(let node):
            try container.encode(node, forKey: .container)
        }
    }
}

struct PublicElement: Encodable {
    let heistId: String
    let traits: [String]
    let actions: [String]?
    let rotors: [String]?
    let label: String?
    let value: String?
    let identifier: String?
    let hint: String?
    let customContent: PublicCustomContent?
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let activationPointX: Double?
    let activationPointY: Double?
    let order: Int?

    init(element: HeistElement, detail: InterfaceDetail, order: Int? = nil) {
        self.heistId = element.heistId
        self.traits = element.traits.map(\.rawValue)
        let meaningfulActions = FenceResponse.meaningfulActions(element)
        self.actions = meaningfulActions.isEmpty ? nil : meaningfulActions.map(\.description)
        self.rotors = element.rotors?.isEmpty == false ? element.rotors?.map { $0.name } : nil
        self.label = element.label
        self.value = element.value
        self.identifier = element.identifier
        self.order = order
        guard detail == .full else {
            self.hint = nil
            self.customContent = nil
            self.frameX = nil
            self.frameY = nil
            self.frameWidth = nil
            self.frameHeight = nil
            self.activationPointX = nil
            self.activationPointY = nil
            return
        }
        self.hint = element.hint
        self.customContent = element.customContent.map { PublicCustomContent(items: $0) }
        self.frameX = element.frameX
        self.frameY = element.frameY
        self.frameWidth = element.frameWidth
        self.frameHeight = element.frameHeight
        self.activationPointX = element.activationPointX
        self.activationPointY = element.activationPointY
    }
}

struct PublicCustomContent: Encodable {
    let important: [PublicCustomContentEntry]?
    let `default`: [PublicCustomContentEntry]?

    init(items: [HeistCustomContent]) {
        let importantItems = items.filter(\.isImportant)
        let defaultItems = items.filter { !$0.isImportant }
        self.important = importantItems.isEmpty ? nil : importantItems.map { PublicCustomContentEntry(item: $0) }
        self.default = defaultItems.isEmpty ? nil : defaultItems.map { PublicCustomContentEntry(item: $0) }
    }
}

struct PublicCustomContentEntry: Encodable {
    let label: String?
    let value: String?

    init(item: HeistCustomContent) {
        self.label = item.label.isEmpty ? nil : item.label
        self.value = item.value.isEmpty ? nil : item.value
    }
}

struct PublicContainer: Encodable {
    let type: String
    let label: String?
    let value: String?
    let identifier: String?
    let rowCount: Int?
    let columnCount: Int?
    let contentWidth: Double?
    let contentHeight: Double?
    let isModalBoundary: Bool?
    let stableId: String?
    let actions: [String]?
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let children: [PublicTreeNode]

    init(
        container: AccessibilityContainer,
        annotation: InterfaceContainerAnnotation?,
        detail: InterfaceDetail,
        children: [PublicTreeNode]
    ) {
        switch container.type {
        case .semanticGroup(let label, let value, let identifier):
            self.type = "semanticGroup"
            self.label = label
            self.value = value
            self.identifier = identifier
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = nil
            self.contentHeight = nil
        case .list:
            self.type = "list"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = nil
            self.contentHeight = nil
        case .landmark:
            self.type = "landmark"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = nil
            self.contentHeight = nil
        case .dataTable(let rowCount, let columnCount):
            self.type = "dataTable"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = rowCount
            self.columnCount = columnCount
            self.contentWidth = nil
            self.contentHeight = nil
        case .tabBar:
            self.type = "tabBar"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = nil
            self.contentHeight = nil
        case .scrollable(let contentSize):
            self.type = "scrollable"
            self.label = nil
            self.value = nil
            self.identifier = nil
            self.rowCount = nil
            self.columnCount = nil
            self.contentWidth = Self.sanitizedDouble(contentSize.width)
            self.contentHeight = Self.sanitizedDouble(contentSize.height)
        }
        self.isModalBoundary = container.isModalBoundary ? true : nil
        self.stableId = annotation?.stableId
        self.actions = annotation?.actions.isEmpty == false ? annotation?.actions.map(\.description) : nil
        self.children = children
        guard detail == .full else {
            self.frameX = nil
            self.frameY = nil
            self.frameWidth = nil
            self.frameHeight = nil
            return
        }
        self.frameX = Self.sanitizedDouble(container.frame.origin.x)
        self.frameY = Self.sanitizedDouble(container.frame.origin.y)
        self.frameWidth = Self.sanitizedDouble(container.frame.size.width)
        self.frameHeight = Self.sanitizedDouble(container.frame.size.height)
    }

    private static func sanitizedDouble(_ value: CGFloat) -> Double {
        value.isFinite ? Double(value) : 0
    }
}

struct PublicScreenshotResponse: FencePublicJSONResponse {
    let status = PublicStatus.ok
    let width: Double
    let height: Double
    let pngData: String?
    let interface: PublicInterface?
    let path: String?

    init(path: String?, payload: ScreenPayload, includePNGData: Bool, includeInterface: Bool) {
        self.width = payload.width
        self.height = payload.height
        self.pngData = includePNGData ? payload.pngData : nil
        self.interface = includeInterface ? PublicInterface(interface: payload.interface, detail: .full) : nil
        self.path = path
    }
}
