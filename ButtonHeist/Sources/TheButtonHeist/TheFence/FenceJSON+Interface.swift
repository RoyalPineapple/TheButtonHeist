import Foundation

import TheScore

struct PublicInterfaceResponse: Encodable {
    let status = PublicResponseStatus.ok
    let detail: String
    let interface: PublicInterface

    init(interface: Interface, detail: InterfaceDetail, profile: ProjectionProfile = .summary) {
        let projectionProfile = ProjectionProfile(
            kind: detail == .full ? .full : profile.kind,
            limits: profile.limits
        )
        self.init(projection: InterfaceProjection(interface: interface, profile: projectionProfile))
    }

    init(projection: InterfaceProjection) {
        self.detail = projection.detail.rawValue
        self.interface = PublicInterface(projection: projection)
    }
}

struct PublicInterface: Encodable {
    let timestamp: String
    let screenDescription: String
    let screenId: String?
    let screenActions: [String]?
    let rendering: PublicInterfaceRendering
    let diagnostics: InterfaceDiagnostics?
    let navigation: PublicNavigation
    let tree: [PublicTreeNode]

    init(
        interface: Interface,
        detail: InterfaceDetail,
        visibleElementBudget: Int = ButtonHeistRuntimeKnobs.current.visibleElementBudget,
        totalNodeBudget: Int = ButtonHeistRuntimeKnobs.current.totalNodeBudget
    ) {
        let profile = ProjectionProfile(
            kind: detail == .full ? .full : .summary,
            limits: .current(
                visibleElementBudget: visibleElementBudget,
                totalNodeBudget: totalNodeBudget
            )
        )
        self.init(projection: InterfaceProjection(interface: interface, profile: profile))
    }

    init(projection: InterfaceProjection) {
        let formatter = ISO8601DateFormatter()
        self.timestamp = formatter.string(from: projection.timestamp)
        self.screenDescription = projection.screenDescription
        self.screenId = projection.screenId
        let screenActions = projection.screenActions.map(\.rawValue)
        self.screenActions = screenActions.isEmpty ? nil : screenActions
        self.rendering = PublicInterfaceRendering(projection: projection.rendering)
        self.diagnostics = projection.diagnostics
        self.navigation = PublicNavigation(projection: projection.navigation)
        self.tree = projection.tree.map { PublicTreeNode(projection: $0, detail: projection.detail) }
    }
}

struct PublicNavigation: Encodable {
    let screenTitle: String?
    let backButton: PublicNavigationItem?
    let tabBarItems: [PublicTabBarItem]?

    init(projection: InterfaceNavigationProjection) {
        self.screenTitle = projection.screenTitle
        self.backButton = projection.backButton.map(PublicNavigationItem.init(projection:))
        let tabBarItems = projection.tabBarItems.map(PublicTabBarItem.init(projection:))
        self.tabBarItems = tabBarItems.isEmpty ? nil : tabBarItems
    }
}

struct PublicNavigationItem: Encodable {
    let label: String?
    let value: String?

    init(projection: NavigationItemProjection) {
        self.label = projection.label
        self.value = projection.value
    }
}

struct PublicTabBarItem: Encodable {
    let label: String?
    let value: String?
    let selected: Bool?

    init(projection: TabBarItemProjection) {
        self.label = projection.label
        self.value = projection.value
        self.selected = projection.selected ? true : nil
    }
}
