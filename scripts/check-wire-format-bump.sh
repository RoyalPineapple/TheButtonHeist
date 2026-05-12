#!/usr/bin/env bash
# Verify that wire-format changes are paired with a `buttonHeistVersion` bump.
#
# Wire-format changes (any edit to ServerMessages.swift, ClientMessages.swift,
# Messages.swift, or Elements.swift) must be accompanied by a version bump in
# Messages.swift. Otherwise client and server can drift silently — the handshake
# would still pass, and protocol mismatches would surface as garbled payloads
# in production rather than a clean `protocolMismatch` reject at connect.
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

# Wire-format files. Any edit here is treated as a wire-format change.
WIRE_FILES=(
    "ButtonHeist/Sources/TheScore/ServerMessages.swift"
    "ButtonHeist/Sources/TheScore/ClientMessages.swift"
    "ButtonHeist/Sources/TheScore/Messages.swift"
    "ButtonHeist/Sources/TheScore/Elements.swift"
)

VERSION_FILE="ButtonHeist/Sources/TheScore/Messages.swift"
VERSION_PATTERN='buttonHeistVersion = "[^"]*"'

if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
    echo "::error::Base ref '$BASE_REF' not found. Fetch it first or pass an explicit ref." >&2
    exit 2
fi

CHANGED_FILES=$(git diff --name-only "$BASE_REF"...HEAD)

# Which wire files changed?
CHANGED_WIRE=()
for file in "${WIRE_FILES[@]}"; do
    if printf '%s\n' "$CHANGED_FILES" | grep -Fxq "$file"; then
        CHANGED_WIRE+=("$file")
    fi
done

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
