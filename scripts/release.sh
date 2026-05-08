#!/usr/bin/env bash
# Release script for Button Heist.
#
# Performs the full release pipeline from a clean main branch:
#   1. Validate: must be on main, in sync with origin, clean worktree
#   2. Bump version across 5 files + regenerate Xcode projects
#   3. Build CLI + MCP (in parallel)
#   4. Rebase onto latest origin, commit, tag, push
#   5. Wait for CI release workflow; upgrade Homebrew on success, rollback on failure
#
# Tests are skipped by default — CI already ran them on the same commit.
# Use --full to run local tests before committing.
#
# Versioning: SemVer (MAJOR.MINOR.PATCH). Default bump is patch.
#
# Usage: ./scripts/release.sh [--dry-run] [--full] [--major | --minor | <version>]
# Example: ./scripts/release.sh              # Bump patch: 0.2.0 -> 0.2.1
#          ./scripts/release.sh --minor      # Bump minor: 0.2.1 -> 0.3.0
#          ./scripts/release.sh --major      # Bump major: 0.3.0 -> 1.0.0
#          ./scripts/release.sh 0.5.0        # Explicit version
#          ./scripts/release.sh --dry-run    # Preview only
#          ./scripts/release.sh --full       # Run local tests before committing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'
GITHUB_REPO="RoyalPineapple/TheButtonHeist"

DRY_RUN=false
RUN_TESTS=false
BUMP_TYPE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    DRY_RUN=true; shift ;;
        --full)       RUN_TESTS=true; shift ;;
        --skip-tests) shift ;;  # legacy flag, tests skip by default now
        --major)      BUMP_TYPE="major"; shift ;;
        --minor)      BUMP_TYPE="minor"; shift ;;
        --patch)      BUMP_TYPE="patch"; shift ;;
        -*)           echo "Error: unknown flag '$1'"; exit 1 ;;
        *)            break ;;
    esac
done

# Read current version
CURRENT_VERSION=$(grep -o 'buttonHeistVersion = "[^"]*"' ButtonHeist/Sources/TheScore/Messages.swift | cut -d'"' -f2)

if [[ $# -ge 1 ]]; then
    NEW_VERSION="$1"
elif [[ -n "$BUMP_TYPE" ]]; then
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    case "$BUMP_TYPE" in
        major) NEW_VERSION="$((MAJOR + 1)).0.0" ;;
        minor) NEW_VERSION="${MAJOR}.$((MINOR + 1)).0" ;;
        patch) NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))" ;;
    esac
else
    # Default: bump patch
    IFS='.' read -r MAJOR MINOR PATCH <<< "$CURRENT_VERSION"
    NEW_VERSION="${MAJOR}.${MINOR}.$((PATCH + 1))"
fi

if ! [[ "$NEW_VERSION" =~ $SEMVER_REGEX ]]; then
    echo "Error: '$NEW_VERSION' is not valid semver (e.g. 0.2.0, 1.0.0)"
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

# CI must have passed on this commit — wait up to 20 minutes
if [[ "$RUN_TESTS" == false ]]; then
    echo "  Waiting for CI on $(echo "$LOCAL_SHA" | cut -c1-8)..."
    CI_DEADLINE=$((SECONDS + 1200))
    CI_RUN_ID=""
    while [[ $SECONDS -lt $CI_DEADLINE ]]; do
        CI_RUN_ID=$(gh run list --repo "$GITHUB_REPO" --commit "$LOCAL_SHA" --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
        if [[ -n "$CI_RUN_ID" && "$CI_RUN_ID" != "null" ]]; then break; fi
        sleep 5
    done
    if [[ -z "$CI_RUN_ID" || "$CI_RUN_ID" == "null" ]]; then
        echo "Error: no CI run found after 20 minutes"
        echo "  Check: https://github.com/$GITHUB_REPO/actions"
        echo "  Or run with --full to test locally"
        exit 1
    fi
    if ! gh run watch "$CI_RUN_ID" --repo "$GITHUB_REPO" --exit-status; then
        echo "Error: CI failed on $(echo "$LOCAL_SHA" | cut -c1-8)"
        echo "  https://github.com/$GITHUB_REPO/actions/runs/$CI_RUN_ID"
        exit 1
    fi
    echo "  CI: passed on $(echo "$LOCAL_SHA" | cut -c1-8)"
fi

# Clean worktree
if [[ -n $(git status --porcelain) ]]; then
    echo "Error: worktree is not clean"
    echo "  git status"
    exit 1
fi

if [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    echo "Error: version is already $NEW_VERSION."
    exit 1
fi

# Tag must not exist
if [[ -n $(git tag -l "v$NEW_VERSION" 2>/dev/null) ]]; then
    echo "Error: tag v$NEW_VERSION already exists."
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
    echo "  2. Build CLI + MCP (parallel)"
    if [[ "$RUN_TESTS" == true ]]; then
        echo "  3. Run TheScoreTests, ButtonHeistTests, TheInsideJobTests"
    else
        echo "  3. (tests skipped — CI already ran them. Use --full to run locally)"
    fi
    echo "  4. Rebase, commit 'Release $NEW_VERSION', tag v$NEW_VERSION, push"
    echo "  5. Wait for CI release workflow"
    echo "  6. On success: upgrade Homebrew. On failure: rollback tag + commit"
    exit 0
fi

# --------------------------------------------------------------------------
# Phase 2: Bump version
# --------------------------------------------------------------------------

echo "==> Phase 2: Bumping version"

# From this point, any failure should revert uncommitted version bumps
cleanup_version_bump() {
    if [[ -n $(git status --porcelain) ]]; then
        echo ""
        echo "  Reverting uncommitted version bump..."
        git checkout -- .
        echo "  ✓ Worktree restored to clean state"
    fi
}
trap cleanup_version_bump EXIT

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

# 2. RELEASE_VERSION file
echo "$NEW_VERSION" > RELEASE_VERSION
echo "  ✓ RELEASE_VERSION"

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
# Phase 3: Build CLI + MCP (parallel)
# --------------------------------------------------------------------------

echo "==> Phase 3: Building CLI + MCP"

rm -rf ButtonHeistCLI/.build ButtonHeistMCP/.build

CLI_LOG=$(mktemp)
MCP_LOG=$(mktemp)

(cd ButtonHeistCLI && swift build -c release --quiet 2>&1) > "$CLI_LOG" 2>&1 &
CLI_PID=$!

(cd ButtonHeistMCP && swift build -c release --quiet 2>&1) > "$MCP_LOG" 2>&1 &
MCP_PID=$!

CLI_OK=true
MCP_OK=true

if ! wait "$CLI_PID"; then
    CLI_OK=false
fi
if ! wait "$MCP_PID"; then
    MCP_OK=false
fi

if [[ "$CLI_OK" == true ]]; then
    echo "  ✓ CLI"
else
    echo "  ✗ CLI build failed:"
    cat "$CLI_LOG"
    rm -f "$CLI_LOG" "$MCP_LOG"
    exit 1
fi

if [[ "$MCP_OK" == true ]]; then
    echo "  ✓ MCP"
else
    echo "  ✗ MCP build failed:"
    cat "$MCP_LOG"
    rm -f "$CLI_LOG" "$MCP_LOG"
    exit 1
fi

rm -f "$CLI_LOG" "$MCP_LOG"

# Verify CLI version
CLI_VERSION=$(ButtonHeistCLI/.build/release/buttonheist --version)
if [[ "$CLI_VERSION" != "$NEW_VERSION" ]]; then
    echo "Error: CLI reports '$CLI_VERSION', expected '$NEW_VERSION'"
    exit 1
fi
echo "  ✓ CLI --version reports $NEW_VERSION"
echo ""

# --------------------------------------------------------------------------
# Phase 4: Test
# --------------------------------------------------------------------------

if [[ "$RUN_TESTS" == true ]]; then
    echo "==> Phase 4: Running tests (--full)"

    rm -rf ~/Library/Developer/Xcode/DerivedData/ButtonHeist-*

    echo "  Running TheScoreTests..."
    tuist test TheScoreTests --no-selective-testing
    echo "  ✓ TheScoreTests"

    echo "  Running ButtonHeistTests..."
    tuist test ButtonHeistTests --no-selective-testing
    echo "  ✓ ButtonHeistTests"

    # Reuse a persistent release-test simulator instead of create/boot/delete
    SIM_NAME="release-test"
    SIM_UDID=$(xcrun simctl list devices | grep "$SIM_NAME" | grep -oE '[0-9A-F-]{36}' | head -1 || true)

    if [[ -z "$SIM_UDID" ]]; then
        SIM_RUNTIME=$(xcrun simctl list runtimes | grep "iOS 26" | tail -1 | sed 's/.*- //')
        if [[ -z "$SIM_RUNTIME" ]]; then
            SIM_RUNTIME=$(xcrun simctl list runtimes | grep "iOS" | tail -1 | sed 's/.*- //')
        fi
        SIM_UDID=$(xcrun simctl create "$SIM_NAME" "com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro" "$SIM_RUNTIME")
        echo "  Created simulator $SIM_NAME ($SIM_UDID)"
    fi

    # Boot only if not already booted
    SIM_STATE=$(xcrun simctl list devices | grep "$SIM_UDID" | grep -o '(Booted)' || true)
    if [[ -z "$SIM_STATE" ]]; then
        xcrun simctl boot "$SIM_UDID" 2>/dev/null || true
        echo "  Booted $SIM_NAME"
    else
        echo "  Reusing booted $SIM_NAME"
    fi

    echo "  Running TheInsideJobTests on $SIM_NAME..."
    tuist test TheInsideJobTests --platform ios --device "$SIM_NAME" --no-selective-testing
    echo "  ✓ TheInsideJobTests"
    echo ""
fi

# --------------------------------------------------------------------------
# Phase 5: Commit, tag, push
# --------------------------------------------------------------------------

echo "==> Phase 5: Committing and tagging"

# Regenerate right before commit so the pre-commit hook's tuist generate
# produces identical output (build artifacts can shift cache state)
tuist generate --no-open

git add \
    ButtonHeist/Sources/TheScore/Messages.swift \
    RELEASE_VERSION \
    docs/API.md \
    TestApp/Sources/DisclosureGroupingDemo.swift \
    Formula/buttonheist.rb \
    -- '*.pbxproj' '*.xcworkspacedata' '*.xcscheme'

git commit -m "Release $NEW_VERSION"
git tag "v$NEW_VERSION"

# Rebase onto latest origin to avoid push rejection if main moved
git fetch origin main --quiet
if [[ "$(git rev-parse origin/main)" != "$(git rev-parse HEAD~1)" ]]; then
    echo "  Origin moved during release — rebasing..."
    git tag -d "v$NEW_VERSION"
    git rebase origin/main
    git tag "v$NEW_VERSION"
    echo "  ✓ Rebased onto latest origin/main"
fi

git push origin HEAD:main
git push origin "v$NEW_VERSION"

# Version bump is committed — disable the cleanup trap
trap - EXIT

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
