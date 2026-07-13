#!/usr/bin/env bash
# Release script for Button Heist.
#
# Performs the full release pipeline from a clean main branch:
#   1. Validate: must be on main, in sync with origin, clean worktree
#   2. Prepare parser projections and derive version mirrors from TheScore
#   3. Build CLI + MCP (in parallel)
#   4. Rebase onto latest origin, commit, push source to main, and wait for CI
#   5. Tag the exact green main commit and wait for release packaging
#
# Local tests are skipped by default — main-branch CI gates the exact release
# commit before the tag is pushed and release artifacts are published.
# Use --full for an optional local preflight before committing.
#
# Versioning: SemVer (MAJOR.MINOR.PATCH). Default bump is patch.
#
# Usage: ./scripts/release.sh [--dry-run] [--full] [--major | --minor | <version>]
#        ./scripts/release.sh --tag-current [--dry-run] [--full]
# Example: ./scripts/release.sh              # Bump patch: 0.2.0 -> 0.2.1
#          ./scripts/release.sh --minor      # Bump minor: 0.2.1 -> 0.3.0
#          ./scripts/release.sh --major      # Bump major: 0.3.0 -> 1.0.0
#          ./scripts/release.sh 0.5.0        # Explicit version
#          ./scripts/release.sh --tag-current # Publish the already-bumped source version
#          ./scripts/release.sh --dry-run    # Preview only
#          ./scripts/release.sh --full       # Run optional local tests before committing

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'

# shellcheck source=scripts/release-contract.sh
source "$SCRIPT_DIR/release-contract.sh"

DRY_RUN=false
RUN_TESTS=false
TAG_CURRENT=false
BUMP_TYPE=""

run_tuist_test() {
    local receipts_dir="${BUTTONHEIST_RECEIPTS_DIR:-$REPO_ROOT/.rp1/work/heist-receipts/release}"
    local receipts_mode="${BUTTONHEIST_RECEIPTS_MODE:-failing-and-passing}"
    set +e
    BUTTONHEIST_TUIST_SKIP_AUTO_CLEAN=1 \
        scripts/run-with-heist-receipts.sh \
        --dir "$receipts_dir" \
        --mode "$receipts_mode" \
        -- tuist test "$@"
    local test_status=$?
    set -e

    scripts/clean-generated-projects.sh

    return "$test_status"
}

local_release_tag_exists() {
    local version="$1"
    git show-ref --verify --quiet "refs/tags/v$version"
}

remote_release_tag_exists() {
    local version="$1"
    git ls-remote --exit-code --tags origin "refs/tags/v$version" >/dev/null 2>&1
}

release_tag_exists() {
    local version="$1"
    local_release_tag_exists "$version" || remote_release_tag_exists "$version"
}

ci_push_run_count() {
    local sha="$1"
    local jq_filter="$2"
    gh run list \
        --repo "$BUTTONHEIST_GITHUB_REPO" \
        --workflow CI \
        --branch main \
        --commit "$sha" \
        --limit 20 \
        --json conclusion,event,status \
        --jq "$jq_filter" 2>/dev/null || echo 0
}

print_ci_runs_for_commit() {
    local sha="$1"
    gh run list \
        --repo "$BUTTONHEIST_GITHUB_REPO" \
        --workflow CI \
        --branch main \
        --commit "$sha" \
        --limit 20 || true
}

wait_for_ci_success() {
    local sha="$1"
    local label="${2:-release commit}"
    local success_count running_count failed_count total_count

    echo "  Waiting for main CI on $label (${sha:0:8})..."
    for _ in {1..160}; do
        success_count=$(ci_push_run_count "$sha" '[.[] | select(.event == "push" and .status == "completed" and .conclusion == "success")] | length')
        if [[ "$success_count" -gt 0 ]]; then
            echo "  ✓ Main CI passed on ${sha:0:8}"
            return 0
        fi

        running_count=$(ci_push_run_count "$sha" '[.[] | select(.event == "push" and .status != "completed")] | length')
        failed_count=$(ci_push_run_count "$sha" '[.[] | select(.event == "push" and .status == "completed" and .conclusion != "success")] | length')
        total_count=$(ci_push_run_count "$sha" '[.[] | select(.event == "push")] | length')
        if [[ "$failed_count" -gt 0 && "$running_count" -eq 0 && "$total_count" -gt 0 ]]; then
            echo "  ✗ Main CI failed on ${sha:0:8}"
            print_ci_runs_for_commit "$sha"
            echo ""
            echo "  The release source commit is already on main. Fix main before tagging this version."
            return 1
        fi

        sleep 15
    done

    echo "  ✗ Timed out waiting for main CI on ${sha:0:8}"
    print_ci_runs_for_commit "$sha"
    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)    DRY_RUN=true; shift ;;
        --full)       RUN_TESTS=true; shift ;;
        --skip-tests) echo "Error: --skip-tests is not a supported release flag; local tests already skip by default."; exit 1 ;;
        --tag-current) TAG_CURRENT=true; shift ;;
        --major)      BUMP_TYPE="major"; shift ;;
        --minor)      BUMP_TYPE="minor"; shift ;;
        --patch)      BUMP_TYPE="patch"; shift ;;
        -*)           echo "Error: unknown flag '$1'"; exit 1 ;;
        *)            break ;;
    esac
done

# Read the canonical current version.
CURRENT_VERSION=$(grep -o 'buttonHeistVersion = "[^"]*"' "$BUTTONHEIST_CODE_VERSION_FILE" | cut -d'"' -f2)

if [[ "$TAG_CURRENT" == true ]]; then
    if [[ -n "$BUMP_TYPE" || $# -gt 0 ]]; then
        echo "Error: --tag-current cannot be combined with a version or bump flag."
        exit 1
    fi
    NEW_VERSION="$CURRENT_VERSION"
elif [[ $# -ge 1 ]]; then
    if [[ $# -gt 1 ]]; then
        echo "Error: expected at most one explicit version."
        exit 1
    fi
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
    echo "  git pull --ff-only origin main"
    exit 1
fi

# The release may now create only its own derived working-tree changes.
if [[ -n $(git status --porcelain) ]]; then
    echo "Error: worktree is not clean"
    echo "  git status"
    exit 1
fi

cleanup_release_changes() {
    if [[ -n $(git status --porcelain) ]]; then
        echo ""
        echo "  Reverting uncommitted release changes..."
        git checkout -- .
        echo "  ✓ Worktree restored to clean state"
    fi
}
trap cleanup_release_changes EXIT

CURRENT_VERSION_TAG_EXISTS=false
if remote_release_tag_exists "$CURRENT_VERSION"; then
    CURRENT_VERSION_TAG_EXISTS=true
fi

NEW_VERSION_TAG_EXISTS=false
if release_tag_exists "$NEW_VERSION"; then
    NEW_VERSION_TAG_EXISTS=true
fi

if [[ "$TAG_CURRENT" == false && "$CURRENT_VERSION_TAG_EXISTS" == false ]]; then
    cat >&2 <<EOF
Error: checked-in version $CURRENT_VERSION has no v$CURRENT_VERSION tag.

The source tree is already bumped to an unreleased version. That is an
ambiguous release state: a normal release would skip over $CURRENT_VERSION,
while a manual tag-only release can publish a version that was not validated by
the release script.

If $CURRENT_VERSION is the intended release, run:
  ./scripts/release.sh --tag-current

Otherwise restore the checked-in version to the latest released tag before
running a normal bump release.
EOF
    exit 1
fi

# CI must have passed on this commit — wait up to 20 minutes
if [[ "$RUN_TESTS" == false ]]; then
    echo "  Waiting for CI on $(echo "$LOCAL_SHA" | cut -c1-8)..."
    CI_DEADLINE=$((SECONDS + 1200))
    CI_RUN_ID=""
    while [[ $SECONDS -lt $CI_DEADLINE ]]; do
        CI_RUN_ID=$(gh run list --repo "$BUTTONHEIST_GITHUB_REPO" --commit "$LOCAL_SHA" --workflow CI --limit 1 --json databaseId --jq '.[0].databaseId' 2>/dev/null || true)
        if [[ -n "$CI_RUN_ID" && "$CI_RUN_ID" != "null" ]]; then break; fi
        sleep 5
    done
    if [[ -z "$CI_RUN_ID" || "$CI_RUN_ID" == "null" ]]; then
        echo "Error: no CI run found after 20 minutes"
        echo "  Check: https://github.com/$BUTTONHEIST_GITHUB_REPO/actions"
        echo "  Or run with --full to test locally before the main CI release gate"
        exit 1
    fi
    if ! gh run watch "$CI_RUN_ID" --repo "$BUTTONHEIST_GITHUB_REPO" --exit-status; then
        echo "Error: CI failed on $(echo "$LOCAL_SHA" | cut -c1-8)"
        echo "  https://github.com/$BUTTONHEIST_GITHUB_REPO/actions/runs/$CI_RUN_ID"
        exit 1
    fi
    echo "  CI: passed on $(echo "$LOCAL_SHA" | cut -c1-8)"
fi

if [[ "$TAG_CURRENT" == true ]]; then
    if [[ "$NEW_VERSION_TAG_EXISTS" == true ]]; then
        echo "Error: tag v$NEW_VERSION already exists; $NEW_VERSION is already released."
        exit 1
    fi
elif [[ "$CURRENT_VERSION" == "$NEW_VERSION" ]]; then
    if [[ "$NEW_VERSION_TAG_EXISTS" == true ]]; then
        echo "Error: version is already $NEW_VERSION and tag v$NEW_VERSION exists."
    else
        echo "Error: source is already bumped to $NEW_VERSION but tag v$NEW_VERSION is missing."
        echo "  Run './scripts/release.sh --tag-current' to publish the checked-in version intentionally."
    fi
    exit 1
elif [[ "$NEW_VERSION_TAG_EXISTS" == true ]]; then
    echo "Error: tag v$NEW_VERSION already exists."
    exit 1
fi

# Prepare every parser dependency projection only after main and release state
# have passed their side-effect-free gates.
SUBMODULE_DIR="submodules/AccessibilitySnapshotBH"
if [[ -d "$SUBMODULE_DIR" ]]; then
    git submodule update --init --recursive "$SUBMODULE_DIR"
    if [[ "$DRY_RUN" == true ]]; then
        "$SCRIPT_DIR/bump-parser.sh" --dry-run
    else
        "$SCRIPT_DIR/bump-parser.sh"
    fi
    if [[ "$TAG_CURRENT" == true && -n $(git status --porcelain) ]]; then
        echo "Error: --tag-current cannot change parser dependency projections."
        echo "  Commit the parser alignment through a normal release first."
        exit 1
    fi
fi

if [[ "$DRY_RUN" == false ]]; then
    "$SCRIPT_DIR/check-parser-contract.sh"
    echo "  Parser dependency: valid"
else
    echo "  Parser dependency: dry-run projection checked"
fi

echo "  HEAD: in sync with origin/main"
echo "  Release inputs: prepared"
if [[ "$TAG_CURRENT" == true ]]; then
    echo "  Version: $CURRENT_VERSION (tag current source)"
else
    echo "  Version: $CURRENT_VERSION -> $NEW_VERSION"
fi
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "(dry run — stopping after validation)"
    echo ""
    echo "Would perform:"
    if [[ "$TAG_CURRENT" == true ]]; then
        echo "  1. Validate current version in RELEASE_VERSION, source, formula, Homebrew rendering, and parser contract"
    else
        echo "  1. Bump the canonical source version and derive RELEASE_VERSION and formula mirrors"
    fi
    echo "  2. Build CLI + MCP (parallel)"
    if [[ "$RUN_TESTS" == true ]]; then
        echo "  3. Run TheScoreTests, ButtonHeistTests, and all five hosted iOS schemes"
    else
        echo "  3. (local tests skipped — main CI gates the exact release commit. Use --full for local preflight)"
    fi
    if [[ "$TAG_CURRENT" == true ]]; then
        echo "  4. Verify main CI is green on current HEAD"
        echo "  5. Tag current HEAD as v$NEW_VERSION and push the tag"
    else
        echo "  4. Rebase, commit 'Release $NEW_VERSION', and push the source commit to main"
        echo "  5. Wait for main CI on the exact release commit"
        echo "  6. Tag the green release commit as v$NEW_VERSION and push the tag"
    fi
    echo "  7. Wait for release workflow packaging and Homebrew publishing"
    echo "     On release workflow failure: delete tag and keep main fix-forward"
    echo ""
    echo "Smallest local release-readiness preflight:"
    echo "  ./scripts/release-readiness.sh"
    exit 0
fi

# --------------------------------------------------------------------------
# Phase 2: Bump or validate version
# --------------------------------------------------------------------------

if [[ "$TAG_CURRENT" == true ]]; then
    echo "==> Phase 2: Validating current version"
    "$SCRIPT_DIR/validate-release-contract.sh"
    echo "  ✓ release contract"
    echo ""
else
    echo "==> Phase 2: Bumping version"

    "$SCRIPT_DIR/bump-version.sh" "$NEW_VERSION"
    echo "  ✓ canonical version and derived mirrors"

    echo ""
fi

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
    run_tuist_test TheScoreTests --no-selective-testing
    echo "  ✓ TheScoreTests"

    echo "  Running ButtonHeistTests..."
    run_tuist_test ButtonHeistTests --no-selective-testing
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

    run_hosted_release_suite() {
        local suite="$1"
        echo "  Running $suite on $SIM_NAME..."
        run_tuist_test "$suite" --platform ios --device "$SIM_NAME" --no-selective-testing
        echo "  ✓ $suite"
    }

    run_hosted_release_suite TheInsideJobTests
    run_hosted_release_suite DogfoodFeatureFlowTests
    run_hosted_release_suite DogfoodRuntimeContractTests
    run_hosted_release_suite AdversarialMutationTests
    run_hosted_release_suite AdversarialNavigationTests
    echo ""
fi

# --------------------------------------------------------------------------
# Phase 5: Commit, push source, wait for CI, tag
# --------------------------------------------------------------------------

if [[ "$TAG_CURRENT" == true ]]; then
    echo "==> Phase 5: Verifying and tagging current release"
    "$SCRIPT_DIR/validate-release-contract.sh"
    RELEASE_SHA=$(git rev-parse HEAD)
    wait_for_ci_success "$RELEASE_SHA" "current release source"
    git tag "v$NEW_VERSION"
    git push origin "v$NEW_VERSION"
    echo "  ✓ Tagged green HEAD as v$NEW_VERSION and pushed"
else
    echo "==> Phase 5: Committing release source"

    git add \
        ButtonHeist/Sources/TheScore/Wire/Messages.swift \
        "$BUTTONHEIST_RELEASE_VERSION_FILE" \
        "$BUTTONHEIST_FORMULA_TEMPLATE"

    while IFS= read -r parser_projection; do
        [[ -n "$parser_projection" ]] || continue
        git add -- "$parser_projection"
    done < <(git diff --name-only -- '*Package.swift' '*Package.resolved')

    git commit -m "Release $NEW_VERSION"

    # Release inputs are committed. Rebase failures must preserve their state
    # for diagnosis rather than invoking working-tree cleanup.
    trap - EXIT

    # Rebase onto latest origin to avoid push rejection if main moved
    git fetch origin main --quiet
    if [[ "$(git rev-parse origin/main)" != "$(git rev-parse HEAD~1)" ]]; then
        echo "  Origin moved during release — rebasing..."
        git rebase origin/main
        echo "  ✓ Rebased onto latest origin/main"
    fi

    RELEASE_SHA=$(git rev-parse HEAD)
    echo "  Publishing release source commit to main..."
    git push origin HEAD:main
    echo "  ✓ Published release source commit ${RELEASE_SHA:0:8} to main"

    wait_for_ci_success "$RELEASE_SHA" "release source"

    git tag "v$NEW_VERSION"
    git push origin "v$NEW_VERSION"
    echo "  ✓ Tagged green release commit as v$NEW_VERSION and pushed"
fi
echo ""

# --------------------------------------------------------------------------
# Phase 6: Wait for tag workflow and upgrade Homebrew
# --------------------------------------------------------------------------

echo "==> Phase 6: Waiting for release workflow"

# Find the workflow run triggered by this exact tag push. Branch/tag names can
# repeat after rollback; the commit SHA is the release identity.
RELEASE_SHA=$(git rev-parse "v$NEW_VERSION^{}" 2>/dev/null || git rev-parse HEAD)
RUN_ID=""
for _ in {1..30}; do
    RUN_ID=$(gh run list \
        --repo "$BUTTONHEIST_GITHUB_REPO" \
        --workflow Release \
        --commit "$RELEASE_SHA" \
        --limit 1 \
        --json databaseId \
        --jq '.[0].databaseId // ""' 2>/dev/null || true)
    if [[ -n "$RUN_ID" ]]; then break; fi
    sleep 5
done

if [[ -z "${RUN_ID:-}" ]]; then
    echo "  Could not find release workflow run for v$NEW_VERSION."
    echo "  Check manually: https://github.com/$BUTTONHEIST_GITHUB_REPO/actions"
    echo "  This is a tag workflow discovery failure. Do not cut a new patch yet."
    echo "  Re-run this script after confirming whether the tag workflow started:"
    if [[ "$TAG_CURRENT" == true ]]; then
        echo "    ./scripts/release.sh --tag-current"
    else
        echo "    ./scripts/release.sh $NEW_VERSION"
    fi
    exit 1
else
    echo "  Watching run $RUN_ID..."
    if gh run watch "$RUN_ID" --repo "$BUTTONHEIST_GITHUB_REPO" --exit-status; then
        echo ""
        echo "  ✓ Release workflow passed"
        if command -v brew &>/dev/null && brew list royalpineapple/tap/buttonheist &>/dev/null; then
            echo "  Upgrading Homebrew..."
            brew update --quiet
            brew upgrade royalpineapple/tap/buttonheist
            HOMEBREW_BUTTONHEIST="$(brew --prefix royalpineapple/tap/buttonheist)/bin/buttonheist"
            HOMEBREW_VERSION="$("$HOMEBREW_BUTTONHEIST" --version)"
            if [[ "$HOMEBREW_VERSION" != "$NEW_VERSION" ]]; then
                echo "Error: Homebrew buttonheist reports '$HOMEBREW_VERSION', expected '$NEW_VERSION'"
                exit 1
            fi
            echo "  ✓ Homebrew upgraded to $HOMEBREW_VERSION"
        fi
    else
        echo ""
        echo "  ✗ Release workflow failed — deleting release tag"
        echo ""

        git push origin --delete "v$NEW_VERSION" 2>/dev/null || true
        git tag -d "v$NEW_VERSION" 2>/dev/null || true
        echo "  ✓ Deleted tag v$NEW_VERSION"

        # Delete the failed GitHub release if one was created
        gh release delete "v$NEW_VERSION" --repo "$BUTTONHEIST_GITHUB_REPO" --yes 2>/dev/null || true
        echo "  ✓ Cleaned up GitHub release"

        echo ""
        echo "  Release workflow failure rolled back at the tag boundary."
        echo "  The release source commit remains on main; fix forward and re-run the same version:"
        if [[ "$TAG_CURRENT" == true ]]; then
            echo "    ./scripts/release.sh --tag-current"
        else
            echo "    ./scripts/release.sh $NEW_VERSION"
        fi
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
