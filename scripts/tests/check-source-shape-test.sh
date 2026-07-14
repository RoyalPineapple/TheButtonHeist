#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
FIXTURE_ROOT="$(mktemp -d)"
FIXTURE_REPO="$FIXTURE_ROOT/repo"
LINT_OUTPUT=""
LINT_STATUS=0

trap 'rm -rf "$FIXTURE_ROOT"' EXIT

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

mkdir -p "$FIXTURE_REPO"
copy_fixture_file "BumperBowling.swift"

while IFS= read -r source; do
    copy_fixture_file "${source#"$REPO_ROOT/"}"
done < <(find "$REPO_ROOT/.bumper" -type f -print | sort)

while IFS= read -r owner; do
    copy_fixture_file "$owner"
done < <(
    sed -n '/private let architectureCurrencyOwnership:/,/^]/p' \
        "$REPO_ROOT/.bumper/Sources/ButtonHeistCustomRules.swift" \
        | sed -n \
            -e 's/.*[.]declaration([^,]*, ownerPath: "\([^"]*\)".*/\1/p' \
            -e 's/.*declarationOwnerPath: "\([^"]*\)".*/\1/p' \
        | sort -u
)

mkdir -p \
    "$FIXTURE_REPO/ButtonHeistCLI/Sources/Support" \
    "$FIXTURE_REPO/ButtonHeist/Sources/ThePlans/SourceShapeFixtures" \
    "$FIXTURE_REPO/ButtonHeist/Sources/TheInsideJob/SourceShapeFixtures"

cat > "$FIXTURE_REPO/ButtonHeistCLI/Sources/Support/SourceShapeFixtures.swift" <<'EOF'
var onActorIsolated: (@MainActor (Int) -> Void)?
var onSendable: (@Sendable (Int) -> Void)?

/// Mutable state is lock-protected in the real boundary type.
final class LockBackedFixture: @unchecked Sendable {} // swiftlint:disable:this agent_unchecked_sendable_no_comment

@MainActor enum ActorNamespaceFixture {} // swiftlint:disable:this agent_main_actor_value_type
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

run_lint
[[ "$LINT_STATUS" -ne 0 ]] || fail "source-shape lint accepted invalid fixtures"
[[ "$LINT_OUTPUT" == *"alternate AccessibilityTarget typealias"* ]] \
    || fail "source-shape lint missed the alternate target alias: $LINT_OUTPUT"
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

echo "PASS: SwiftSyntax source-shape guardrails"
