import ProjectDescription

let project = Project(
    name: "TestApp",
    targets: [
        // MARK: - SwiftUI Test App
        .target(
            name: "AccessibilityTestApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.buttonheist.testapp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "A11y SwiftUI",
                "NSLocalNetworkUsageDescription": "This app uses local network to communicate with the accessibility inspector.",
                "NSBonjourServices": ["_buttonheist._tcp"],
            ]),
            sources: ["Sources/**"],
            resources: ["Resources/**"],
            dependencies: [
                .project(target: "TheGoods", path: ".."),
                .project(target: "InsideMan", path: ".."),
            ]
        ),

        // MARK: - UIKit Test App
        .target(
            name: "UIKitTestApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.buttonheist.uikittestapp",
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
                "NSBonjourServices": ["_buttonheist._tcp"],
            ]),
            sources: ["UIKitSources/**"],
            resources: ["UIKitResources/**"],
            dependencies: [
                .project(target: "TheGoods", path: ".."),
                .project(target: "InsideMan", path: ".."),
            ]
        ),
    ]
)
