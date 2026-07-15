#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
FIXTURE_REPO="$FIXTURE_ROOT/repo"
LINT_OUTPUT=""
LINT_STATUS=0

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

"$REPO_ROOT/scripts/check-bumper-rule-documentation.sh"

fail() {
    echo "FAIL: $*" >&2
    exit 1
}

copy_fixture_file() {
    local path="$1"
    mkdir -p "$FIXTURE_REPO/$(dirname "$path")"
    cp "$REPO_ROOT/$path" "$FIXTURE_REPO/$path"
}

run_lint() {
    set +e
    LINT_OUTPUT="$(
        BUTTONHEIST_SOURCE_ROOT="$FIXTURE_REPO" \
            "$REPO_ROOT/scripts/check-source-shape.sh" 2>&1
    )"
    LINT_STATUS=$?
    set -e
}

prepare_bumper_binary() {
    local binary_path

    if [[ -n "${BUMPER:-}" || -z "${BUMPER_BOWLING_PACKAGE_PATH:-}" ]]; then
        return
    fi

    swift build --package-path "$BUMPER_BOWLING_PACKAGE_PATH" --product bumper >/dev/null
    binary_path="$(swift build --package-path "$BUMPER_BOWLING_PACKAGE_PATH" --show-bin-path)/bumper"
    export BUMPER="$binary_path"
}

mkdir -p "$FIXTURE_REPO"
prepare_bumper_binary
copy_fixture_file "BumperBowling.swift"

while IFS= read -r source; do
    copy_fixture_file "${source#"$REPO_ROOT/"}"
done < <(find "$REPO_ROOT/.bumper" -type f -print | sort)

while IFS= read -r owner; do
    copy_fixture_file "$owner"
done < <(
    sed -n '/private let architectureCurrencyDeclarationOwners:/,/^]/p' \
        "$REPO_ROOT/.bumper/Sources/ButtonHeistCustomRules.swift" \
        | sed -n \
            -e 's/.*owner: "\([^"]*\)".*/\1/p' \
        | sort -u
)

mkdir -p \
    "$FIXTURE_REPO/ButtonHeistCLI/Sources/Support" \
    "$FIXTURE_REPO/ButtonHeist/Sources/ButtonHeistTesting/SourceShapeFixtures" \
    "$FIXTURE_REPO/ButtonHeist/Sources/ThePlans/SourceShapeFixtures" \
    "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/TheBurglar" \
    "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/TheStash" \
    "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/SourceShapeFixtures" \
    "$FIXTURE_REPO/ButtonHeist/Sources/TheScore/Core" \
    "$FIXTURE_REPO/ButtonHeist/Sources/TheScore/SourceShapeFixtures" \
    "$FIXTURE_REPO/TestApp/Sources"

cat > "$FIXTURE_REPO/ButtonHeistCLI/Sources/Support/SourceShapeFixtures.swift" <<'EOF'
var onActorIsolated: (@MainActor (Int) -> Void)?
var onSendable: (@Sendable (Int) -> Void)?

/// Mutable state is lock-protected in the real boundary type.
final class LockBackedFixture: @unchecked Sendable {} // swiftlint:disable:this agent_unchecked_sendable_no_comment

@MainActor enum ActorNamespaceFixture {} // swiftlint:disable:this agent_main_actor_value_type
EOF

cat > "$FIXTURE_REPO/TestApp/Sources/AccessibleFixture.swift" <<'EOF'
func configureAccessibleFixture(_ view: FixtureView) {
    view.accessibilityLabel = "Fixture"
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/SourceShapeFixtures/ObservationCommits.swift" <<'EOF'
func commitSettledVisibleObservation(_ proof: InterfaceObservationProof) {}
func commitSettledDiscoveryObservation(_ proof: InterfaceObservationProof) {}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/ThePlans/SourceShapeFixtures/PlanTraversal.swift" <<'EOF'
struct PlanFacts: HeistPlanTraversalVisitor {}

func deriveFacts(from plan: HeistPlan) {
    var facts = PlanFacts()
    HeistPlanTraversal().walk(plan, visitor: &facts)
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/ThePlans/SourceShapeFixtures/ExpressionOwnership.swift" <<'EOF'
package func retainPackageExpressionTypes(
    _ expression: Expr<String>,
    core: StringMatchCore<Expr<String>>
) {}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/ButtonHeistTesting/SourceShapeFixtures/TestSemantics.swift" <<'EOF'
func retainScriptedStep(
    _ step: HeistStep,
    result: HeistExecutionStepResult
) -> HeistExecutionStepResult {
    result
}

func retainScriptedWaitReceipt(_ receipt: HeistWaitReceipt) -> HeistWaitReceipt {
    receipt
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/SourceShapeFixtures/TargetResolution.swift" <<'EOF'
func resolveDirectly(
    _ target: ResolvedAccessibilityTarget,
    in interface: Interface
) -> AccessibilityTargetMatchSet {
    ElementMatchGraph(interface: interface).resolve(target)
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/TheStash/SemanticObservationStream.swift" <<'EOF'
final class SemanticObservationStreamFixture {
    let observationLog = SemanticObservationLog()
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheScore/SourceShapeFixtures/HierarchyTraversal.swift" <<'EOF'
func collectHierarchyFacts(_ hierarchy: AccessibilityHierarchy) {
    hierarchy.folded(
        onElement: { _, _ in 1 },
        onContainer: { _, children in children.reduce(0, +) }
    )
}

func inspectOneHierarchyNode(_ hierarchy: AccessibilityHierarchy) -> Bool {
    switch hierarchy {
    case .element:
        return true
    case .container(_, let children):
        return children.isEmpty
    }
}

indirect enum UnrelatedFixtureTree {
    case leaf
    case branch([UnrelatedFixtureTree])
}

func countUnrelatedFixtureTree(_ tree: UnrelatedFixtureTree) -> Int {
    switch tree {
    case .leaf:
        return 1
    case .branch(let children):
        return children.reduce(0) { $0 + countUnrelatedFixtureTree($1) }
    }
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheScore/SourceShapeFixtures/InterfaceGraph.swift" <<'EOF'
func useOwnedInterfaceGraph(_ interface: Interface) -> InterfaceGraph {
    interface.graph
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheScore/Core/AccessibilityHierarchy+Traversal.swift" <<'EOF'
func canonicalHierarchyWalk(_ hierarchy: AccessibilityHierarchy) {
    switch hierarchy {
    case .element:
        return
    case .container(_, let children):
        for child in children {
            canonicalHierarchyWalk(child)
        }
    }
}
EOF

run_lint
[[ "$LINT_STATUS" -eq 0 ]] || fail "source-shape lint rejected valid fixtures: $LINT_OUTPUT"

cat > "$FIXTURE_REPO/ButtonHeistCLI/Sources/Support/SourceShapeFixtures.swift" <<'EOF'
typealias AlternateAccessibilityTarget = AccessibilityTarget

var onUnannotated: ((Int) -> Void)?
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/SourceShapeFixtures/ObservationCommits.swift" <<'EOF'
func commitVisibleInterface(_ screen: InterfaceObservation) {}
func commitDiscoveryInterface(_ screen: InterfaceObservation?) {}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/ThePlans/SourceShapeFixtures/PlanTraversal.swift" <<'EOF'
func collectPlans(_ plan: HeistPlan) {
    collectPlans(plan.definitions[0])
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/ThePlans/SourceShapeFixtures/ArchitectureOwnership.swift" <<'EOF'
struct AccessibilityTarget {}

func constructObservationOutsideOwner() {
    _ = InterfaceObservation()
}

func constructLiveCaptureOutsideOwner() {
    _ = LiveCapture()
}

func constructEvidenceRollupOutsideOwner() {
    _ = HeistExecutionEvidenceRollup(steps: [])
}

func constructSemanticObservationPublicationOutsideOwner() {
    _ = SemanticObservationPublication()
}

func constructSemanticObservationRuntimeStateOutsideOwner() {
    _ = SemanticObservationRuntimeState()
}

struct HeistExecutionEvidenceRollup {}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/TheStash/InterfaceObservation.swift" <<'EOF'
struct InterfaceObservation {
    static func invalidOwnerConstruction() -> InterfaceObservation {
        InterfaceObservation()
    }
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/TheStash/LiveCapture.swift" <<'EOF'
struct LiveCapture {
    static func invalidOwnerConstruction() -> LiveCapture {
        LiveCapture()
    }
}
EOF

cat > "$FIXTURE_REPO/TestApp/Sources/AccessibleFixture.swift" <<'EOF'
func configureAccessibleFixture(_ view: FixtureView) {
    view.accessibilityIdentifier = "fixture"
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/ThePlans/SourceShapeFixtures/ExpressionOwnership.swift" <<'EOF'
internal enum Expr<Value> {}
public struct AlternateExpr {}
EOF

cat >> "$FIXTURE_REPO/ButtonHeist/Sources/ThePlans/Model/AccessibilityPredicate.swift" <<'EOF'

package typealias RogueTarget = AccessibilityTarget
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/TheBurglar/TheBurglar+InterfaceObservationBuilding.swift" <<'EOF'
func burglarHierarchyWalk(_ hierarchy: AccessibilityHierarchy) {
    switch hierarchy {
    case .element:
        return
    case .container(_, let children):
        for child in children {
            burglarHierarchyWalk(child)
        }
    }
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/SourceShapeFixtures/ObservationLog.swift" <<'EOF'
let alternateObservationLog = SemanticObservationLog()

extension SemanticObservationLog {
    func clearHistory() {}
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/TheScore/SourceShapeFixtures/InterfaceGraph.swift" <<'EOF'
func reconstructInterfaceGraph(_ interface: Interface) throws -> InterfaceGraph {
    try InterfaceGraph(interface: interface)
}
EOF

cat > "$FIXTURE_REPO/ButtonHeist/Sources/ButtonHeistTesting/SourceShapeFixtures/TestSemantics.swift" <<'EOF'
func emulateExecution(_ step: HeistStep) -> HeistExecutionStepResult {
    switch step {
    case .action:
        return fixtureExecutionResult()
    default:
        return fixtureExecutionResult()
    }
}

func emulateWait(
    _ step: ResolvedWaitRuntimeInput,
    observation: HeistSemanticObservation
) -> HeistWaitReceipt {
    _ = PredicateEvaluation.evaluate(
        step.predicate,
        expression: step.predicateExpression,
        in: observation
    )
    return fixtureWaitReceipt()
}
EOF

run_lint
[[ "$LINT_STATUS" -ne 0 ]] || fail "source-shape lint accepted invalid fixtures"
[[ "$LINT_OUTPUT" == *"buttonheist.canonical_accessibility_target_spelling"* ]] \
    || fail "source-shape lint missed the alternate target alias: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"alternate AccessibilityTarget typealias"* ]] \
    || fail "source-shape lint missed the owner-file target alias: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"callback without isolation annotation"* ]] \
    || fail "source-shape lint missed the unannotated callback: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"onUnannotated"* ]] \
    || fail "callback diagnostic did not identify onUnannotated: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"commitVisibleInterface(InterfaceObservation)"* ]] \
    || fail "source-shape lint missed commitVisibleInterface: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"commitDiscoveryInterface(InterfaceObservation?)"* ]] \
    || fail "source-shape lint missed commitDiscoveryInterface: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"interface observation commits require settled or explored InterfaceObservationProof"* ]] \
    || fail "raw observation commit diagnostic did not require proof: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"recursive HeistPlan/HeistStep descent outside canonical traversal"* ]] \
    || fail "source-shape lint missed recursive plan descent: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"recursive AccessibilityHierarchy descent outside canonical traversal ownership"* ]] \
    || fail "source-shape lint missed recursive accessibility hierarchy descent: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.canonical_accessibility_hierarchy_traversal"* ]] \
    || fail "hierarchy traversal violation did not identify its architectural rule: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.architecture_currency.AccessibilityTarget"* ]] \
    || fail "source-shape lint missed duplicate typed architecture ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.architecture_currency.HeistExecutionEvidenceRollup"* ]] \
    || fail "source-shape lint missed duplicate rollup declaration ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"pipeline value constructed outside its canonical owner"* ]] \
    || fail "source-shape lint missed construction outside the canonical builder method: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.canonical_interface_observation_construction"* ]] \
    || fail "source-shape lint missed InterfaceObservation construction ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.canonical_live_capture_construction"* ]] \
    || fail "source-shape lint missed LiveCapture construction ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.canonical_heist_execution_evidence_rollup_construction"* ]] \
    || fail "source-shape lint missed standard-shaper construction ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"Expr must be the single package-internal expression declaration"* ]] \
    || fail "source-shape lint missed non-package Expr ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"nominal Expr bookkeeping type outside the canonical expression owner"* ]] \
    || fail "source-shape lint missed nominal Expr bookkeeping: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"semantic observation log exposes a destructive clear API"* ]] \
    || fail "source-shape lint missed destructive observation-log API: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.canonical_semantic_observation_log_construction"* ]] \
    || fail "source-shape lint missed standard-shaper observation-log ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.canonical_semantic_observation_publication_construction"* ]] \
    || fail "source-shape lint missed observation-publication ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.canonical_semantic_observation_runtime_state_construction"* ]] \
    || fail "source-shape lint missed observation runtime-state ownership: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"InterfaceGraph reconstructed from Interface outside its owner"* ]] \
    || fail "source-shape lint missed external InterfaceGraph reconstruction: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"test support implements HeistStep execution semantics"* ]] \
    || fail "source-shape lint missed test-owned HeistStep execution: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"test support implements wait predicate semantics"* ]] \
    || fail "source-shape lint missed test-owned wait predicate evaluation: $LINT_OUTPUT"
[[ "$LINT_OUTPUT" == *"buttonheist.demo_accessibility_identifier"* ]] \
    || fail "source-shape lint missed demo accessibilityIdentifier use: $LINT_OUTPUT"

echo "PASS: SwiftSyntax source-shape guardrails"
