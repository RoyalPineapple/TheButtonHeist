#!/usr/bin/env bash
# Smoke test the heist-plan Swift authoring compiler outside SwiftPM's test runner.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO_ROOT"

HEIST_PLAN_TOOL="${HEIST_PLAN_TOOL:-$REPO_ROOT/ButtonHeist/.build/debug/heist-plan}"
if [[ ! -x "$HEIST_PLAN_TOOL" ]]; then
    echo "Error: heist-plan executable not found at $HEIST_PLAN_TOOL" >&2
    exit 1
fi
HEIST_THEPLANS_BUILD_DIR="${HEIST_THEPLANS_BUILD_DIR:-$REPO_ROOT/ButtonHeist/.build/debug}"

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/heist-plan-compile.XXXXXX")"
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

SOURCE="$TMP_DIR/Plan.swift"
OUTPUT="$TMP_DIR/compiled.heist"
RENDERED="$TMP_DIR/rendered.swift"
EXPECTED="$TMP_DIR/expected.swift"

cat > "$SOURCE" <<'SWIFT'
import ThePlans

func makeHeist() throws -> HeistPlan {
    try HeistPlan("compiled") {
        Warn("from Swift")
    }
}
SWIFT

cat > "$EXPECTED" <<'SWIFT'
HeistPlan("compiled") {
    Warn("from Swift")
}
SWIFT

echo "Compiling Swift fixture with heist-plan"
HEIST_SOURCE_COMPILER_TRACE=1 HEIST_THEPLANS_BUILD_DIR="$HEIST_THEPLANS_BUILD_DIR" \
    "$HEIST_PLAN_TOOL" compile "$SOURCE" --entry makeHeist --output "$OUTPUT"
[[ -d "$OUTPUT" ]] || {
    echo "Error: compile did not produce a .heist package directory" >&2
    exit 1
}
[[ -f "$OUTPUT/manifest.json" ]] || {
    echo "Error: compile output is missing manifest.json" >&2
    exit 1
}
[[ -f "$OUTPUT/plan.json" ]] || {
    echo "Error: compile output is missing plan.json" >&2
    exit 1
}

echo "Validating compiled heist package passes runtime validation"
"$HEIST_PLAN_TOOL" validate "$OUTPUT"
echo "Rendering compiled heist package as canonical Swift"
"$HEIST_PLAN_TOOL" render-swift "$OUTPUT" > "$RENDERED"
diff -u "$EXPECTED" "$RENDERED"

# Negative: a missing build directory override must fail with an actionable
# diagnostic that names what was searched and how to fix it. This guards the
# single-resolution contract — there is no hidden fallback to building ThePlans
# from source or to JSON.
echo "Verifying missing-artifact diagnostic"
MISSING_OUTPUT="$TMP_DIR/missing.heist"
set +e
DIAGNOSTIC="$(HEIST_THEPLANS_BUILD_DIR="$TMP_DIR/does-not-exist" \
    "$HEIST_PLAN_TOOL" compile "$SOURCE" --entry makeHeist --output "$MISSING_OUTPUT" 2>&1)"
STATUS=$?
set -e
if [[ "$STATUS" -eq 0 ]]; then
    echo "Error: compile unexpectedly succeeded with a missing build directory" >&2
    exit 1
fi
for fragment in "searched:" "HEIST_THEPLANS_BUILD_DIR" "swift build --package-path ButtonHeist --product heist-plan"; do
    if [[ "$DIAGNOSTIC" != *"$fragment"* ]]; then
        echo "Error: missing-artifact diagnostic did not mention '$fragment'" >&2
        echo "--- diagnostic ---" >&2
        echo "$DIAGNOSTIC" >&2
        exit 1
    fi
done
