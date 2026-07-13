import AccessibilitySnapshotModel
import ThePlans

public extension AccessibilityContainer {
    var containerPredicateFacts: ContainerPredicateFacts {
        let actions = Set(customActions.lazy.map(\.name).filter { !$0.isEmpty }.map(ElementAction.custom))
        let role: ContainerPredicateRoleFacts
        switch type {
        case .none:
            role = .none
        case .scrollable:
            role = .none
        case .semanticGroup(let semanticLabel, let semanticValue):
            role = .semanticGroup(label: semanticLabel, value: semanticValue)
        case .list:
            role = .list
        case .landmark:
            role = .landmark
        case .dataTable(let tableRowCount, let tableColumnCount, _):
            role = .dataTable(rowCount: tableRowCount, columnCount: tableColumnCount)
        case .tabBar:
            role = .tabBar
        case .series:
            role = .series
        }
        return ContainerPredicateFacts(
            role: role,
            identifier: identifier,
            isModalBoundary: isModalBoundary,
            isScrollable: isScrollable,
            actions: actions
        )
    }
}
