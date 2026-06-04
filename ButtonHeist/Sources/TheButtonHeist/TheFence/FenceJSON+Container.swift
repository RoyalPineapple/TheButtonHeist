import CoreGraphics
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
    let isModalBoundary: Bool?
    let containerName: String?
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
        self.containerName = annotation?.containerName
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
