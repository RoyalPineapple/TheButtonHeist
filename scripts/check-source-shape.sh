#!/usr/bin/env bash
# Guard source-level house rules that the compiler and API diff do not own.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${BUTTONHEIST_SOURCE_ROOT:-$(cd "$SCRIPT_DIR/.." && pwd)}"
BUMPER_BOWLING_REPOSITORY="${BUMPER_BOWLING_REPOSITORY:-https://github.com/RoyalPineapple/BumperBowling.git}"
BUMPER_BOWLING_REVISION="${BUMPER_BOWLING_REVISION:-7e036292060a5b770b16d3613f8b3dfdc79f4a82}"
BUMPER_BOWLING_CHECKOUT="${BUMPER_BOWLING_CHECKOUT:-$REPO_ROOT/.build/bumper-bowling}"
BUMPER_CACHE_DIR="${BUMPER_CACHE_DIR:-$REPO_ROOT/.build/bumper-cache}"
BUMPER_CONFIGURATION_EVALUATION_TIMEOUT_SECONDS="${BUMPER_CONFIGURATION_EVALUATION_TIMEOUT_SECONDS:-300}"
export BUMPER_CACHE_DIR BUMPER_CONFIGURATION_EVALUATION_TIMEOUT_SECONDS

if [[ ! "$BUMPER_CONFIGURATION_EVALUATION_TIMEOUT_SECONDS" =~ ^[1-9][0-9]*$ ]]; then
    echo "Error: BUMPER_CONFIGURATION_EVALUATION_TIMEOUT_SECONDS must be a positive integer" >&2
    exit 1
fi

fetch_bumper_revision() {
    local checkout="$1"

    if ! git -C "$checkout" fetch --depth=1 origin "$BUMPER_BOWLING_REVISION"; then
        git -C "$checkout" fetch --depth=1 origin main
    fi
    git -C "$checkout" checkout --detach "$BUMPER_BOWLING_REVISION" >/dev/null
}

patch_bumper_evaluation_timeout() {
    local checkout="$1"
    local runner="$checkout/Sources/BumperBowlingCore/ConfigurationCommandRunner.swift"
    local marker='BUMPER_CONFIGURATION_EVALUATION_TIMEOUT_SECONDS'
    local original='    static let configurationEvaluationTimeoutSeconds: TimeInterval = 60'

    if grep -Fq "$marker" "$runner"; then
        return
    fi
    if ! grep -Fq "$original" "$runner"; then
        echo "Error: Bumper Bowling evaluation timeout source no longer matches 0.5.1" >&2
        exit 1
    fi

    /usr/bin/perl -0pi -e '
        s{    static let configurationEvaluationTimeoutSeconds: TimeInterval = 60\n}{    static let configurationEvaluationTimeoutSeconds: TimeInterval =\n        ProcessInfo.processInfo.environment["BUMPER_CONFIGURATION_EVALUATION_TIMEOUT_SECONDS"]\n            .flatMap(Double.init) ?? 60\n}
    ' "$runner"

    if ! grep -Fq "$marker" "$runner"; then
        echo "Error: failed to wire Bumper Bowling evaluation timeout override" >&2
        exit 1
    fi
}

ensure_bumper_checkout() {
    if [[ -d "$BUMPER_BOWLING_CHECKOUT/.git" ]]; then
        fetch_bumper_revision "$BUMPER_BOWLING_CHECKOUT"
        patch_bumper_evaluation_timeout "$BUMPER_BOWLING_CHECKOUT"
        return
    fi

    if [[ -e "$BUMPER_BOWLING_CHECKOUT" ]]; then
        echo "Error: $BUMPER_BOWLING_CHECKOUT exists but is not a git checkout" >&2
        exit 1
    fi

    git clone --filter=blob:none --no-checkout "$BUMPER_BOWLING_REPOSITORY" "$BUMPER_BOWLING_CHECKOUT"
    fetch_bumper_revision "$BUMPER_BOWLING_CHECKOUT"
    patch_bumper_evaluation_timeout "$BUMPER_BOWLING_CHECKOUT"
}

run_bumper() {
    if [[ -n "${BUMPER:-}" ]]; then
        "$BUMPER" lint "$REPO_ROOT" --fail-on error
        return
    fi

    if [[ -n "${BUMPER_BOWLING_PACKAGE_PATH:-}" ]]; then
        patch_bumper_evaluation_timeout "$BUMPER_BOWLING_PACKAGE_PATH"
        swift run --package-path "$BUMPER_BOWLING_PACKAGE_PATH" bumper lint "$REPO_ROOT" --fail-on error
        return
    fi

    ensure_bumper_checkout
    swift run --package-path "$BUMPER_BOWLING_CHECKOUT" bumper lint "$REPO_ROOT" --fail-on error
}

run_bumper
