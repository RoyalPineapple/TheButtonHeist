import ProjectDescription

public extension Project {
    /// Creates a multi-platform framework
    static func framework(
        name: String,
        destinations: Destinations,
        dependencies: [TargetDependency] = []
    ) -> Project {
        return Project(
            name: name,
            targets: [
                .target(
                    name: name,
                    destinations: destinations,
                    product: .framework,
                    bundleId: "com.buttonheist.\(name.lowercased())",
                    deploymentTargets: .multiplatform(iOS: "17.0", macOS: "14.0"),
                    infoPlist: .default,
                    sources: ["Sources/**"],
                    dependencies: dependencies
                ),
            ]
        )
    }

    /// Creates an iOS or macOS app
    static func app(
        name: String,
        destinations: Destinations,
        deploymentTargets: DeploymentTargets,
        sources: SourceFilesList,
        resources: ResourceFileElements? = nil,
        dependencies: [TargetDependency] = []
    ) -> Project {
        return Project(
            name: name,
            targets: [
                .target(
                    name: name,
                    destinations: destinations,
                    product: .app,
                    bundleId: "com.buttonheist.\(name.lowercased())",
                    deploymentTargets: deploymentTargets,
                    infoPlist: .extendingDefault(with: [:]),
                    sources: sources,
                    resources: resources,
                    dependencies: dependencies
                ),
            ]
        )
    }
}
