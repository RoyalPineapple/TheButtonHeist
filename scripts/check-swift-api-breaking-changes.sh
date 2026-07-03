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
MODE="${BUTTONHEIST_SWIFT_API_BREAKAGE_MODE:-strict}"
case "$MODE" in
    strict|report) ;;
    *)
        echo "Error: BUTTONHEIST_SWIFT_API_BREAKAGE_MODE must be 'strict' or 'report', got '$MODE'"
        exit 2
        ;;
esac

set +e
swift package diagnose-api-breaking-changes "$BASELINE_TAG" \
    --products "${PUBLIC_PRODUCTS[@]}"
status=$?
set -e

if [[ "$status" -eq 0 ]]; then
    exit 0
fi

if [[ "$MODE" == "report" ]]; then
    echo "Swift API breakage reported in non-blocking mode."
    echo "Run with BUTTONHEIST_SWIFT_API_BREAKAGE_MODE=strict to fail on this diagnostic."
    exit 0
fi

exit "$status"
