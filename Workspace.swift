import ProjectDescription

let workspace = Workspace(
    name: "ButtonHeist",
    projects: [
        ".",
        "TestApp",
    ],
    schemes: [
        .scheme(
            name: "TheInsideJobTests",
            buildAction: .buildAction(targets: [
                .project(path: ".", target: "TheInsideJobTests"),
                .project(path: ".", target: "TheInsideJob"),
.project(path: ".", target: "TheScore"),
                .project(path: "TestApp", target: "AccessibilityTestApp"),
            ]),
            testAction: .targets([
                .testableTarget(target: .project(path: ".", target: "TheInsideJobTests")),
            ])
        ),
    ]
)
