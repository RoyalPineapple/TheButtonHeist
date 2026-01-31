import ProjectDescription

let project = Project(
    name: "TestApp",
    targets: [
        .target(
            name: "AccessibilityTestApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.accra.testapp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "A11y Test App",
                "NSLocalNetworkUsageDescription": "This app uses local network to communicate with the accessibility inspector.",
                "NSBonjourServices": ["_a11ybridge._tcp"],
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [
                .project(target: "AccessibilityBridgeProtocol", path: ".."),
                .project(target: "AccessibilityBridgeServer", path: ".."),
            ]
        ),
    ]
)
