#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/bh-reference.XXXXXX")"
trap 'rm -rf "$TMPDIR"' EXIT

cat > "$TMPDIR/Package.swift" <<EOF
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

mkdir -p "$TMPDIR/Sources/BHReferenceDump"
cat > "$TMPDIR/Sources/BHReferenceDump/main.swift" <<'EOF'
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

mkdir -p "$ROOT/docs/reference"
swift run --package-path "$TMPDIR" BHReferenceDump commands > "$ROOT/docs/reference/commands.md"
swift run --package-path "$TMPDIR" BHReferenceDump mcp > "$ROOT/docs/reference/mcp-tools.md"
