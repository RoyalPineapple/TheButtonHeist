#!/usr/bin/env bash
# Guard source-level house rules that the compiler and API diff do not own.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BUTTONHEIST_SOURCE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUMPER_BOWLING_REPOSITORY="${BUMPER_BOWLING_REPOSITORY:-https://github.com/RoyalPineapple/BumperBowling.git}"
BUMPER_BOWLING_REVISION="${BUMPER_BOWLING_REVISION:-971cb79942baa79606170f63c13ba811270e216b}"
BUMPER_BOWLING_CHECKOUT="${BUMPER_BOWLING_CHECKOUT:-$REPO_ROOT/.build/bumper-bowling}"
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

fetch_bumper_revision() {
    local checkout="$1"

    if ! git -C "$checkout" fetch --depth=1 origin "$BUMPER_BOWLING_REVISION"; then
        git -C "$checkout" fetch --depth=1 origin main
    fi
    git -C "$checkout" checkout --detach "$BUMPER_BOWLING_REVISION" >/dev/null
}

ensure_bumper_checkout() {
    if [[ -d "$BUMPER_BOWLING_CHECKOUT/.git" ]]; then
        fetch_bumper_revision "$BUMPER_BOWLING_CHECKOUT"
        return
    fi

    if [[ -e "$BUMPER_BOWLING_CHECKOUT" ]]; then
        echo "Error: $BUMPER_BOWLING_CHECKOUT exists but is not a git checkout" >&2
        exit 1
    fi

    git clone --filter=blob:none --no-checkout "$BUMPER_BOWLING_REPOSITORY" "$BUMPER_BOWLING_CHECKOUT"
    fetch_bumper_revision "$BUMPER_BOWLING_CHECKOUT"
}

run_bumper() {
    if [[ -n "${BUMPER:-}" ]]; then
        run_bumper_binary "$BUMPER"
        return
    fi

    if [[ -n "${BUMPER_BOWLING_PACKAGE_PATH:-}" ]]; then
        run_bumper_from_package "$BUMPER_BOWLING_PACKAGE_PATH"
        return
    fi

    ensure_bumper_checkout
    run_bumper_from_package "$BUMPER_BOWLING_CHECKOUT"
}

run_bumper_from_package() {
    local package_path="$1"
    local binary_path

    swift build --package-path "$package_path" --product bumper >/dev/null
    binary_path="$(swift build --package-path "$package_path" --show-bin-path)/bumper"
    run_bumper_binary "$binary_path"
}

run_bumper_binary() {
    local binary_path="$1"

    case "$COMMAND" in
        lint)
            "$binary_path" lint "$REPO_ROOT" --fail-on error
            ;;
        test)
            "$binary_path" test "$REPO_ROOT"
            ;;
    esac
}

run_bumper
