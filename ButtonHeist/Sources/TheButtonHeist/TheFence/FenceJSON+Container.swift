import Foundation

import AccessibilitySnapshotModel
import TheScore

struct PublicContainer: Encodable {
    let type: AccessibilityContainerKind
    let label: String?
    let value: String?
    let identifier: String?
    let rowCount: Int?
    let columnCount: Int?
    let actions: [String]?
    let contentWidth: Double?
    let contentHeight: Double?
    let scrollAxis: String?
    let pageScrollsX: Int?
    let pageScrollsY: Int?
    let observedElementCount: Int?
    let truncation: PublicSubtreeTruncation?
    let isModalBoundary: Bool?
    let containerName: String?
    let frameX: Double?
    let frameY: Double?
    let frameWidth: Double?
    let frameHeight: Double?
    let children: [PublicTreeNode]

    init(projection: InterfaceContainerProjection, detail: InterfaceDetail) {
        let children = projection.children.map { PublicTreeNode(projection: $0, detail: detail) }
        let fields = Self.fields(
            for: projection.container,
            children: children,
            observedElementCount: projection.observedElementCount,
            scrollInventory: projection.scrollInventory
        )
        self.type = fields.type
        self.label = fields.label
        self.value = fields.value
        self.identifier = fields.identifier
        self.rowCount = fields.rowCount
        self.columnCount = fields.columnCount
        self.actions = Self.actionNames(projection.container)
        self.contentWidth = fields.contentWidth
        self.contentHeight = fields.contentHeight
        self.scrollAxis = fields.scrollAxis
        self.pageScrollsX = fields.pageScrollsX
        self.pageScrollsY = fields.pageScrollsY
        self.observedElementCount = fields.observedElementCount
        self.truncation = projection.truncation.map(PublicSubtreeTruncation.init(projection:))
        self.isModalBoundary = projection.container.isModalBoundary ? true : nil
        self.containerName = projection.containerName
        self.children = children
        guard detail == .full else {
            self.frameX = nil
            self.frameY = nil
            self.frameWidth = nil
            self.frameHeight = nil
            return
        }
        self.frameX = Self.sanitizedDouble(projection.container.frame.origin.x)
        self.frameY = Self.sanitizedDouble(projection.container.frame.origin.y)
        self.frameWidth = Self.sanitizedDouble(projection.container.frame.size.width)
        self.frameHeight = Self.sanitizedDouble(projection.container.frame.size.height)
    }

    private static func sanitizedDouble(_ value: Double) -> Double {
        value.isFinite ? value : 0
    }

    private static func actionNames(_ container: AccessibilityContainer) -> [String]? {
        let actions = container.customActions.map(\.name).filter { !$0.isEmpty }
        return actions.isEmpty ? nil : actions
    }

    private static func fields(
        for container: AccessibilityContainer,
        children: [PublicTreeNode],
        observedElementCount: Int?,
        scrollInventory: ScrollInventory?
    ) -> Fields {
        var fields: Fields
        switch container.type {
        case .none:
            fields = Fields(type: .none, identifier: container.identifier)
        case .semanticGroup(let label, let value):
            fields = Fields(type: .semanticGroup, label: label, value: value, identifier: container.identifier)
        case .list:
            fields = Fields(type: .list, identifier: container.identifier)
        case .landmark:
            fields = Fields(type: .landmark, identifier: container.identifier)
        case .dataTable(let rowCount, let columnCount):
            fields = Fields(type: .dataTable, identifier: container.identifier, rowCount: rowCount, columnCount: columnCount)
        case .tabBar:
            fields = Fields(type: .tabBar, identifier: container.identifier)
        }

        if let scrollableContentSize = container.scrollableContentSize {
            fields.addScrollFields(
                contentSize: scrollableContentSize,
                frame: container.frame,
                children: children,
                observedElementCount: observedElementCount,
                scrollInventory: scrollInventory
            )
        }
        return fields
    }

    private static func scrollFields(
        contentSize: AccessibilitySize,
        frame: AccessibilityRect,
        children: [PublicTreeNode],
        observedElementCount: Int?,
        scrollInventory: ScrollInventory?
    ) -> Fields {
        let contentWidth = Self.sanitizedDouble(contentSize.width)
        let contentHeight = Self.sanitizedDouble(contentSize.height)
        let viewportWidth = Self.sanitizedDouble(frame.size.width)
        let viewportHeight = Self.sanitizedDouble(frame.size.height)
        let horizontalPageScrolls = ScrollContainerMetrics.estimatedHorizontalPageScrolls(
            contentWidth: contentWidth,
            viewportWidth: viewportWidth
        )
        let verticalPageScrolls = ScrollContainerMetrics.estimatedVerticalPageScrolls(
            contentHeight: contentHeight,
            viewportHeight: viewportHeight
        )
        let scrollAxis = ScrollContainerMetrics.axis(
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            viewportWidth: viewportWidth,
            viewportHeight: viewportHeight
        )
        return Fields(
            type: .none,
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            scrollAxis: scrollAxis.rawValue,
            pageScrollsX: horizontalPageScrolls > 0 ? horizontalPageScrolls : nil,
            pageScrollsY: verticalPageScrolls > 0 ? verticalPageScrolls : nil,
            observedElementCount: scrollInventory?.totalElementCount
                ?? observedElementCount
                ?? children.reduce(0) { $0 + $1.elementCount }
        )
    }

    private struct Fields {
        let type: AccessibilityContainerKind
        var label: String?
        var value: String?
        var identifier: String?
        var rowCount: Int?
        var columnCount: Int?
        var contentWidth: Double?
        var contentHeight: Double?
        var scrollAxis: String?
        var pageScrollsX: Int?
        var pageScrollsY: Int?
        var observedElementCount: Int?

        init(
            type: AccessibilityContainerKind,
            label: String? = nil,
            value: String? = nil,
            identifier: String? = nil,
            rowCount: Int? = nil,
            columnCount: Int? = nil,
            contentWidth: Double? = nil,
            contentHeight: Double? = nil,
            scrollAxis: String? = nil,
            pageScrollsX: Int? = nil,
            pageScrollsY: Int? = nil,
            observedElementCount: Int? = nil
        ) {
            self.type = type
            self.label = label
            self.value = value
            self.identifier = identifier
            self.rowCount = rowCount
            self.columnCount = columnCount
            self.contentWidth = contentWidth
            self.contentHeight = contentHeight
            self.scrollAxis = scrollAxis
            self.pageScrollsX = pageScrollsX
            self.pageScrollsY = pageScrollsY
            self.observedElementCount = observedElementCount
        }

        mutating func addScrollFields(
            contentSize: AccessibilitySize,
            frame: AccessibilityRect,
            children: [PublicTreeNode],
            observedElementCount: Int?,
            scrollInventory: ScrollInventory?
        ) {
            let scrollFields = PublicContainer.scrollFields(
                contentSize: contentSize,
                frame: frame,
                children: children,
                observedElementCount: observedElementCount,
                scrollInventory: scrollInventory
            )
            contentWidth = scrollFields.contentWidth
            contentHeight = scrollFields.contentHeight
            scrollAxis = scrollFields.scrollAxis
            pageScrollsX = scrollFields.pageScrollsX
            pageScrollsY = scrollFields.pageScrollsY
            self.observedElementCount = scrollFields.observedElementCount
        }
    }
}

struct PublicSubtreeTruncation: Encodable {
    let state = "truncated"
    let reasonCode = "scroll-subtree-element-budget"
    let observedElementCount: Int
    let renderedElementCount: Int
    let omittedElementCount: Int
    let visibleElementBudget: Int

    init(projection: InterfaceSubtreeTruncationProjection) {
        self.observedElementCount = projection.observedElementCount
        self.renderedElementCount = projection.renderedElementCount
        self.omittedElementCount = projection.omittedElementCount
        self.visibleElementBudget = projection.visibleElementBudget
    }
}
