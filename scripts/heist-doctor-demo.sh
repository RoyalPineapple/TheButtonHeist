#!/usr/bin/env bash
# Generate a small doctor-ready result pair and run heist-doctor.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="$REPO_ROOT/.rp1/work/heist-doctor-demo"
FORMAT="${BUTTONHEIST_DOCTOR_FORMAT:-human}"
KEEP_WORK=false

usage() {
    cat <<'EOF'
Usage: scripts/heist-doctor-demo.sh [options]

Options:
  --work-dir DIR  Directory for generated fixture package and results.
  --format FORMAT Doctor output format: human or json. Defaults to human.
  --keep-work     Leave the generated fixture package in place.
  -h, --help      Show this help.

The demo generates a last-passing Checkout result and a new-failing result
where Checkout has become Go to Checkout. Results are written through the same
HeistResultRecorder path used by tests and CI, then paired by fingerprint and
fed into heist-doctor.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --work-dir)
            WORK_DIR="${2:-}"
            [[ -n "$WORK_DIR" ]] || {
                echo "Error: --work-dir requires a value" >&2
                exit 2
            }
            shift 2
            ;;
        --format)
            FORMAT="${2:-}"
            [[ "$FORMAT" == "human" || "$FORMAT" == "json" ]] || {
                echo "Error: --format must be human or json" >&2
                exit 2
            }
            shift 2
            ;;
        --keep-work)
            KEEP_WORK=true
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

PACKAGE_DIR="$WORK_DIR/fixture-generator"
RESULTS_DIR="$WORK_DIR/results"

rm -rf "$WORK_DIR"
mkdir -p "$PACKAGE_DIR/Sources/DoctorDemoFixture" "$RESULTS_DIR"

cleanup() {
    if [[ "$KEEP_WORK" == false ]]; then
        rm -rf "$PACKAGE_DIR"
    fi
}
trap cleanup EXIT

cat > "$PACKAGE_DIR/Package.swift" <<SWIFT
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DoctorDemoFixture",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DoctorDemoFixture", targets: ["DoctorDemoFixture"]),
    ],
    dependencies: [
        .package(name: "ButtonHeist", path: "$REPO_ROOT"),
        .package(path: "$REPO_ROOT/submodules/AccessibilitySnapshotBH"),
    ],
    targets: [
        .executableTarget(
            name: "DoctorDemoFixture",
            dependencies: [
                .product(name: "ThePlans", package: "ButtonHeist"),
                .product(name: "TheScore", package: "ButtonHeist"),
                .product(name: "AccessibilitySnapshotModel", package: "AccessibilitySnapshotBH"),
            ]
        ),
    ]
)
SWIFT

cat > "$PACKAGE_DIR/Sources/DoctorDemoFixture/main.swift" <<'SWIFT'
import AccessibilitySnapshotModel
import Foundation
import ThePlans
import TheScore

@main
struct DoctorDemoFixture {
    static func main() throws {
        guard CommandLine.arguments.count == 2 else {
            throw FixtureError.message("usage: DoctorDemoFixture RESULTS_DIR")
        }

        let resultsDirectory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        try FileManager.default.createDirectory(at: resultsDirectory, withIntermediateDirectories: true)

        let target = AccessibilityTarget.predicate(.label("Checkout"))
        let plan = try HeistPlan(
            name: "doctorDemoCheckout",
            body: [.action(ActionStep(command: .activate(target)))]
        )
        let configuration = HeistResultRecordingConfiguration(
            rootDirectory: resultsDirectory,
            mode: .all
        )

        let lastPass = try result(
            outcome: .passed,
            target: target,
            before: menuInterface(primaryAction: "Checkout"),
            after: confirmationInterface()
        )
        let newFail = try result(
            outcome: .failed,
            target: target,
            before: menuInterface(primaryAction: "Go to Checkout"),
            after: nil
        )

        guard let passRecording = try HeistResultRecorder.write(
            lastPass,
            plan: plan,
            configuration: configuration
        ) else {
            throw FixtureError.message("failed to record passing result")
        }
        guard let failRecording = try HeistResultRecorder.write(
            newFail,
            plan: plan,
            configuration: configuration
        ) else {
            throw FixtureError.message("failed to record failing result")
        }

        print("last-pass=\(passRecording.url.path)")
        print("new-fail=\(failRecording.url.path)")
    }

    private static func result(
        outcome: ActionNodeFixture.Outcome,
        target: AccessibilityTarget,
        before: Interface,
        after: Interface?
    ) throws -> HeistResult {
        let trace = after
            .map { AccessibilityTrace(first: before).appending($0) }
            ?? AccessibilityTrace(first: before)
        guard let traceEvidence = AccessibilityTraceEvidence(trace: trace, completeness: .complete) else {
            throw FixtureError.message("failed to build trace evidence")
        }
        let actionResult: ActionResult
        switch outcome {
        case .passed:
            actionResult = .success(
                method: .activate,
                evidence: ActionResultSuccessEvidence(observation: .trace(traceEvidence))
            )
        case .failed:
            actionResult = .failure(
                method: .activate,
                errorKind: .elementNotFound,
                message: "No element matching \(target)",
                evidence: ActionResultFailureEvidence(observation: .trace(traceEvidence))
            )
        }
        let command = HeistActionCommand.activate(target)
        let evidence = HeistActionEvidence.dispatch(
            command: command,
            dispatchResult: actionResult
        )
        let node = ActionNodeFixture(
            command: command,
            outcome: outcome,
            evidence: evidence,
            failure: outcome == .failed
                ? HeistFailureDetail(
                    category: .targetResolution,
                    contract: "action dispatch succeeds",
                    observed: "No element matching \(target)",
                    expected: target.description
                )
                : nil
        )

        let fixture = ResultFixture(
            steps: [StepFixture(
                path: "$.body[0]",
                durationMs: 1,
                node: node
            )],
            durationMs: 1
        )
        return try HeistResultCodec.decode(JSONEncoder().encode(fixture))
    }

    private static func menuInterface(primaryAction: String) throws -> Interface {
        try interface(nodes: [
            container(children: [
                element(label: "Menu", traits: [.header], frameY: 0),
                element(label: "Greek Salad", traits: [.staticText], frameY: 50),
                element(label: "Margherita Pizza", traits: [.staticText], frameY: 94),
                element(label: "Items, 2", value: "US$23.50", traits: [.staticText], frameY: 138),
                element(label: primaryAction, traits: [.button], actions: [.activate], frameY: 190),
            ]),
        ])
    }

    private static func confirmationInterface() throws -> Interface {
        try interface(nodes: [
            container(children: [
                element(label: "Review Order", traits: [.header], frameY: 0),
                element(label: "Greek Salad", traits: [.staticText], frameY: 50),
                element(label: "Margherita Pizza", traits: [.staticText], frameY: 94),
                element(label: "Place Order", traits: [.button], actions: [.activate], frameY: 150),
            ]),
        ])
    }

    private static func interface(nodes: [FixtureNode]) throws -> Interface {
        var traversalIndex = 0
        var elementAnnotations: [InterfaceElementAnnotation] = []
        var containerAnnotations: [InterfaceContainerAnnotation] = []

        func convert(_ node: FixtureNode, path: TreePath) -> AccessibilityHierarchy {
            switch node {
            case .element(let element):
                let index = traversalIndex
                traversalIndex += 1
                elementAnnotations.append(InterfaceElementAnnotation(path: path, actions: element.actions))
                return .element(accessibilityElement(element), traversalIndex: index)
            case .container(let container, let children):
                containerAnnotations.append(InterfaceContainerAnnotation(path: path, containerName: nil))
                return .container(
                    container,
                    children: children.enumerated().map { offset, child in
                        convert(child, path: path.appending(offset))
                    }
                )
            }
        }

        let tree = nodes.enumerated().map { offset, node in
            convert(node, path: TreePath([offset]))
        }
        return try Interface(
            timestamp: Date(timeIntervalSince1970: 0),
            tree: tree,
            annotations: InterfaceAnnotations(
                elements: elementAnnotations,
                containers: containerAnnotations
            )
        )
    }

    private static func container(children: [FixtureNode]) -> FixtureNode {
        .container(
            AccessibilityContainer(
                type: .none,
                frame: AccessibilityRect(x: 0, y: 0, width: 320, height: 260)
            ),
            children
        )
    }

    private static func element(
        label: String,
        value: String? = nil,
        traits: [HeistTrait],
        actions: [ElementAction] = [],
        frameY: Double
    ) -> FixtureNode {
        .element(HeistElement(
            description: "\(label).",
            label: label,
            value: value,
            identifier: nil,
            traits: traits,
            frameX: 0,
            frameY: frameY,
            frameWidth: 280,
            frameHeight: 44,
            actions: actions
        ))
    }

    private static func accessibilityElement(_ element: HeistElement) -> AccessibilityElement {
        AccessibilityElement(
            description: element.description,
            label: element.label,
            value: element.value,
            traits: AccessibilityTraits.fromNames(element.traits.map(\.rawValue)),
            identifier: element.identifier,
            hint: element.hint,
            userInputLabels: nil,
            shape: .frame(AccessibilityRect(
                x: element.frameX,
                y: element.frameY,
                width: element.frameWidth,
                height: element.frameHeight
            )),
            activationPoint: AccessibilityPoint(
                x: element.activationPointX,
                y: element.activationPointY
            ),
            usesDefaultActivationPoint: true,
            customActions: [],
            customContent: [],
            customRotors: [],
            accessibilityLanguage: nil,
            respondsToUserInteraction: element.respondsToUserInteraction
        )
    }
}

private struct ResultFixture: Encodable {
    let steps: [StepFixture]
    let durationMs: Int
}

private struct StepFixture: Encodable {
    let path: String
    let durationMs: Int
    let node: ActionNodeFixture
}

private struct ActionNodeFixture: Encodable {
    enum NodeType: String, Encodable {
        case action
    }

    enum Outcome: String, Encodable {
        case passed
        case failed
    }

    let type: NodeType = .action
    let command: HeistActionCommand
    let outcome: Outcome
    let evidence: HeistActionEvidence?
    let failure: HeistFailureDetail?
    let children: [StepFixture] = []
}

private enum FixtureNode {
    case element(HeistElement)
    case container(AccessibilityContainer, [FixtureNode])
}

private enum FixtureError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let value):
            return value
        }
    }
}
SWIFT

echo "Generating doctor demo results..."
swift run --package-path "$PACKAGE_DIR" DoctorDemoFixture "$RESULTS_DIR"

echo
"$REPO_ROOT/scripts/heist-doctor-from-results.sh" \
    --last-pass-dir "$RESULTS_DIR" \
    --new-fail-dir "$RESULTS_DIR" \
    --format "$FORMAT"

echo
echo "Result artifacts: $RESULTS_DIR"
