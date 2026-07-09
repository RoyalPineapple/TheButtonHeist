import AccessibilitySnapshotModel
import ThePlans

public extension AccessibilityContainer {
    var accessibilityContainerKind: AccessibilityContainerKind {
        containerPredicateFacts.type
    }

    var containerPredicateLabel: String? {
        containerPredicateFacts.label
    }

    var containerPredicateValue: String? {
        containerPredicateFacts.value
    }

    var containerPredicateIdentifier: String? {
        containerPredicateFacts.identifier
    }

    var containerPredicateFacts: ContainerPredicateFacts {
        let actions = Set(customActions.lazy.map(\.name).filter { !$0.isEmpty }.map(ElementAction.custom))
        let kind: AccessibilityContainerKind
        let label: String?
        let value: String?
        let rowCount: Int?
        let columnCount: Int?
        switch type {
        case .none:
            kind = .none
            label = nil
            value = nil
            rowCount = nil
            columnCount = nil
        case .semanticGroup(let semanticLabel, let semanticValue):
            kind = .semanticGroup
            label = semanticLabel
            value = semanticValue
            rowCount = nil
            columnCount = nil
        case .list:
            kind = .list
            label = nil
            value = nil
            rowCount = nil
            columnCount = nil
        case .landmark:
            kind = .landmark
            label = nil
            value = nil
            rowCount = nil
            columnCount = nil
        case .dataTable(let tableRowCount, let tableColumnCount):
            kind = .dataTable
            label = nil
            value = nil
            rowCount = tableRowCount
            columnCount = tableColumnCount
        case .tabBar:
            kind = .tabBar
            label = nil
            value = nil
            rowCount = nil
            columnCount = nil
        }
        return ContainerPredicateFacts(
            type: kind,
            label: label,
            value: value,
            identifier: identifier,
            rowCount: rowCount,
            columnCount: columnCount,
            isModalBoundary: isModalBoundary,
            isScrollable: isScrollable,
            actions: actions
        )
    }
}
