#!/usr/bin/env bash
# Guard source-level house rules that the compiler and API diff do not own.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BUTTONHEIST_SOURCE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUMPER_BOWLING_REPOSITORY="${BUMPER_BOWLING_REPOSITORY:-https://github.com/RoyalPineapple/BumperBowling.git}"
BUMPER_BOWLING_REVISION="${BUMPER_BOWLING_REVISION:-655ccf729898b4dc17b84238645befceb8863ec3}"
BUMPER_BOWLING_CHECKOUT="${BUMPER_BOWLING_CHECKOUT:-$REPO_ROOT/.build/bumper-bowling}"
BUMPER_CACHE_DIR="${BUMPER_CACHE_DIR:-$REPO_ROOT/.build/bumper-cache}"
export BUMPER_CACHE_DIR

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
        "$BUMPER" lint "$REPO_ROOT" --fail-on error
        return
    fi

    if [[ -n "${BUMPER_BOWLING_PACKAGE_PATH:-}" ]]; then
        swift run --package-path "$BUMPER_BOWLING_PACKAGE_PATH" bumper lint "$REPO_ROOT" --fail-on error
        return
    fi

    ensure_bumper_checkout
    swift run --package-path "$BUMPER_BOWLING_CHECKOUT" bumper lint "$REPO_ROOT" --fail-on error
}

run_bumper
