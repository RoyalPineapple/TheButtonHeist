import Foundation

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
    let snapshotQuality: PublicSnapshotQuality
    let navigation: PublicNavigation
    let tree: [PublicTreeNode]

    init(
        interface: Interface,
        detail: InterfaceDetail,
        visibleElementBudget: Int = ButtonHeistRuntimeKnobs.current.visibleElementBudget,
        totalNodeBudget: Int = ButtonHeistRuntimeKnobs.current.totalNodeBudget
    ) {
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.string(from: interface.timestamp)
        self.screenDescription = InterfaceSummary.screenDescription(for: interface)
        self.screenId = InterfaceSummary.screenId(for: interface)
        self.navigation = PublicNavigation(interface: interface)
        let counter = PublicIndexCounter()
        let projectionStats = PublicInterfaceProjectionStats(
            observedElementCount: interface.projectedElements.count
        )
        let totalNodeBudgetTracker = PublicElementBudgetTracker(budget: totalNodeBudget)
        self.tree = PublicTreeNode.nodes(
            from: interface.tree,
            detail: detail,
            counter: counter,
            visibleElementBudget: visibleElementBudget,
            totalNodeBudget: totalNodeBudgetTracker,
            projectionStats: projectionStats,
            elementAnnotations: interface.annotations.elementByPath,
            containerAnnotations: interface.annotations.containerByPath
        )
        self.snapshotQuality = projectionStats.snapshotQuality(
            visibleElementBudget: visibleElementBudget,
            totalNodeBudget: totalNodeBudget,
            totalNodeBudgetHit: totalNodeBudgetTracker.wasLimited
        )
    }
}

struct PublicNavigation: Encodable {
    let screenTitle: String?
    let backButton: PublicNavigationItem?
    let tabBarItems: [PublicTabBarItem]?

    init(interface: Interface) {
        let elements = interface.projectedElements
        self.screenTitle = InterfaceSummary.screenTitle(for: interface)
        self.backButton = elements
            .first(where: { $0.traits.contains(.backButton) })
            .map { PublicNavigationItem(element: $0) }

        let tabBarItems = elements
            .filter { $0.traits.contains(.tabBarItem) }
            .map(PublicTabBarItem.init(element:))
        self.tabBarItems = tabBarItems.isEmpty ? nil : tabBarItems
    }
}

struct PublicNavigationItem: Encodable {
    let label: String?
    let value: String?

    init(element: HeistElement) {
        self.label = element.label
        self.value = element.value
    }
}

struct PublicTabBarItem: Encodable {
    let label: String?
    let value: String?
    let selected: Bool?

    init(element: HeistElement) {
        self.label = element.label
        self.value = element.value
        self.selected = element.traits.contains(.selected) ? true : nil
    }
}
