#!/usr/bin/env bash
# Bump the AccessibilitySnapshotBH dependency.
#
# Reuses an existing semver tag on the current AccessibilitySnapshotBH
# submodule commit, or tags the current parser main commit with the next
# minor version and bumps the exact Package.swift pin to match.
#
# Usage: ./scripts/bump-parser.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'

DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Error: unknown flag '$1'"; exit 1 ;;
    esac
done

SUBMODULE_DIR="submodules/AccessibilitySnapshotBH"
PACKAGE_FILE="Package.swift"

if [[ ! -d "$SUBMODULE_DIR/.git" ]] && [[ ! -f "$SUBMODULE_DIR/.git" ]]; then
    echo "Error: submodule not initialized at $SUBMODULE_DIR"
    echo "  git submodule update --init --recursive"
    exit 1
fi

SUBMODULE_SHA=$(git -C "$SUBMODULE_DIR" rev-parse HEAD)
echo "Submodule commit: ${SUBMODULE_SHA:0:8}"

CURRENT_PIN=$(grep 'AccessibilitySnapshotBH' "$PACKAGE_FILE" | grep -oE 'exact: "[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -z "$CURRENT_PIN" ]]; then
    echo "Error: could not find exact AccessibilitySnapshotBH version pin in $PACKAGE_FILE"
    exit 1
fi

git -C "$SUBMODULE_DIR" fetch origin main --tags --quiet

CURRENT_COMMIT_TAG=$(git -C "$SUBMODULE_DIR" tag -l --points-at "$SUBMODULE_SHA" --sort=-v:refname \
    | grep -E "$SEMVER_REGEX" \
    | head -1 || true)

if [[ -n "$CURRENT_COMMIT_TAG" ]]; then
    if [[ "$CURRENT_PIN" == "$CURRENT_COMMIT_TAG" ]]; then
        echo "Submodule and Package.swift are already at $CURRENT_COMMIT_TAG — nothing to bump."
        exit 0
    fi

    echo "Submodule is already tagged $CURRENT_COMMIT_TAG; Package.swift pin is $CURRENT_PIN."
    echo "Package.swift pin: $CURRENT_PIN → $CURRENT_COMMIT_TAG"
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "(dry run — no changes made)"
        exit 0
    fi

    sed -i '' "s|exact: \"$CURRENT_PIN\"|exact: \"$CURRENT_COMMIT_TAG\"|" "$PACKAGE_FILE"
    git add "$PACKAGE_FILE"
    git commit -m "Bump AccessibilitySnapshotBH $CURRENT_PIN → $CURRENT_COMMIT_TAG"
    echo "✓ Bumped Package.swift"
    echo "✓ Committed"
    exit 0
fi

BRANCH_TIP=$(git -C "$SUBMODULE_DIR" rev-parse origin/main)
if [[ "$SUBMODULE_SHA" != "$BRANCH_TIP" ]]; then
    cat >&2 <<EOF
Error: AccessibilitySnapshotBH submodule commit ${SUBMODULE_SHA:0:8} has no semver tag
and is not parser origin/main (${BRANCH_TIP:0:8}).

Refusing to mint a newer parser release tag on an older or detached commit.
Update the submodule to parser main, or pin Package.swift to an existing tag on
the current submodule commit.
EOF
    exit 1
fi

LATEST_TAG=$(git -C "$SUBMODULE_DIR" tag -l --sort=-v:refname \
    | grep -E "$SEMVER_REGEX" \
    | head -1)
if [[ -z "$LATEST_TAG" ]]; then
    echo "Error: no tags found on AccessibilitySnapshotBH"
    exit 1
fi
echo "Latest tag: $LATEST_TAG"

IFS='.' read -r MAJOR MINOR PATCH <<< "$LATEST_TAG"
NEW_TAG="${MAJOR}.$((MINOR + 1)).0"
echo "New tag: $NEW_TAG (on ${SUBMODULE_SHA:0:8})"
echo "Package.swift pin: $CURRENT_PIN → $NEW_TAG"

if [[ "$DRY_RUN" == true ]]; then
    echo ""
    echo "(dry run — no changes made)"
    exit 0
fi

git -C "$SUBMODULE_DIR" tag "$NEW_TAG" "$SUBMODULE_SHA"
git -C "$SUBMODULE_DIR" push origin "$NEW_TAG"
echo "✓ Tagged $NEW_TAG on AccessibilitySnapshotBH"

sed -i '' "s|exact: \"$CURRENT_PIN\"|exact: \"$NEW_TAG\"|" "$PACKAGE_FILE"
echo "✓ Bumped Package.swift"

git add "$PACKAGE_FILE"
git commit -m "Bump AccessibilitySnapshotBH $CURRENT_PIN → $NEW_TAG"
echo "✓ Committed"
