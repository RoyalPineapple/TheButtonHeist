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
swift package diagnose-api-breaking-changes "$BASELINE_TAG" \
    --products ThePlans TheScore ButtonHeistDSL ButtonHeist
