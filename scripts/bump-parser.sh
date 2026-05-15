#!/usr/bin/env bash
# Bump the AccessibilitySnapshotBH dependency.
#
# Tags the current submodule commit on the AccessibilitySnapshotBH repo
# with the next minor version, then bumps Package.swift to match.
#
# Usage: ./scripts/bump-parser.sh [--dry-run]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

DRY_RUN=false
[[ "${1:-}" == "--dry-run" ]] && DRY_RUN=true

SUBMODULE_DIR="submodules/AccessibilitySnapshotBH"
PACKAGE_FILE="Package.swift"

if [[ ! -d "$SUBMODULE_DIR/.git" ]] && [[ ! -f "$SUBMODULE_DIR/.git" ]]; then
    echo "Error: submodule not initialized at $SUBMODULE_DIR"
    echo "  git submodule update --init --recursive"
    exit 1
fi

SUBMODULE_SHA=$(git -C "$SUBMODULE_DIR" rev-parse HEAD)
echo "Submodule commit: ${SUBMODULE_SHA:0:8}"

CURRENT_PIN=$(grep 'AccessibilitySnapshotBH' "$PACKAGE_FILE" | grep -oE 'from: "[0-9]+\.[0-9]+\.[0-9]+"' | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
if [[ -z "$CURRENT_PIN" ]]; then
    echo "Error: could not find AccessibilitySnapshotBH version pin in $PACKAGE_FILE"
    exit 1
fi

LATEST_TAG=$(git -C "$SUBMODULE_DIR" tag -l --sort=-v:refname | head -1)
if [[ -z "$LATEST_TAG" ]]; then
    echo "Error: no tags found on AccessibilitySnapshotBH"
    exit 1
fi
echo "Latest tag: $LATEST_TAG"

TAGGED_SHA=$(git -C "$SUBMODULE_DIR" rev-parse "$LATEST_TAG^{}")
if [[ "$SUBMODULE_SHA" == "$TAGGED_SHA" ]]; then
    if [[ "$CURRENT_PIN" == "$LATEST_TAG" ]]; then
        echo "Submodule and Package.swift are already at $LATEST_TAG — nothing to bump."
        exit 0
    fi

    echo "Submodule is already at $LATEST_TAG; Package.swift pin is $CURRENT_PIN."
    echo "Package.swift pin: $CURRENT_PIN → $LATEST_TAG"
    if [[ "$DRY_RUN" == true ]]; then
        echo ""
        echo "(dry run — no changes made)"
        exit 0
    fi

    sed -i '' "s|from: \"$CURRENT_PIN\"|from: \"$LATEST_TAG\"|" "$PACKAGE_FILE"
    git add "$PACKAGE_FILE"
    git commit -m "Bump AccessibilitySnapshotBH $CURRENT_PIN → $LATEST_TAG"
    echo "✓ Bumped Package.swift"
    echo "✓ Committed"
    exit 0
fi

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

sed -i '' "s|from: \"$CURRENT_PIN\"|from: \"$NEW_TAG\"|" "$PACKAGE_FILE"
echo "✓ Bumped Package.swift"

git add "$PACKAGE_FILE"
git commit -m "Bump AccessibilitySnapshotBH $CURRENT_PIN → $NEW_TAG"
echo "✓ Committed"
