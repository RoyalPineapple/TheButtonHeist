#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CHECK_MODE=0

usage() {
    echo "usage: scripts/render-command-reference.sh [--check]"
}

case "${1:-}" in
    "")
        ;;
    --check)
        CHECK_MODE=1
        shift
        ;;
    -h|--help)
        usage
        exit 0
        ;;
    *)
        usage >&2
        exit 64
        ;;
esac

if [[ $# -ne 0 ]]; then
    usage >&2
    exit 64
fi

WORKDIR="$(mktemp -d "${TMPDIR:-/tmp}/bh-reference.XXXXXX")"
trap 'rm -rf "$WORKDIR"' EXIT

COMMANDS_DOC="$ROOT/docs/reference/commands.md"
MCP_DOC="$ROOT/docs/reference/mcp-tools.md"

cat > "$WORKDIR/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BHReferenceDump",
    platforms: [.macOS(.v14)],
    dependencies: [.package(path: "$ROOT/ButtonHeist")],
    targets: [
        .executableTarget(
            name: "BHReferenceDump",
            dependencies: [.product(name: "ButtonHeist", package: "ButtonHeist")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
EOF

mkdir -p "$WORKDIR/Sources/BHReferenceDump"
cat > "$WORKDIR/Sources/BHReferenceDump/main.swift" <<'EOF'
import ButtonHeist
import Foundation

switch CommandLine.arguments.dropFirst().first {
case "commands":
    print(FenceCommandReference.commandMarkdown(), terminator: "")
case "mcp":
    print(FenceCommandReference.mcpMarkdown(), terminator: "")
default:
    FileHandle.standardError.write(Data("usage: BHReferenceDump commands|mcp\n".utf8))
    Foundation.exit(64)
}
EOF

check_generated_doc() {
    local committed="$1"
    local generated="$2"
    local relative="${committed#"$ROOT"/}"

    if [[ ! -f "$committed" ]]; then
        echo "Missing generated reference doc: $relative" >&2
        return 1
    fi

    if ! cmp -s "$committed" "$generated"; then
        echo "Generated reference doc is out of date: $relative" >&2
        echo "Diff (committed -> generated):" >&2
        diff -u --label "$relative" --label "$relative (generated)" "$committed" "$generated" >&2 || true
        return 1
    fi
}

if [[ "$CHECK_MODE" -eq 1 ]]; then
    GENERATED_COMMANDS="$WORKDIR/commands.md"
    GENERATED_MCP="$WORKDIR/mcp-tools.md"

    swift run --package-path "$WORKDIR" BHReferenceDump commands > "$GENERATED_COMMANDS"
    swift run --package-path "$WORKDIR" BHReferenceDump mcp > "$GENERATED_MCP"

    failed=0
    check_generated_doc "$COMMANDS_DOC" "$GENERATED_COMMANDS" || failed=1
    check_generated_doc "$MCP_DOC" "$GENERATED_MCP" || failed=1

    if [[ "$failed" -ne 0 ]]; then
        echo "Error: generated reference docs are out of date. Run scripts/render-command-reference.sh and commit the changes." >&2
        exit 1
    fi

    echo "Generated reference docs are up to date."
else
    mkdir -p "$ROOT/docs/reference"
    swift run --package-path "$WORKDIR" BHReferenceDump commands > "$COMMANDS_DOC"
    swift run --package-path "$WORKDIR" BHReferenceDump mcp > "$MCP_DOC"
fi
