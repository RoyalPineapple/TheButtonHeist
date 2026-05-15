#!/usr/bin/env bash
# Shared release/install contract for release scripts and CI workflows.

# shellcheck disable=SC2034
BUTTONHEIST_GITHUB_REPO="RoyalPineapple/TheButtonHeist"
BUTTONHEIST_TAP_REPO="RoyalPineapple/homebrew-tap"

BUTTONHEIST_RELEASE_VERSION_FILE="RELEASE_VERSION"
BUTTONHEIST_CODE_VERSION_FILE="ButtonHeist/Sources/TheScore/Messages.swift"
BUTTONHEIST_FORMULA_TEMPLATE="Formula/buttonheist.rb"

BUTTONHEIST_CLI_ARTIFACT_PREFIX="buttonheist"
BUTTONHEIST_MCP_ARTIFACT_PREFIX="buttonheist-mcp"
BUTTONHEIST_MACOS_ARTIFACT_SUFFIX="macos"
BUTTONHEIST_DEMO_ARTIFACT_PREFIX="bh-demo"
BUTTONHEIST_DEMO_ARTIFACT_SUFFIX="iphonesimulator"

buttonheist_release_url() {
    local version="$1"
    printf 'https://github.com/%s/releases/download/v%s' "$BUTTONHEIST_GITHUB_REPO" "$version"
}

buttonheist_cli_archive_name() {
    local version="$1"
    printf '%s-%s-%s.tar.gz' \
        "$BUTTONHEIST_CLI_ARTIFACT_PREFIX" \
        "$version" \
        "$BUTTONHEIST_MACOS_ARTIFACT_SUFFIX"
}

buttonheist_mcp_archive_name() {
    local version="$1"
    printf '%s-%s-%s.tar.gz' \
        "$BUTTONHEIST_MCP_ARTIFACT_PREFIX" \
        "$version" \
        "$BUTTONHEIST_MACOS_ARTIFACT_SUFFIX"
}

buttonheist_demo_archive_name() {
    local version="$1"
    printf '%s-%s-%s.zip' \
        "$BUTTONHEIST_DEMO_ARTIFACT_PREFIX" \
        "$version" \
        "$BUTTONHEIST_DEMO_ARTIFACT_SUFFIX"
}
