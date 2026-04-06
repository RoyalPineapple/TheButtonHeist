#!/usr/bin/env bash
# Release script for Button Heist.
#
# Performs the full release pipeline from a clean main branch:
#   1. Validate: must be on main, in sync with origin, clean worktree
#   2. Bump version across 5 files + regenerate Xcode projects
#   3. Build all targets (TheScore, ButtonHeist, TheInsideJob, CLI, MCP)
#   4. Run all tests (TheScoreTests, ButtonHeistTests, TheInsideJobTests)
#   5. Commit, tag, push
#   6. Wait for CI release workflow; upgrade Homebrew on success, rollback on failure
#
# The release workflow (triggered by the tag push):
#   - Builds universal binaries (arm64 + x86_64)
#   - Creates the GitHub release with artifacts
#   - Updates the Homebrew tap with real SHA-256 hashes
#
# Idempotent: if CI fails, the script deletes the tag, reverts the
# version bump, and cleans up the GitHub release — re-run to retry.
#
# Usage: ./scripts/release.sh [--dry-run] [<version>]
# Example: ./scripts/release.sh              # Uses today's date: 2026.04.03
#          ./scripts/release.sh              # Same day again: auto-increments to 2026.04.03.1
#          ./scripts/release.sh 2026.04.03   # Explicit CalVer
#          ./scripts/release.sh --dry-run    # Preview only
#
# See VERSIONING.md in bh-infra for versioning rules.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CALVER_REGEX='^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$'
GITHUB_REPO="RoyalPineapple/TheButtonHeist"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

# Default to today's date; auto-increment patch if today's version is already released
if [[ $# -lt 1 ]]; then
    BASE_DATE="$(date +%Y.%m.%d)"
    if git tag -l "v$BASE_DATE" | grep -q .; then
        PATCH=1
        while git tag -l "v${BASE_DATE}.${PATCH}" | grep -q .; do
            PATCH=$((PATCH + 1))
        done
        NEW_VERSION="${BASE_DATE}.${PATCH}"
    else
        NEW_VERSION="$BASE_DATE"
    fi
else
    NEW_VERSION="$1"
fi

if ! [[ "$NEW_VERSION" =~ $CALVER_REGEX ]]; then
    echo "Error: '$NEW_VERSION' is not a valid CalVer (e.g. 2026.04.03, 2026.04.03.1)"
    exit 1
fi

# --------------------------------------------------------------------------
# Phase 1: Validate preconditions
# --------------------------------------------------------------------------

echo "==> Phase 1: Validating preconditions"

# Must be on the main branch at the same commit as origin/main
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "Error: must be on the main branch (currently on '$CURRENT_BRANCH')"
    echo "  git checkout main"
    exit 1
fi

git fetch origin main --quiet
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse origin/main)
if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
    echo "Error: HEAD ($LOCAL_SHA) is not at origin/main ($REMOTE_SHA)"
    echo "  git pull origin main   # or: git reset --hard origin/main"
    exit 1
fi

# Clean worktree
if [[ -n $(git status --porcelain) ]]; then
    echo "Error: worktree is not clean"
    echo "  git status"
    exit 1
fi

# Read current version
CURRENT_VERSION=$(grep -o 'buttonHeistVersion = "[^"]*"' ButtonHeist/Sources/TheScore/Messages.swift | cut -d'"' -f2)

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo "Error: version is already $NEW_VERSION and tag v$NEW_VERSION exists."
    echo "  To cut a same-day patch, omit the version argument and the script will auto-increment:"
    echo "    ./scripts/release.sh"
    exit 1
fi

# Tag must not exist
if [[ -n $(git tag -l "v$NEW_VERSION" 2>/dev/null) ]]; then
    echo "Error: tag v$NEW_VERSION already exists."
    echo "  To cut a same-day patch, omit the version argument and the script will auto-increment:"
    echo "    ./scripts/release.sh"
    exit 1
fi

echo "  HEAD: in sync with origin/main"
echo "  Worktree: clean"
echo "  Version: $CURRENT_VERSION -> $NEW_VERSION"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "(dry run — stopping after validation)"
    echo ""
    echo "Would perform:"
    echo "  1. Bump version in 5 files + regenerate Xcode projects"
    echo "  2. Build TheScore, ButtonHeist, TheInsideJob, CLI, MCP"
    echo "  3. Run TheScoreTests, ButtonHeistTests, TheInsideJobTests"
    echo "  4. Commit 'Release $NEW_VERSION', tag v$NEW_VERSION, push"
    echo "  5. Wait for CI release workflow"
    echo "  6. On success: upgrade Homebrew. On failure: rollback tag + commit"
    exit 0
fi

# --------------------------------------------------------------------------
# Phase 2: Bump version
# --------------------------------------------------------------------------

echo "==> Phase 2: Bumping version"

escape_sed_pattern() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/\./\\./g; s/[*\[\]^$+?(){}|]/\\&/g'
}
escape_sed_replacement() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/&/\\&/g'
}

CURRENT_ESC=$(escape_sed_pattern "$CURRENT_VERSION")
NEW_ESC=$(escape_sed_replacement "$NEW_VERSION")

# 1. TheScore/Messages.swift (canonical source of truth)
sed -i '' "s/buttonHeistVersion = \"$CURRENT_ESC\"/buttonHeistVersion = \"$NEW_ESC\"/" \
    ButtonHeist/Sources/TheScore/Messages.swift
echo "  ✓ Messages.swift"

# 2. VERSION file
echo "$NEW_VERSION" > VERSION
echo "  ✓ VERSION"

# 3. docs/API.md
sed -i '' "s/\*\*Version\*\*: $CURRENT_ESC/**Version**: $NEW_ESC/" docs/API.md
echo "  ✓ docs/API.md"

# 4. TestApp demo
sed -i '' "s/LabeledContent(\"Version\", value: \"$CURRENT_ESC\")/LabeledContent(\"Version\", value: \"$NEW_ESC\")/" \
    TestApp/Sources/DisclosureGroupingDemo.swift
echo "  ✓ DisclosureGroupingDemo.swift"

# 5. Formula/buttonheist.rb (in-repo template — PLACEHOLDERs stay, CI fills them)
sed -i '' "s/version \"$CURRENT_ESC\"/version \"$NEW_ESC\"/" Formula/buttonheist.rb
echo "  ✓ Formula/buttonheist.rb"

# 6. Regenerate Xcode projects so pbxproj files stay in sync
echo "  Regenerating Xcode projects..."
tuist generate --no-open
echo "  ✓ Xcode projects"
echo ""

# --------------------------------------------------------------------------
# Phase 3: Build
# --------------------------------------------------------------------------

echo "==> Phase 3: Building all targets"

echo "  Building TheScore..."
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheScore build -quiet
echo "  ✓ TheScore"

echo "  Building ButtonHeist..."
xcodebuild -workspace ButtonHeist.xcworkspace -scheme ButtonHeist build -quiet
echo "  ✓ ButtonHeist"

echo "  Building TheInsideJob..."
xcodebuild -workspace ButtonHeist.xcworkspace -scheme TheInsideJob \
    -destination 'generic/platform=iOS' build -quiet
echo "  ✓ TheInsideJob"

echo "  Building CLI..."
(cd ButtonHeistCLI && swift build -c release --quiet)
echo "  ✓ CLI"

echo "  Building MCP..."
(cd ButtonHeistMCP && swift build -c release --quiet)
echo "  ✓ MCP"

# Verify CLI version
CLI_VERSION=$(ButtonHeistCLI/.build/release/buttonheist --version)
if [[ "$CLI_VERSION" != "$NEW_VERSION" ]]; then
    echo "Error: CLI reports '$CLI_VERSION', expected '$NEW_VERSION'"
    echo "  Reverting version changes..."
    git checkout -- .
    exit 1
fi
echo "  ✓ CLI --version reports $NEW_VERSION"
echo ""

# --------------------------------------------------------------------------
# Phase 4: Test
# --------------------------------------------------------------------------

echo "==> Phase 4: Running tests"

echo "  Running TheScoreTests..."
tuist test TheScoreTests --no-selective-testing
echo "  ✓ TheScoreTests"

echo "  Running ButtonHeistTests..."
tuist test ButtonHeistTests --no-selective-testing
echo "  ✓ ButtonHeistTests"

# Find or create a simulator for iOS tests
SIM_NAME="release-test-$$"
SIM_RUNTIME=$(xcrun simctl list runtimes | grep "iOS 26" | tail -1 | sed 's/.*- //')
if [[ -z "$SIM_RUNTIME" ]]; then
    echo "  Warning: no iOS 26 runtime found, trying latest available..."
    SIM_RUNTIME=$(xcrun simctl list runtimes | grep "iOS" | tail -1 | sed 's/.*- //')
fi
SIM_UDID=$(xcrun simctl create "$SIM_NAME" "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro" "$SIM_RUNTIME")
xcrun simctl boot "$SIM_UDID" 2>/dev/null || true

echo "  Running TheInsideJobTests on $SIM_NAME..."
tuist test TheInsideJobTests --platform ios --device "$SIM_NAME" --no-selective-testing
echo "  ✓ TheInsideJobTests"

# Clean up test simulator
xcrun simctl shutdown "$SIM_UDID" 2>/dev/null || true
xcrun simctl delete "$SIM_UDID" 2>/dev/null || true
echo ""

# --------------------------------------------------------------------------
# Phase 5: Commit, tag, push
# --------------------------------------------------------------------------

echo "==> Phase 5: Committing and tagging"

git add \
    ButtonHeist/Sources/TheScore/Messages.swift \
    VERSION \
    docs/API.md \
    TestApp/Sources/DisclosureGroupingDemo.swift \
    Formula/buttonheist.rb \
    -- '*.pbxproj' '*.xcworkspacedata'

git commit -m "Release $NEW_VERSION"
git tag "v$NEW_VERSION"
git push origin HEAD:main
git push origin "v$NEW_VERSION"

echo "  ✓ Committed, tagged v$NEW_VERSION, pushed"
echo ""

# --------------------------------------------------------------------------
# Phase 6: Wait for CI and upgrade Homebrew
# --------------------------------------------------------------------------

echo "==> Phase 6: Waiting for release workflow"

# Find the workflow run triggered by the tag push
for _ in 1 2 3 4 5; do
    RUN_ID=$(gh run list --repo "$GITHUB_REPO" --branch "v$NEW_VERSION" --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
    if [[ -n "$RUN_ID" ]]; then break; fi
    sleep 2
done

if [[ -z "${RUN_ID:-}" ]]; then
    echo "  Could not find release workflow run for v$NEW_VERSION."
    echo "  Check manually: https://github.com/$GITHUB_REPO/actions"
    echo "  Then run: brew update && brew upgrade royalpineapple/tap/buttonheist"
else
    echo "  Watching run $RUN_ID..."
    if gh run watch "$RUN_ID" --repo "$GITHUB_REPO" --exit-status; then
        echo ""
        echo "  ✓ Release workflow passed"
        if command -v brew &>/dev/null && brew list royalpineapple/tap/buttonheist &>/dev/null; then
            echo "  Upgrading Homebrew..."
            brew update --quiet
            brew upgrade royalpineapple/tap/buttonheist
            echo "  ✓ Homebrew upgraded to $(buttonheist --version)"
        fi
    else
        echo ""
        echo "  ✗ Release workflow failed — rolling back"
        echo ""

        # Delete remote and local tag
        git push origin --delete "v$NEW_VERSION" 2>/dev/null || true
        git tag -d "v$NEW_VERSION" 2>/dev/null || true
        echo "  ✓ Deleted tag v$NEW_VERSION"

        # Revert the version bump commit, but only if HEAD is actually the release commit
        RELEASE_MSG="Release $NEW_VERSION"
        if [[ "$(git log -1 --format=%s)" == "$RELEASE_MSG" ]]; then
            git revert --no-edit HEAD
            git push origin HEAD:main
            echo "  ✓ Reverted version bump on main"
        else
            echo "  ⚠ HEAD is not the release commit — skipping revert (manual cleanup needed)"
        fi

        # Delete the failed GitHub release if one was created
        gh release delete "v$NEW_VERSION" --repo "$GITHUB_REPO" --yes 2>/dev/null || true
        echo "  ✓ Cleaned up GitHub release"

        echo ""
        echo "  Release rolled back. Fix the issue and re-run:"
        echo "    ./scripts/release.sh $NEW_VERSION"
        exit 1
    fi
fi
echo ""

# --------------------------------------------------------------------------
# Done
# --------------------------------------------------------------------------

echo "========================================="
echo "  Release $NEW_VERSION complete"
echo "========================================="
echo ""
echo "  Tag:      v$NEW_VERSION"
echo ""
