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
        switch type {
        case .none:
            return ContainerPredicateFacts(
                type: .none,
                identifier: identifier,
                isModalBoundary: isModalBoundary,
                isScrollable: isScrollable,
                actions: actions
            )
        case .semanticGroup(let label, let value):
            return ContainerPredicateFacts(
                type: .semanticGroup,
                label: label,
                value: value,
                identifier: identifier,
                isModalBoundary: isModalBoundary,
                isScrollable: isScrollable,
                actions: actions
            )
        case .list:
            return ContainerPredicateFacts(
                type: .list,
                identifier: identifier,
                isModalBoundary: isModalBoundary,
                isScrollable: isScrollable,
                actions: actions
            )
        case .landmark:
            return ContainerPredicateFacts(
                type: .landmark,
                identifier: identifier,
                isModalBoundary: isModalBoundary,
                isScrollable: isScrollable,
                actions: actions
            )
        case .dataTable(let rowCount, let columnCount):
            return ContainerPredicateFacts(
                type: .dataTable,
                identifier: identifier,
                rowCount: rowCount,
                columnCount: columnCount,
                isModalBoundary: isModalBoundary,
                isScrollable: isScrollable,
                actions: actions
            )
        case .tabBar:
            return ContainerPredicateFacts(
                type: .tabBar,
                identifier: identifier,
                isModalBoundary: isModalBoundary,
                isScrollable: isScrollable,
                actions: actions
            )
        }
    }
}
