#!/usr/bin/env bash
# Check public Swift API compatibility against the latest release tag.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BASELINE_TAG="${BUTTONHEIST_SWIFT_API_BASELINE_TAG:-}"

if [[ -z "$BASELINE_TAG" ]]; then
    git fetch --quiet --force --tags origin +refs/heads/main:refs/remotes/origin/main
    BASELINE_TAG="$(git tag --merged origin/main --sort=-v:refname 'v*' | head -1 || true)"
fi

if [[ -z "$BASELINE_TAG" ]]; then
    echo "No release tag found on origin/main; skipping Swift API breakage check."
    exit 0
fi

echo "Checking Swift API breakage against $BASELINE_TAG"
PUBLIC_PRODUCTS=(
    ThePlans
    TheScore
    ButtonHeistDSL
    ButtonHeist
    TheInsideJob
    ButtonHeistTesting
)
INTENTIONAL_BREAKAGES=(
    "enumelement StringMatch.Mode.isEmpty has been added as a new enum case"
    "enumelement StringMatch.isEmpty has been added as a new enum case"
    "constructor HeistInvocationEvidence.init(invocation:name:argument:childFailedPath:expectationActionResult:expectation:expectationEvidence:) has been removed"
)
MODE="${BUTTONHEIST_SWIFT_API_BREAKAGE_MODE:-strict}"
case "$MODE" in
    strict|report) ;;
    *)
        echo "Error: BUTTONHEIST_SWIFT_API_BREAKAGE_MODE must be 'strict' or 'report', got '$MODE'"
        exit 2
        ;;
esac

OUTPUT_FILE="$(mktemp)"
trap 'rm -f "$OUTPUT_FILE"' EXIT

set +e
swift package diagnose-api-breaking-changes "$BASELINE_TAG" \
    --products "${PUBLIC_PRODUCTS[@]}" 2>&1 | tee "$OUTPUT_FILE"
status=${PIPESTATUS[0]}
set -e

if [[ "$status" -eq 0 ]]; then
    exit 0
fi

if [[ "$MODE" == "report" ]]; then
    echo "Swift API breakage reported in non-blocking mode."
    echo "Run with BUTTONHEIST_SWIFT_API_BREAKAGE_MODE=strict to fail on this diagnostic."
    exit 0
fi

detected_breakages=()
while IFS= read -r breakage; do
    [[ -n "$breakage" ]] || continue
    detected_breakages+=("$breakage")
done < <(grep -F "API breakage:" "$OUTPUT_FILE" | sed 's/^.*API breakage: //')
if [[ "${#detected_breakages[@]}" -eq 0 ]]; then
    exit "$status"
fi

unexpected_breakages=()
for breakage in "${detected_breakages[@]}"; do
    allowed=0
    for intentional in "${INTENTIONAL_BREAKAGES[@]}"; do
        if [[ "$breakage" == "$intentional" ]]; then
            allowed=1
            break
        fi
    done
    if [[ "$allowed" -eq 0 ]]; then
        unexpected_breakages+=("$breakage")
    fi
done

if [[ "${#unexpected_breakages[@]}" -eq 0 ]]; then
    echo "Only intentional Swift API breakage detected:"
    printf '  - %s\n' "${detected_breakages[@]}"
    exit 0
fi

echo "Unexpected Swift API breakage detected:"
printf '  - %s\n' "${unexpected_breakages[@]}"
exit "$status"
