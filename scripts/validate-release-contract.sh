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

read_version_file() {
    tr -d '[:space:]' < "$BUTTONHEIST_RELEASE_VERSION_FILE"
}

extract_code_version() {
    grep -o 'buttonHeistVersion = "[^"]*"' "$BUTTONHEIST_CODE_VERSION_FILE" | cut -d'"' -f2
}

extract_formula_version() {
    grep -o 'version "[^"]*"' "$BUTTONHEIST_FORMULA_TEMPLATE" | cut -d'"' -f2
}

VERSION_FILE=$(read_version_file)
CODE_VERSION=$(extract_code_version)
FORMULA_VERSION=$(extract_formula_version)

[[ -n "$VERSION_FILE" ]] || fail "$BUTTONHEIST_RELEASE_VERSION_FILE is empty"
[[ "$VERSION_FILE" == "$CODE_VERSION" ]] || fail "$BUTTONHEIST_RELEASE_VERSION_FILE ($VERSION_FILE) != $BUTTONHEIST_CODE_VERSION_FILE ($CODE_VERSION)"
[[ "$VERSION_FILE" == "$FORMULA_VERSION" ]] || fail "$BUTTONHEIST_RELEASE_VERSION_FILE ($VERSION_FILE) != $BUTTONHEIST_FORMULA_TEMPLATE ($FORMULA_VERSION)"

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
