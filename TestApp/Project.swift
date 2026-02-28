import ProjectDescription

let copyResourceBundleScript: TargetScript = .post(
    script: """
    BUNDLE="$BUILT_PRODUCTS_DIR/AccessibilitySnapshot_AccessibilitySnapshotParser.bundle"
    if [ -d "$BUNDLE" ]; then
        cp -R "$BUNDLE" "$CODESIGNING_FOLDER_PATH/"
    fi
    """,
    name: "Copy AccessibilitySnapshotParser Resources",
    basedOnDependencyAnalysis: false
)

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
            scripts: [copyResourceBundleScript],
            dependencies: [
                .project(target: "TheScore", path: ".."),
                .project(target: "TheInsideJob", path: ".."),
            ],
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": "Y4XC6NM5DD",
            ])
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
            scripts: [copyResourceBundleScript],
            dependencies: [
                .project(target: "TheScore", path: ".."),
                .project(target: "TheInsideJob", path: ".."),
            ],
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": "Y4XC6NM5DD",
            ])
        ),
    ]
)
