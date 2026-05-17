#!/usr/bin/env bash
# Verify that the parser dependency has a single, auditable release contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PARSER_REPO_URL="https://github.com/RoyalPineapple/AccessibilitySnapshotBH"
PACKAGE_FILE="Package.swift"
SUBMODULE_PATH="submodules/AccessibilitySnapshotBH"

fail() {
    echo "::error::$*"
    exit 1
}

PACKAGE_LINE=$(grep -F "$PARSER_REPO_URL" "$PACKAGE_FILE" || true)
[[ -n "$PACKAGE_LINE" ]] || fail "$PACKAGE_FILE does not declare $PARSER_REPO_URL"

PACKAGE_TAG=$(printf '%s\n' "$PACKAGE_LINE" \
    | grep -oE 'exact: "[0-9]+\.[0-9]+\.[0-9]+"' \
    | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' \
    | head -1 || true)

if [[ -z "$PACKAGE_TAG" ]]; then
    fail "$PACKAGE_FILE must pin AccessibilitySnapshotBH with exact: \"x.y.z\". Semver ranges can silently pull parser semantics that were not released with Button Heist."
fi

SUBMODULE_SHA=$(git ls-tree HEAD "$SUBMODULE_PATH" | awk '{print $3}')
[[ -n "$SUBMODULE_SHA" ]] || fail "$SUBMODULE_PATH is not tracked as a submodule"

BRANCH_TIP=$(git ls-remote "$PARSER_REPO_URL" refs/heads/main | awk '{print $1}')
[[ -n "$BRANCH_TIP" ]] || fail "could not resolve AccessibilitySnapshotBH main branch"

TAG_SHA=$(git ls-remote "$PARSER_REPO_URL" "refs/tags/$PACKAGE_TAG^{}" | awk '{print $1}')
if [[ -z "$TAG_SHA" ]]; then
    TAG_SHA=$(git ls-remote "$PARSER_REPO_URL" "refs/tags/$PACKAGE_TAG" | awk '{print $1}')
fi

echo "AccessibilitySnapshotBH contract:"
echo "  Package.swift exact tag: $PACKAGE_TAG"
echo "  Tagged commit:           ${TAG_SHA:-<missing>}"
echo "  Submodule pin:           $SUBMODULE_SHA"
echo "  Main branch tip:         $BRANCH_TIP"

FAILED=0

if [[ -z "$TAG_SHA" ]]; then
    echo "::error::Package.swift references AccessibilitySnapshotBH tag $PACKAGE_TAG, but that tag does not exist."
    FAILED=1
elif [[ "$TAG_SHA" != "$SUBMODULE_SHA" ]]; then
    echo "::error::Package.swift tag $PACKAGE_TAG ($TAG_SHA) does not match submodule ($SUBMODULE_SHA). Run: ./scripts/bump-parser.sh"
    FAILED=1
fi

if [[ "$SUBMODULE_SHA" != "$BRANCH_TIP" ]]; then
    echo "::error::Submodule ($SUBMODULE_SHA) is behind AccessibilitySnapshotBH main ($BRANCH_TIP). Run: git submodule update --remote submodules/AccessibilitySnapshotBH && ./scripts/bump-parser.sh"
    FAILED=1
fi

if [[ "$FAILED" -ne 0 ]]; then
    exit "$FAILED"
fi

echo "Parser dependency contract verified for AccessibilitySnapshotBH $PACKAGE_TAG"
