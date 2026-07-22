import Foundation

import TheScore

struct PublicInterfaceResponse: Encodable {
    let status = PublicResponseStatus.ok
    let detail: String
    let interface: InterfaceProjection

    init(interface: Interface, detail: InterfaceDetail, profile: ProjectionProfile = .summary) {
        self.init(projection: InterfaceProjection(
            interface: interface,
            profile: ProjectionProfile(
                kind: detail == .full ? .full : profile.kind,
                limits: profile.limits
            )
        ))
    }

    init(projection: InterfaceProjection) {
        self.detail = projection.detail.rawValue
        self.interface = projection
    }
}

extension InterfaceProjection: Encodable {
    private enum CodingKeys: String, CodingKey {
        case timestamp, screenDescription, screenId, screenActions, rendering, diagnostics, navigation, tree
    }

    func encode(to encoder: Encoder) throws {
        let formatter = ISO8601DateFormatter()
        let actionNames = screenActions.map(\.rawValue)
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatter.string(from: timestamp), forKey: .timestamp)
        try container.encode(screenDescription, forKey: .screenDescription)
        try container.encodeIfPresent(screenId, forKey: .screenId)
        try container.encodeIfPresent(actionNames.isEmpty ? nil : actionNames, forKey: .screenActions)
        try container.encode(rendering, forKey: .rendering)
        try container.encodeIfPresent(diagnostics, forKey: .diagnostics)
        try container.encode(navigation, forKey: .navigation)
        try container.encode(tree, forKey: .tree)
    }
}

extension InterfaceNavigationProjection: Encodable {
    private enum CodingKeys: String, CodingKey {
        case screenTitle, backButton, tabBarItems
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(screenTitle, forKey: .screenTitle)
        try container.encodeIfPresent(backButton, forKey: .backButton)
        try container.encodeIfPresent(tabBarItems.isEmpty ? nil : tabBarItems, forKey: .tabBarItems)
    }
}

extension NavigationItemProjection: Encodable {
    private enum CodingKeys: String, CodingKey {
        case label, value
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
    }
}

extension TabBarItemProjection: Encodable {
    private enum CodingKeys: String, CodingKey {
        case label, value, selected
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(label, forKey: .label)
        try container.encodeIfPresent(value, forKey: .value)
        try container.encodeIfPresent(selected ? true : nil, forKey: .selected)
    }
}
