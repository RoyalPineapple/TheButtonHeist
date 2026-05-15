#!/usr/bin/env bash
# Render the checked-in Homebrew formula template with release checksums.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=scripts/release-contract.sh
source "$SCRIPT_DIR/release-contract.sh"

usage() {
    echo "Usage: $0 <version> <cli-sha256> <mcp-sha256> [output]"
}

if [[ $# -lt 3 || $# -gt 4 ]]; then
    usage
    exit 2
fi

VERSION="$1"
CLI_SHA="$2"
MCP_SHA="$3"
OUTPUT="${4:-}"
TEMPLATE="$REPO_ROOT/$BUTTONHEIST_FORMULA_TEMPLATE"
CLI_URL="$(buttonheist_release_url "$VERSION")/$(buttonheist_cli_archive_name "$VERSION")"
MCP_URL="$(buttonheist_release_url "$VERSION")/$(buttonheist_mcp_archive_name "$VERSION")"

RELEASE_VERSION_REGEX='^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$'
SHA256_REGEX='^[0-9a-f]{64}$'

if ! [[ "$VERSION" =~ $RELEASE_VERSION_REGEX ]]; then
    echo "Error: '$VERSION' is not a valid release version (e.g. 0.2.0 or 2026.05.15.1)"
    exit 1
fi
if ! [[ "$CLI_SHA" =~ $SHA256_REGEX ]]; then
    echo "Error: CLI checksum must be a lowercase SHA-256 hex digest"
    exit 1
fi
if ! [[ "$MCP_SHA" =~ $SHA256_REGEX ]]; then
    echo "Error: MCP checksum must be a lowercase SHA-256 hex digest"
    exit 1
fi
if [[ ! -f "$TEMPLATE" ]]; then
    echo "Error: formula template not found: $BUTTONHEIST_FORMULA_TEMPLATE"
    exit 1
fi

TMP_OUTPUT=$(mktemp)
trap 'rm -f "$TMP_OUTPUT"' EXIT

awk \
    -v version="$VERSION" \
    -v cli_sha="$CLI_SHA" \
    -v mcp_sha="$MCP_SHA" \
    -v cli_url="$CLI_URL" \
    -v mcp_url="$MCP_URL" '
    BEGIN {
        version_count = 0
        url_count = 0
        sha_count = 0
    }
    /^[[:space:]]*version "[^"]+"/ {
        sub(/version "[^"]+"/, "version \"" version "\"")
        version_count += 1
    }
    /^[[:space:]]*url "[^"]+"/ {
        url_count += 1
        if (url_count == 1) {
            sub(/url "[^"]+"/, "url \"" cli_url "\"")
        } else if (url_count == 2) {
            sub(/url "[^"]+"/, "url \"" mcp_url "\"")
        }
    }
    /^[[:space:]]*sha256 "[^"]+"/ {
        sha_count += 1
        if (sha_count == 1) {
            sub(/sha256 "[^"]+"/, "sha256 \"" cli_sha "\"")
        } else if (sha_count == 2) {
            sub(/sha256 "[^"]+"/, "sha256 \"" mcp_sha "\"")
        }
    }
    { print }
    END {
        if (version_count != 1) {
            print "Error: expected exactly one formula version line, found " version_count > "/dev/stderr"
            exit 1
        }
        if (url_count != 2) {
            print "Error: expected exactly two formula url lines, found " url_count > "/dev/stderr"
            exit 1
        }
        if (sha_count != 2) {
            print "Error: expected exactly two formula sha256 lines, found " sha_count > "/dev/stderr"
            exit 1
        }
    }
' "$TEMPLATE" > "$TMP_OUTPUT"

if [[ -n "$OUTPUT" ]]; then
    mv "$TMP_OUTPUT" "$OUTPUT"
else
    cat "$TMP_OUTPUT"
fi
