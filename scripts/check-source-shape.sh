#!/usr/bin/env bash
# Guard source-level house rules that the compiler and API diff do not own.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BUTTONHEIST_SOURCE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUMPER_CACHE_DIR="${BUMPER_CACHE_DIR:-$REPO_ROOT/.build/bumper-cache}"
BUMPER_EVALUATION_TIMEOUT_SECONDS="${BUMPER_EVALUATION_TIMEOUT_SECONDS:-300}"
BUMPER_RUNNER_BUILD_CONFIGURATION="${BUMPER_RUNNER_BUILD_CONFIGURATION:-debug}"
export BUMPER_CACHE_DIR BUMPER_EVALUATION_TIMEOUT_SECONDS BUMPER_RUNNER_BUILD_CONFIGURATION

if (( $# > 1 )); then
    echo "Usage: scripts/check-source-shape.sh [lint|test]" >&2
    exit 2
fi

COMMAND="${1:-lint}"
case "$COMMAND" in
    lint|test) ;;
    *)
        echo "Usage: scripts/check-source-shape.sh [lint|test]" >&2
        exit 2
        ;;
esac

BUMPER_ARGUMENTS=("$COMMAND" "$REPO_ROOT")
if [[ "$COMMAND" == "lint" ]]; then
    BUMPER_ARGUMENTS+=(--fail-on error)
fi

swift run \
    --package-path "$REPO_ROOT" \
    --configuration debug \
    bumper "${BUMPER_ARGUMENTS[@]}"
