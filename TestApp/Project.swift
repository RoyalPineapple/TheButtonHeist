import ProjectDescription

let project = Project(
    name: "TestApp",
    targets: [
        // MARK: - SwiftUI Test App
        .target(
            name: "AccessibilityTestApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.accra.testapp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "A11y SwiftUI",
                "NSLocalNetworkUsageDescription": "This app uses local network to communicate with the accessibility inspector.",
                "NSBonjourServices": ["_a11ybridge._tcp"],
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [
                .project(target: "AccraCore", path: ".."),
                .project(target: "AccraHost", path: ".."),
            ]
        ),

        // MARK: - UIKit Test App
        .target(
            name: "UIKitTestApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.accra.uikittestapp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "A11y UIKit",
                "UIApplicationSceneManifest": [
                    "UIApplicationSupportsMultipleScenes": false,
                    "UISceneConfigurations": [
                        "UIWindowSceneSessionRoleApplication": [
                            [
                                "UISceneConfigurationName": "Default Configuration",
                                "UISceneDelegateClassName": "$(PRODUCT_MODULE_NAME).SceneDelegate",
                            ]
                        ]
                    ]
                ],
                "NSLocalNetworkUsageDescription": "This app uses local network to communicate with the accessibility inspector.",
                "NSBonjourServices": ["_a11ybridge._tcp"],
            ]),
            sources: ["UIKitSources/**"],
            resources: ["UIKitResources/**"],
            dependencies: [
                .project(target: "AccraCore", path: ".."),
                .project(target: "AccraHost", path: ".."),
            ]
        ),
    ]
)
