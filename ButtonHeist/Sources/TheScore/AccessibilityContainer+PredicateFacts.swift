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
        switch type {
        case .semanticGroup(let label, let value, let identifier):
            return ContainerPredicateFacts(
                type: .semanticGroup,
                label: label,
                value: value,
                identifier: identifier,
                isModalBoundary: isModalBoundary
            )
        case .list:
            return ContainerPredicateFacts(type: .list, isModalBoundary: isModalBoundary)
        case .landmark:
            return ContainerPredicateFacts(type: .landmark, isModalBoundary: isModalBoundary)
        case .dataTable(let rowCount, let columnCount):
            return ContainerPredicateFacts(
                type: .dataTable,
                rowCount: rowCount,
                columnCount: columnCount,
                isModalBoundary: isModalBoundary
            )
        case .tabBar:
            return ContainerPredicateFacts(type: .tabBar, isModalBoundary: isModalBoundary)
        case .scrollable:
            return ContainerPredicateFacts(type: .scrollable, isModalBoundary: isModalBoundary)
        }
    }
}
