import Foundation

import AccessibilitySnapshotModel
import TheScore

struct PublicContainer: Encodable {
    let type: String
    let label: String?
    let value: String?
    let identifier: String?
    let rowCount: Int?
    let columnCount: Int?
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
            observedElementCount: projection.observedElementCount
        )
        self.type = fields.type
        self.label = fields.label
        self.value = fields.value
        self.identifier = fields.identifier
        self.rowCount = fields.rowCount
        self.columnCount = fields.columnCount
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

    private static func fields(
        for container: AccessibilityContainer,
        children: [PublicTreeNode],
        observedElementCount: Int?
    ) -> Fields {
        switch container.type {
        case .semanticGroup(let label, let value, let identifier):
            return Fields(type: "semanticGroup", label: label, value: value, identifier: identifier)
        case .list:
            return Fields(type: "list")
        case .landmark:
            return Fields(type: "landmark")
        case .dataTable(let rowCount, let columnCount):
            return Fields(type: "dataTable", rowCount: rowCount, columnCount: columnCount)
        case .tabBar:
            return Fields(type: "tabBar")
        case .scrollable(let contentSize):
            return scrollableFields(
                contentSize: contentSize,
                frame: container.frame,
                children: children,
                observedElementCount: observedElementCount
            )
        }
    }

    private static func scrollableFields(
        contentSize: AccessibilitySize,
        frame: AccessibilityRect,
        children: [PublicTreeNode],
        observedElementCount: Int?
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
            type: "scrollable",
            contentWidth: contentWidth,
            contentHeight: contentHeight,
            scrollAxis: scrollAxis.rawValue,
            pageScrollsX: horizontalPageScrolls > 0 ? horizontalPageScrolls : nil,
            pageScrollsY: verticalPageScrolls > 0 ? verticalPageScrolls : nil,
            observedElementCount: observedElementCount ?? children.reduce(0) { $0 + $1.elementCount }
        )
    }

    private struct Fields {
        let type: String
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
            type: String,
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
