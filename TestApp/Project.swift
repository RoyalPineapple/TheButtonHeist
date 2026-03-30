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
    settings: .settings(base: [
        "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
    ]),
    targets: [
        // MARK: - Demo App
        .target(
            name: "AccessibilityTestApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.buttonheist.testapp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "BH Demo",
                "NSLocalNetworkUsageDescription": "This app uses local network to communicate with the accessibility inspector.",
                "NSBonjourServices": ["_buttonheist._tcp"],
                "InsideJobPort": 1455,
                "InsideJobToken": "INJECTED-TOKEN-12345",
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
                "DEVELOPMENT_TEAM": "",
            ])
        ),

        // MARK: - Research App (SPI harness, trait probes)
        .target(
            name: "ResearchApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.buttonheist.research",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "BH Research",
                "NSLocalNetworkUsageDescription": "This app uses local network to communicate with the accessibility inspector.",
                "NSBonjourServices": ["_buttonheist._tcp"],
                "InsideJobPort": 1457,
                "InsideJobToken": "INJECTED-TOKEN-12345",
            ]),
            sources: ["ResearchSources/**"],
            scripts: [copyResourceBundleScript],
            dependencies: [
                .project(target: "TheScore", path: ".."),
                .project(target: "TheInsideJob", path: ".."),
            ],
            settings: .settings(base: [
                "CODE_SIGN_STYLE": "Automatic",
                "DEVELOPMENT_TEAM": "",
            ])
        ),

        // MARK: - UIKit Demo App
        .target(
            name: "UIKitTestApp",
            destinations: .iOS,
            product: .app,
            bundleId: "com.buttonheist.uikittestapp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleDisplayName": "BH UIKit Demo",
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
                "DEVELOPMENT_TEAM": "",
            ])
        ),
    ]
)
