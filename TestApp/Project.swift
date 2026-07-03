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
            name: "BH Demo",
            destinations: .iOS,
            product: .app,
            productName: "BHDemo",
            bundleId: "com.buttonheist.testapp",
            deploymentTargets: .iOS("17.0"),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
                "CFBundleName": "BH Demo",
                "CFBundleDisplayName": "BH Demo",
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
                "DEVELOPMENT_TEAM": "",
            ])
        ),
    ]
)
