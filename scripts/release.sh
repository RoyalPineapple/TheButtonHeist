#!/usr/bin/env bash
# Release script for Button Heist. Updates version across all files.
# Usage: ./scripts/release.sh [--dry-run] <version>
# Example: ./scripts/release.sh 0.0.2
#
# See docs/VERSIONING.md for SemVer rules and release workflow.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# SemVer regex: MAJOR.MINOR.PATCH (optional pre-release and build metadata)
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(-[a-zA-Z0-9.-]+)?(\+[a-zA-Z0-9.-]+)?$'

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

usage() {
    echo "Usage: $0 [--dry-run] <version>"
    echo ""
    echo "Bumps the product version to the given SemVer string."
    echo "Example: $0 0.0.2"
    echo ""
    echo "Options:"
    echo "  --dry-run    Show what would be changed without modifying files"
    echo ""
    echo "Files updated:"
    echo "  - ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift"
    echo "  - VERSION"
    echo "  - docs/API.md"
    echo "  - TestApp/Sources/DisclosureGroupingDemo.swift"
    echo "  - docs/VERSIONING.md"
    echo ""
    echo "After running, commit and tag: git tag v<VERSION>"
    exit 1
}

if [[ $# -lt 1 ]]; then
    usage
fi

NEW_VERSION="$1"
if ! [[ "$NEW_VERSION" =~ $SEMVER_REGEX ]]; then
    echo "Error: '$NEW_VERSION' is not a valid SemVer (e.g. 0.0.2, 1.0.0)"
    exit 1
fi

# Read current version from source of truth
CURRENT_VERSION=$(grep -o 'buttonHeistVersion = "[^"]*"' ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift | cut -d'"' -f2)

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo "Version is already $NEW_VERSION. Nothing to do."
    exit 0
fi

# Reject if tag already exists (version already released)
if [[ -n $(git tag -l "v$NEW_VERSION" 2>/dev/null) ]]; then
    echo "Error: tag v$NEW_VERSION already exists. Cannot release an already-released version."
    exit 1
fi

echo "Bumping version: $CURRENT_VERSION -> $NEW_VERSION"
[[ "$DRY_RUN" == true ]] && echo "(dry run — no files modified)"
echo ""

# Escape version for literal match in sed pattern (escape . * [ ] \ ^ $ + ? ( ) { } |)
escape_sed_pattern() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/\./\\./g; s/[*\[\]^$+?(){}|]/\\&/g'
}
# Escape version for sed replacement (escape \ and &)
escape_sed_replacement() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/&/\\&/g'
}

CURRENT_ESC=$(escape_sed_pattern "$CURRENT_VERSION")
NEW_ESC=$(escape_sed_replacement "$NEW_VERSION")

# 1. TheFence+CommandCatalog.swift
if [[ "$DRY_RUN" == true ]]; then
    echo "  Would update: buttonHeistVersion = \"$NEW_VERSION\" in TheFence+CommandCatalog.swift"
else
    sed -i '' "s/buttonHeistVersion = \"$CURRENT_ESC\"/buttonHeistVersion = \"$NEW_ESC\"/" \
        ButtonHeist/Sources/TheButtonHeist/TheFence+CommandCatalog.swift
fi
echo "  ✓ TheFence+CommandCatalog.swift"

# 2. VERSION file
if [[ "$DRY_RUN" == true ]]; then
    echo "  Would write: $NEW_VERSION to VERSION"
else
    echo "$NEW_VERSION" > VERSION
fi
echo "  ✓ VERSION"

# 3. docs/API.md
if [[ "$DRY_RUN" == true ]]; then
    echo "  Would update: **Version**: $NEW_VERSION in docs/API.md"
else
    sed -i '' "s/\*\*Version\*\*: $CURRENT_ESC/**Version**: $NEW_ESC/" docs/API.md
fi
echo "  ✓ docs/API.md"

# 4. TestApp demo
if [[ "$DRY_RUN" == true ]]; then
    echo "  Would update: LabeledContent(\"Version\", value: \"$NEW_VERSION\") in DisclosureGroupingDemo.swift"
else
    sed -i '' "s/LabeledContent(\"Version\", value: \"$CURRENT_ESC\")/LabeledContent(\"Version\", value: \"$NEW_ESC\")/" \
        TestApp/Sources/DisclosureGroupingDemo.swift
fi
echo "  ✓ TestApp/Sources/DisclosureGroupingDemo.swift"

# 5. docs/VERSIONING.md "Current version" line
if [[ "$DRY_RUN" == true ]]; then
    echo "  Would update: **$NEW_VERSION** in docs/VERSIONING.md"
else
    sed -i '' "s/\*\*$CURRENT_ESC\*\*/**$NEW_ESC**/" docs/VERSIONING.md
fi
echo "  ✓ docs/VERSIONING.md"

echo ""
[[ "$DRY_RUN" == true ]] && exit 0
echo "Done. Next steps:"
echo "  1. Run full build and tests (see CLAUDE.md Pre-Commit Checklist)"
echo "  2. git add -A && git commit -m 'Release $NEW_VERSION'"
echo "  3. git tag v$NEW_VERSION"
