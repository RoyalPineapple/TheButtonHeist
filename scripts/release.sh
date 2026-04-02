#!/usr/bin/env bash
# Release script for Button Heist.
#
# Performs the full release pipeline from a clean main branch:
#   1. Validate: must be on main, in sync with origin, clean worktree
#   2. Bump version across 6 files
#   3. Build all targets (TheScore, ButtonHeist, TheInsideJob, CLI, MCP)
#   4. Run all tests (TheScoreTests, ButtonHeistTests, TheInsideJobTests)
#   5. Commit, tag, push
#   6. Create GitHub release with CLI and MCP binaries
#   7. Update RoyalPineapple/homebrew-tap formula with real SHA-256 hashes
#
# Usage: ./scripts/release.sh [--dry-run] [<version>]
# Example: ./scripts/release.sh              # Uses today's date: 2026.04.03
#          ./scripts/release.sh 2026.04.03   # Explicit CalVer
#          ./scripts/release.sh --dry-run    # Preview only
#
# See docs/VERSIONING.md for versioning rules.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

CALVER_REGEX='^[0-9]{4}\.[0-9]{2}\.[0-9]{2}(\.[0-9]+)?$'
GITHUB_REPO="RoyalPineapple/TheButtonHeist"
HOMEBREW_TAP_REPO="RoyalPineapple/homebrew-tap"

DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=true
    shift
fi

# Default to today's date
if [[ $# -lt 1 ]]; then
    NEW_VERSION="$(date +%Y.%m.%d)"
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

# Must be on main
CURRENT_BRANCH=$(git branch --show-current)
if [[ "$CURRENT_BRANCH" != "main" ]]; then
    echo "Error: must be on main (currently on '$CURRENT_BRANCH')"
    echo "  git checkout main && git pull origin main"
    exit 1
fi

# Fetch latest and verify in sync
git fetch origin main --quiet
LOCAL_SHA=$(git rev-parse HEAD)
REMOTE_SHA=$(git rev-parse origin/main)
if [[ "$LOCAL_SHA" != "$REMOTE_SHA" ]]; then
    echo "Error: local main ($LOCAL_SHA) is not in sync with origin/main ($REMOTE_SHA)"
    echo "  git pull origin main"
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
    echo "Version is already $NEW_VERSION. Nothing to do."
    exit 0
fi

# Tag must not exist
if [[ -n $(git tag -l "v$NEW_VERSION" 2>/dev/null) ]]; then
    echo "Error: tag v$NEW_VERSION already exists."
    exit 1
fi

echo "  Branch: main (in sync with origin)"
echo "  Worktree: clean"
echo "  Version: $CURRENT_VERSION -> $NEW_VERSION"
echo ""

if [[ "$DRY_RUN" == true ]]; then
    echo "(dry run — stopping after validation)"
    echo ""
    echo "Would perform:"
    echo "  1. Bump version in 6 files"
    echo "  2. Build TheScore, ButtonHeist, TheInsideJob, CLI, MCP"
    echo "  3. Run TheScoreTests, ButtonHeistTests, TheInsideJobTests"
    echo "  4. Commit 'Release $NEW_VERSION', tag v$NEW_VERSION, push"
    echo "  5. Create GitHub release with binaries"
    echo "  6. Update homebrew-tap formula"
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

# 5. docs/VERSIONING.md
sed -i '' "s/\*\*$CURRENT_ESC\*\*/**$NEW_ESC**/" docs/VERSIONING.md
echo "  ✓ docs/VERSIONING.md"

# 6. Formula/buttonheist.rb (in-repo template — PLACEHOLDERs stay)
sed -i '' "s/version \"$CURRENT_ESC\"/version \"$NEW_ESC\"/" Formula/buttonheist.rb
echo "  ✓ Formula/buttonheist.rb"
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
tuist test TheScoreTests --no-selective-testing 2>&1 | tail -1
echo "  ✓ TheScoreTests"

echo "  Running ButtonHeistTests..."
tuist test ButtonHeistTests --no-selective-testing 2>&1 | tail -1
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
tuist test TheInsideJobTests --platform ios --device "$SIM_NAME" --no-selective-testing 2>&1 | tail -1
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
    docs/VERSIONING.md \
    Formula/buttonheist.rb

git commit -m "Release $NEW_VERSION"
git tag "v$NEW_VERSION"
git push origin main
git push origin "v$NEW_VERSION"

echo "  ✓ Committed, tagged v$NEW_VERSION, pushed"
echo ""

# --------------------------------------------------------------------------
# Phase 6: GitHub release with binaries
# --------------------------------------------------------------------------

echo "==> Phase 6: Creating GitHub release"

STAGING=$(mktemp -d)
trap "rm -rf $STAGING" EXIT

# Package CLI
mkdir -p "$STAGING/cli"
cp ButtonHeistCLI/.build/release/buttonheist "$STAGING/cli/"
(cd "$STAGING/cli" && tar czf "$STAGING/buttonheist-$NEW_VERSION-macos.tar.gz" buttonheist)

# Package MCP
mkdir -p "$STAGING/mcp"
cp ButtonHeistMCP/.build/release/buttonheist-mcp "$STAGING/mcp/"
(cd "$STAGING/mcp" && tar czf "$STAGING/buttonheist-mcp-$NEW_VERSION-macos.tar.gz" buttonheist-mcp)

CLI_SHA=$(shasum -a 256 "$STAGING/buttonheist-$NEW_VERSION-macos.tar.gz" | cut -d' ' -f1)
MCP_SHA=$(shasum -a 256 "$STAGING/buttonheist-mcp-$NEW_VERSION-macos.tar.gz" | cut -d' ' -f1)

gh release create "v$NEW_VERSION" \
    --repo "$GITHUB_REPO" \
    --title "Release $NEW_VERSION" \
    --notes "## Install

\`\`\`bash
brew install RoyalPineapple/tap/buttonheist
\`\`\`

## Binaries
- \`buttonheist\` CLI (macOS)
- \`buttonheist-mcp\` MCP server (macOS)" \
    "$STAGING/buttonheist-$NEW_VERSION-macos.tar.gz" \
    "$STAGING/buttonheist-mcp-$NEW_VERSION-macos.tar.gz"

echo "  ✓ GitHub release created"
echo "  CLI SHA-256:  $CLI_SHA"
echo "  MCP SHA-256:  $MCP_SHA"
echo ""

# --------------------------------------------------------------------------
# Phase 7: Update Homebrew tap
# --------------------------------------------------------------------------

echo "==> Phase 7: Updating Homebrew tap"

TAP_DIR=$(mktemp -d)
git clone --quiet "https://github.com/$HOMEBREW_TAP_REPO.git" "$TAP_DIR"

RELEASE_URL="https://github.com/$GITHUB_REPO/releases/download/v$NEW_VERSION"

mkdir -p "$TAP_DIR/Formula"
cat > "$TAP_DIR/Formula/buttonheist.rb" << FORMULA
class Buttonheist < Formula
  desc "Give AI agents full programmatic control of iOS apps"
  homepage "https://github.com/$GITHUB_REPO"
  version "$NEW_VERSION"

  url "$RELEASE_URL/buttonheist-$NEW_VERSION-macos.tar.gz"
  sha256 "$CLI_SHA"

  resource "mcp" do
    url "$RELEASE_URL/buttonheist-mcp-$NEW_VERSION-macos.tar.gz"
    sha256 "$MCP_SHA"
  end

  depends_on :macos
  depends_on macos: :sonoma

  def install
    bin.install "buttonheist"
    resource("mcp").stage { bin.install "buttonheist-mcp" }
  end

  def caveats
    <<~EOS
      MCP server is installed at:
        #{opt_bin}/buttonheist-mcp

      Add to your project's .mcp.json:
        {
          "mcpServers": {
            "buttonheist": {
              "command": "#{opt_bin}/buttonheist-mcp",
              "args": []
            }
          }
        }
    EOS
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/buttonheist --version")
  end
end
FORMULA

(cd "$TAP_DIR" && git add -A && git commit -m "Update buttonheist to $NEW_VERSION" && git push --quiet)
rm -rf "$TAP_DIR"

echo "  ✓ Homebrew tap updated"
echo ""

# --------------------------------------------------------------------------
# Done
# --------------------------------------------------------------------------

echo "========================================="
echo "  Release $NEW_VERSION complete"
echo "========================================="
echo ""
echo "  Tag:     v$NEW_VERSION"
echo "  Release: https://github.com/$GITHUB_REPO/releases/tag/v$NEW_VERSION"
echo "  Install: brew install RoyalPineapple/tap/buttonheist"
echo ""
