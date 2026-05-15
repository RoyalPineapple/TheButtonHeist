#!/usr/bin/env bash
# Verify that wire-format changes are paired with a `buttonHeistVersion` bump.
#
# Wire format lives in `ButtonHeist/Sources/TheScore/` — every Codable type that
# crosses the connection, the Codable adapters, the `WireBoundaryTypes` rawValue
# strings, the `InterfaceDelta` / `ActionExpectation` / `ConnectionScope`
# payloads, and the `AccessibilityPolicy` (whose
# `synthesisPriority` order is wire-format because it determines synthesized
# heistIds, per CLAUDE.md).
#
# Any edit under `ButtonHeist/Sources/TheScore/*.swift` is treated as a
# wire-format change and must be accompanied by a version bump in Messages.swift.
# Otherwise client and server can drift silently — the handshake would still
# pass, and protocol mismatches would surface as garbled payloads in production
# rather than a clean `protocolMismatch` reject at connect.
#
# Usage:
#   scripts/check-wire-format-bump.sh                # diff against origin/main
#   scripts/check-wire-format-bump.sh <base-ref>     # diff against custom base
#
# Exit codes:
#   0 — no wire files changed, or wire files changed AND version was bumped
#   1 — wire files changed but version did not change
#   2 — usage / git error

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

BASE_REF="${1:-origin/main}"

# Wire-format scope: every live protocol Swift file in TheScore is part of the
# connection contract. Heist playback files are persisted local artifacts with
# their own file-format version, so they do not require a product release bump.
WIRE_GLOB="ButtonHeist/Sources/TheScore/"
NON_PROTOCOL_FILES=(
    "ButtonHeist/Sources/TheScore/HeistPlayback.swift"
    "ButtonHeist/Sources/TheScore/HeistPlaybackReport.swift"
)

VERSION_FILE="ButtonHeist/Sources/TheScore/Messages.swift"
VERSION_PATTERN='buttonHeistVersion = "[^"]*"'

if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
    echo "::error::Base ref '$BASE_REF' not found. Fetch it first or pass an explicit ref." >&2
    exit 2
fi

# Determine the merge base. CI checkouts are often shallow, and a brand-new
# branch may share no history with the base ref. In either case, `git diff
# A...B` errors with "fatal: no merge base". Fall back to diffing against the
# base ref directly (two-dot), which compares the working tree against the tip
# of the base ref rather than against the common ancestor. That's a strict
# superset of the three-dot diff, so we may flag files that were already
# changed upstream — acceptable, since the check only fires when the version
# is also unchanged, and a wire-touching PR should always bump it anyway.
DIFF_MODE="three-dot"
if ! git merge-base "$BASE_REF" HEAD >/dev/null 2>&1; then
    echo "::warning::No merge base between HEAD and $BASE_REF (shallow clone or unrelated history). Falling back to two-dot diff against $BASE_REF." >&2
    DIFF_MODE="two-dot"
fi

CHANGED_FILES=""
if [ "$DIFF_MODE" = "three-dot" ]; then
    if ! CHANGED_FILES=$(git diff --name-only "$BASE_REF"...HEAD 2>/dev/null); then
        echo "::warning::git diff $BASE_REF...HEAD failed unexpectedly. Falling back to two-dot diff." >&2
        DIFF_MODE="two-dot"
    fi
fi

if [ "$DIFF_MODE" = "two-dot" ]; then
    if ! CHANGED_FILES=$(git diff --name-only "$BASE_REF" HEAD 2>/dev/null); then
        echo "::error::Could not compute diff against '$BASE_REF'. In CI, ensure the workflow fetches enough history (e.g. fetch-depth: 0). Locally, run 'git fetch origin main' and retry." >&2
        exit 2
    fi
fi

# Which files under the wire glob changed?
CHANGED_WIRE=()
while IFS= read -r file; do
    [ -z "$file" ] && continue
    skip=false
    for non_protocol_file in "${NON_PROTOCOL_FILES[@]}"; do
        if [ "$file" = "$non_protocol_file" ]; then
            skip=true
            break
        fi
    done
    [ "$skip" = true ] && continue

    case "$file" in
        "$WIRE_GLOB"*.swift)
            CHANGED_WIRE+=("$file")
            ;;
    esac
done <<< "$CHANGED_FILES"

if [ "${#CHANGED_WIRE[@]}" -eq 0 ]; then
    echo "No wire-format files changed against $BASE_REF — nothing to check."
    exit 0
fi

echo "Wire-format files changed against $BASE_REF:"
for file in "${CHANGED_WIRE[@]}"; do
    echo "  - $file"
done

# Extract version strings before and after.
OLD_VERSION=$(git show "$BASE_REF:$VERSION_FILE" 2>/dev/null \
    | grep -oE "$VERSION_PATTERN" \
    | head -1 \
    | cut -d'"' -f2 || true)

NEW_VERSION=$(grep -oE "$VERSION_PATTERN" "$VERSION_FILE" \
    | head -1 \
    | cut -d'"' -f2 || true)

if [ -z "$OLD_VERSION" ] || [ -z "$NEW_VERSION" ]; then
    echo "::error::Could not extract buttonHeistVersion from $VERSION_FILE (old='$OLD_VERSION', new='$NEW_VERSION')." >&2
    exit 2
fi

echo "buttonHeistVersion: $OLD_VERSION -> $NEW_VERSION"

if [ "$OLD_VERSION" = "$NEW_VERSION" ]; then
    cat >&2 <<EOF
::error::Wire-format files changed but buttonHeistVersion was not bumped.

A wire-format change without a version bump means clients and servers built
from this PR will negotiate as compatible with prior releases, then drift on
the actual payload. Bump buttonHeistVersion in $VERSION_FILE — usually via
scripts/release.sh on a clean main — and try again.

If you genuinely believe this change is wire-compatible (e.g. comments,
docstrings, internal helpers that don't cross the Codable boundary), justify
that in the PR description and skip this check by removing the affected
file(s) from the diff or splitting them into a separate non-wire PR.
EOF
    exit 1
fi

echo "buttonHeistVersion bumped — wire-format change is accompanied by a release."
exit 0
