#!/usr/bin/env bash
# Validate release/install contract drift without publishing a release.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/release-contract.sh
source "$SCRIPT_DIR/release-contract.sh"

fail() {
    echo "Error: $*"
    exit 1
}

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'
SEMVER_GREP='[0-9]+\.[0-9]+\.[0-9]+'

single_value() {
    local label="$1"
    local value="$2"
    local count

    count=$(printf '%s\n' "$value" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    [[ "$count" == "1" ]] || fail "$label must contain exactly one release version, found $count"
    printf '%s' "$value"
}

read_version_file() {
    sed -E 's/[[:space:]]//g' "$BUTTONHEIST_RELEASE_VERSION_FILE" | sed '/^$/d'
}

extract_code_version() {
    grep -E '^[[:space:]]*public let buttonHeistVersion = "[^"]+"' "$BUTTONHEIST_CODE_VERSION_FILE" \
        | sed -E 's/.*"([^"]+)".*/\1/'
}

extract_formula_version() {
    grep -E '^[[:space:]]*version "[^"]+"' "$BUTTONHEIST_FORMULA_TEMPLATE" \
        | sed -E 's/.*"([^"]+)".*/\1/'
}

VERSION_FILE=$(single_value "$BUTTONHEIST_RELEASE_VERSION_FILE" "$(read_version_file || true)")
CODE_VERSION=$(single_value "$BUTTONHEIST_CODE_VERSION_FILE buttonHeistVersion" "$(extract_code_version || true)")
FORMULA_VERSION=$(single_value "$BUTTONHEIST_FORMULA_TEMPLATE version" "$(extract_formula_version || true)")

[[ -n "$VERSION_FILE" ]] || fail "$BUTTONHEIST_RELEASE_VERSION_FILE is empty"
[[ "$VERSION_FILE" =~ $SEMVER_REGEX ]] || fail "$BUTTONHEIST_RELEASE_VERSION_FILE ($VERSION_FILE) is not MAJOR.MINOR.PATCH"
[[ "$CODE_VERSION" =~ $SEMVER_REGEX ]] || fail "$BUTTONHEIST_CODE_VERSION_FILE ($CODE_VERSION) is not MAJOR.MINOR.PATCH"
[[ "$FORMULA_VERSION" =~ $SEMVER_REGEX ]] || fail "$BUTTONHEIST_FORMULA_TEMPLATE ($FORMULA_VERSION) is not MAJOR.MINOR.PATCH"
[[ "$VERSION_FILE" == "$CODE_VERSION" ]] || fail "$BUTTONHEIST_RELEASE_VERSION_FILE ($VERSION_FILE) != $BUTTONHEIST_CODE_VERSION_FILE ($CODE_VERSION)"
[[ "$VERSION_FILE" == "$FORMULA_VERSION" ]] || fail "$BUTTONHEIST_RELEASE_VERSION_FILE ($VERSION_FILE) != $BUTTONHEIST_FORMULA_TEMPLATE ($FORMULA_VERSION)"

if grep -Fq "$VERSION_FILE" "$BUTTONHEIST_API_DOCS_FILE"; then
    fail "$BUTTONHEIST_API_DOCS_FILE must not duplicate release version $VERSION_FILE"
fi
if grep -Eq "$SEMVER_GREP" "$BUTTONHEIST_API_DOCS_FILE"; then
    fail "$BUTTONHEIST_API_DOCS_FILE must use placeholders instead of concrete release versions"
fi

if awk '
    /^## CLI Reference$/ { in_cli = 1; next }
    in_cli && /^## / { in_cli = 0 }
    in_cli && /^\*\*Version\*\*:[[:space:]]*[0-9]+\.[0-9]+\.[0-9]+[[:space:]]*$/ { found = 1 }
    END { exit found ? 0 : 1 }
' "$BUTTONHEIST_API_DOCS_FILE"; then
    fail "$BUTTONHEIST_API_DOCS_FILE must not duplicate the CLI release version"
fi

if grep -Fq "$VERSION_FILE" "$BUTTONHEIST_DEMO_VERSION_FILE"; then
    fail "$BUTTONHEIST_DEMO_VERSION_FILE must not duplicate release version $VERSION_FILE"
fi

if grep -Eq "\"$SEMVER_GREP\"" "$BUTTONHEIST_DEMO_VERSION_FILE"; then
    fail "$BUTTONHEIST_DEMO_VERSION_FILE must use buttonHeistVersion instead of a hardcoded release version"
fi

DOC_EXAMPLE_PATHS=(README.md docs examples)
if grep -R -n -E '\} Else \{' "${DOC_EXAMPLE_PATHS[@]}" >/tmp/buttonheist-stale-dsl-grep.txt; then
    cat /tmp/buttonheist-stale-dsl-grep.txt
    fail "docs/examples must use canonical .else { ... } syntax, not } Else {"
fi
if grep -R -n -E 'WaitFor\(timeout:' "${DOC_EXAMPLE_PATHS[@]}" >/tmp/buttonheist-stale-dsl-grep.txt; then
    cat /tmp/buttonheist-stale-dsl-grep.txt
    fail "docs/examples must use WaitFor(predicate, timeout: .seconds(...)), not WaitFor(timeout:)"
fi
if grep -R -n -E 'timeout:[[:space:]]*[0-9]+' "${DOC_EXAMPLE_PATHS[@]}" >/tmp/buttonheist-stale-dsl-grep.txt; then
    cat /tmp/buttonheist-stale-dsl-grep.txt
    fail "docs/examples must use timeout: .seconds(...), not bare numeric timeouts"
fi

if grep -Eq 'LabeledContent\([[:space:]]*"Version"' "$BUTTONHEIST_DEMO_VERSION_FILE"; then
    grep -Eq 'LabeledContent\([[:space:]]*"Version"[[:space:]]*,[[:space:]]*value:[[:space:]]*(TheScore\.)?buttonHeistVersion[[:space:]]*\)' "$BUTTONHEIST_DEMO_VERSION_FILE" \
        || fail "$BUTTONHEIST_DEMO_VERSION_FILE must source Version from TheScore.buttonHeistVersion or remove the Version row"
fi

RAW_HEIST_FILES=$(git ls-files '*.heist' || true)
if [[ -n "$RAW_HEIST_FILES" ]]; then
    fail "tracked .heist paths must be generated package directories, not raw files: $RAW_HEIST_FILES"
fi

HEIST_PACKAGE_DIRS=$(git ls-files | sed -n 's#^\(.*\.heist\)/.*#\1#p' | sort -u)
while IFS= read -r package; do
    [[ -z "$package" ]] && continue
    [[ -d "$package" ]] || fail "$package must be a .heist package directory"
    [[ -f "$package/manifest.json" ]] || fail "$package is missing manifest.json"
    [[ -f "$package/plan.json" ]] || fail "$package is missing plan.json"
done <<< "$HEIST_PACKAGE_DIRS"

EXPECTED_HOMEPAGE="homepage \"https://github.com/$BUTTONHEIST_GITHUB_REPO\""
grep -Fq "$EXPECTED_HOMEPAGE" "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE homepage does not match $BUTTONHEIST_GITHUB_REPO"

CLI_TEMPLATE_PATH="$(buttonheist_cli_archive_name '#{version}')"
MCP_TEMPLATE_PATH="$(buttonheist_mcp_archive_name '#{version}')"
EXPECTED_RELEASE_URL="https://github.com/$BUTTONHEIST_GITHUB_REPO/releases/download/v#{version}"

grep -Fq "$EXPECTED_RELEASE_URL/$CLI_TEMPLATE_PATH" "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE CLI URL does not match release contract"
grep -Fq "$EXPECTED_RELEASE_URL/$MCP_TEMPLATE_PATH" "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE MCP URL does not match release contract"
grep -Fq 'bin.install "heist-plan"' "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE must install the heist-plan compiler"
grep -Fq 'lib.install "ThePlans"' "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE must install ThePlans compiler artifacts under lib"
grep -Fq 'depends_on arch: :arm64' "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE must declare Button Heist Homebrew artifacts as arm64-only"
grep -Fq 'ThePlans/arm64-apple-macosx/release/Modules/ThePlans.swiftinterface' "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE test must assert installed arm64 ThePlans artifacts"
grep -Fq 'refute_predicate lib/"ThePlans/arm64-apple-macosx/release/Modules/ThePlans.swiftmodule"' "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE test must reject installed binary ThePlans.swiftmodule"
grep -Fq 'ThePlans/arm64-apple-macosx/release/description.json' "$BUTTONHEIST_FORMULA_TEMPLATE" \
    || fail "$BUTTONHEIST_FORMULA_TEMPLATE test must assert installed ThePlans description.json"

"$SCRIPT_DIR/check-parser-contract.sh"

TMP_FORMULA=$(mktemp)
trap 'rm -f "$TMP_FORMULA"' EXIT

DUMMY_CLI_SHA="1111111111111111111111111111111111111111111111111111111111111111"
DUMMY_MCP_SHA="2222222222222222222222222222222222222222222222222222222222222222"

"$SCRIPT_DIR/render-homebrew-formula.sh" "$VERSION_FILE" "$DUMMY_CLI_SHA" "$DUMMY_MCP_SHA" "$TMP_FORMULA"

grep -Fq "version \"$VERSION_FILE\"" "$TMP_FORMULA" \
    || fail "rendered formula version does not match $VERSION_FILE"
grep -Fq "url \"$(buttonheist_release_url "$VERSION_FILE")/$(buttonheist_cli_archive_name "$VERSION_FILE")\"" "$TMP_FORMULA" \
    || fail "rendered formula is missing concrete CLI URL"
grep -Fq "url \"$(buttonheist_release_url "$VERSION_FILE")/$(buttonheist_mcp_archive_name "$VERSION_FILE")\"" "$TMP_FORMULA" \
    || fail "rendered formula is missing concrete MCP URL"
grep -Fq "sha256 \"$DUMMY_CLI_SHA\"" "$TMP_FORMULA" \
    || fail "rendered formula is missing CLI checksum"
grep -Fq "sha256 \"$DUMMY_MCP_SHA\"" "$TMP_FORMULA" \
    || fail "rendered formula is missing MCP checksum"
if grep -Fq 'PLACEHOLDER' "$TMP_FORMULA"; then
    fail "rendered formula still contains checksum placeholder"
fi

echo "Release contract verified for $VERSION_FILE"
