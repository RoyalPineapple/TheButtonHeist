#!/usr/bin/env bash
# Check compiler-exported Swift public API snapshots.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_DIR="${BUTTONHEIST_SWIFT_API_BASELINE_DIR:-$REPO_ROOT/api-baselines/swift}"
EXPECTED_SWIFT_VERSION="${BUTTONHEIST_SWIFT_API_EXPECTED_SWIFT_VERSION:-Apple Swift version 6.2.4}"
ALLOW_TOOLCHAIN_MISMATCH="${BUTTONHEIST_SWIFT_API_ALLOW_TOOLCHAIN_MISMATCH:-0}"
IOS_SIMULATOR_TRIPLE="${BUTTONHEIST_SWIFT_API_IOS_SIMULATOR_TRIPLE:-arm64-apple-ios17.0-simulator}"

MACOS_MODULES=(
    "ThePlans:"
    "TheScore:"
    "ButtonHeistDSL:ThePlans"
    "ButtonHeist:ThePlans,TheScore"
)
IOS_DEBUG_MODULES=(
    "TheInsideJob:"
)

UPDATE=0

usage() {
    cat <<'EOF'
Usage: scripts/check-swift-api-baseline.sh [--update]

Checks checked-in public Swift API snapshots for ThePlans, TheScore,
ButtonHeistDSL, ButtonHeist, and the iOS DEBUG TheInsideJob module.

Options:
  --update    Regenerate snapshots after an intentional public API change.
EOF
}

while (($#)); do
    case "$1" in
        --update)
            UPDATE=1
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown argument: $1" >&2
            usage >&2
            exit 64
            ;;
    esac
    shift
done

cd "$REPO_ROOT"

SWIFT_BIN="$(xcrun --find swift)"
SWIFTC_BIN="$(xcrun --find swiftc)"
SWIFT_SYMBOLGRAPH_EXTRACT="$(xcrun --find swift-symbolgraph-extract)"
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
MACOS_TARGET_TRIPLE="$("$SWIFTC_BIN" -print-target-info | python3 -c 'import json, sys; print(json.load(sys.stdin)["target"]["triple"])')"
IOS_SIMULATOR_SDK_PATH="$(xcrun --sdk iphonesimulator --show-sdk-path)"
SWIFT_VERSION_OUTPUT="$("$SWIFTC_BIN" --version 2>&1)"
SWIFT_VERSION_LINE="$(printf '%s\n' "$SWIFT_VERSION_OUTPUT" | grep -m1 'Apple Swift version' || true)"
SWIFT_TOOLCHAIN_ID="$(printf '%s' "$SWIFT_VERSION_OUTPUT" | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
SCRATCH_ROOT="${BUTTONHEIST_SWIFT_API_SCRATCH_PATH:-$REPO_ROOT/.build/swift-api-baseline/$SWIFT_TOOLCHAIN_ID}"
RAW_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-swift-api-raw.XXXXXX")"
GENERATED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-swift-api-generated.XXXXXX")"

cleanup() {
    rm -rf "$RAW_DIR" "$GENERATED_DIR"
}
trap cleanup EXIT

if [[ "$SWIFT_VERSION_LINE" != *"$EXPECTED_SWIFT_VERSION"* ]]; then
    severity="Error"
    if [[ "$ALLOW_TOOLCHAIN_MISMATCH" == "1" ]]; then
        severity="Warning"
    fi
    cat >&2 <<EOF
$severity: Swift API baselines must be generated and checked with $EXPECTED_SWIFT_VERSION.

Active toolchain:
$SWIFT_VERSION_OUTPUT

CI selects Xcode 26.3 before running this script. Locally, set DEVELOPER_DIR
to an Xcode 26.3 developer directory before running check or update, for example:

  DEVELOPER_DIR=/Applications/Xcode-26.3.0.app/Contents/Developer scripts/check-swift-api-baseline.sh

Set BUTTONHEIST_SWIFT_API_ALLOW_TOOLCHAIN_MISMATCH=1 only while intentionally
updating this contract for a new pinned Xcode/Swift toolchain.
EOF
    if [[ "$ALLOW_TOOLCHAIN_MISMATCH" != "1" ]]; then
        exit 1
    fi
fi

echo "Swift API baseline toolchain: $SWIFT_VERSION_LINE"

macos_swift_build() {
    "$SWIFT_BIN" build --scratch-path "$SCRATCH_ROOT/macos" "$@"
}

ios_debug_swift_build() {
    "$SWIFT_BIN" build \
        --scratch-path "$SCRATCH_ROOT/ios-simulator-debug" \
        --triple "$IOS_SIMULATOR_TRIPLE" \
        --sdk "$IOS_SIMULATOR_SDK_PATH" \
        -Xswiftc -DDEBUG \
        "$@"
}

echo "Building macOS public Swift API targets"
mkdir -p "$SCRATCH_ROOT/macos"
for entry in "${MACOS_MODULES[@]}"; do
    target="${entry%%:*}"
    macos_swift_build --target "$target"
done

echo "Building iOS DEBUG public Swift API targets"
mkdir -p "$SCRATCH_ROOT/ios-simulator-debug"
for entry in "${IOS_DEBUG_MODULES[@]}"; do
    target="${entry%%:*}"
    ios_debug_swift_build --target "$target"
done

MACOS_BIN_PATH="$(macos_swift_build --show-bin-path)"
MACOS_MODULE_SEARCH_PATH="$MACOS_BIN_PATH/Modules"
MACOS_MODULE_CACHE_PATH="$MACOS_BIN_PATH/ModuleCache"
mkdir -p "$MACOS_MODULE_CACHE_PATH"

IOS_BIN_PATH="$(ios_debug_swift_build --show-bin-path)"
IOS_MODULE_SEARCH_PATH="$IOS_BIN_PATH/Modules"
IOS_MODULE_CACHE_PATH="$IOS_BIN_PATH/ModuleCache"
mkdir -p "$IOS_MODULE_CACHE_PATH"

normalize_module() {
    local module="$1"
    local raw_module_dir="$2"
    local output_file="$3"
    local platform="$4"

    python3 - "$module" "$raw_module_dir" "$output_file" "$platform" <<'PY'
import json
import pathlib
import sys

module = sys.argv[1]
raw_dir = pathlib.Path(sys.argv[2])
output = pathlib.Path(sys.argv[3])
platform = sys.argv[4]

relationship_kinds = {
    "conformsTo",
    "defaultImplementationOf",
    "requirementOf",
}
toolchain_marker_protocols = {
    "Swift.Copyable",
    "Swift.Escapable",
    "Swift.SendableMetatype",
}


def escape(value):
    return str(value).replace("\\", "\\\\").replace("\t", "\\t").replace("\r", "\\r").replace("\n", "\\n")


def fragment_text(symbol):
    fragments = symbol.get("declarationFragments") or symbol.get("names", {}).get("subHeading") or []
    text = "".join(fragment.get("spelling", "") for fragment in fragments).strip()
    # Swift 6.3.2 emits inferred @Sendable on some actor-isolated closure
    # declarations that Swift 6.2.4 omits, with identical symbol identities.
    # Keep the snapshot focused on source-visible public contract drift.
    return text.replace(" @Sendable", "")


def symbol_title(symbol):
    return symbol.get("names", {}).get("title") or ".".join(symbol.get("pathComponents", []))


def target_title(precise, fallback, titles_by_precise):
    return titles_by_precise.get(precise) or fallback or precise


graphs = []
for path in sorted(raw_dir.glob(f"{module}*.symbols.json")):
    with path.open(encoding="utf-8") as handle:
        graph = json.load(handle)
    graphs.append((path.name, graph))

if not graphs:
    raise SystemExit(f"no symbol graph files found for {module} in {raw_dir}")

titles_by_precise = {}
for _, graph in graphs:
    for symbol in graph.get("symbols", []):
        titles_by_precise[symbol["identifier"]["precise"]] = symbol_title(symbol)

symbol_lines = set()
relationship_lines = set()

for graph_name, graph in graphs:
    for symbol in graph.get("symbols", []):
        precise = symbol["identifier"]["precise"]
        kind = symbol["kind"]["identifier"]
        access = symbol.get("accessLevel", "")
        title = symbol_title(symbol)
        path = ".".join(symbol.get("pathComponents", [])) or title
        declaration = fragment_text(symbol)
        symbol_lines.add("\t".join([
            "symbol",
            escape(graph_name),
            escape(precise),
            escape(kind),
            escape(access),
            escape(title),
            escape(path),
            escape(declaration),
        ]))

    for relationship in graph.get("relationships", []):
        kind = relationship.get("kind")
        if kind not in relationship_kinds:
            continue

        target = relationship.get("target", "")
        fallback = relationship.get("targetFallback", "")
        target_display = target_title(target, fallback, titles_by_precise)
        if target_display in toolchain_marker_protocols:
            continue

        source = relationship.get("source", "")
        relationship_lines.add("\t".join([
            "relationship",
            escape(kind),
            escape(source),
            escape(target),
            escape(target_title(source, "", titles_by_precise)),
            escape(target_display),
        ]))

lines = [
    "# Button Heist Swift Public API Snapshot",
    f"# Module: {module}",
    f"# Platform: {platform}",
    "# Generated by scripts/check-swift-api-baseline.sh --update",
    "# Source: swift-symbolgraph-extract --minimum-access-level public",
    "",
    "# Format: symbol<TAB>graph<TAB>precise-id<TAB>kind<TAB>access<TAB>title<TAB>path<TAB>declaration",
    "# Format: relationship<TAB>kind<TAB>source-id<TAB>target-id<TAB>source<TAB>target",
    "",
]
lines.extend(sorted(symbol_lines))
if relationship_lines:
    lines.append("")
    lines.extend(sorted(relationship_lines))
lines.append("")

output.write_text("\n".join(lines), encoding="utf-8")
PY
}

extract_module() {
    local module="$1"
    local reexports="$2"
    local target_triple="$3"
    local sdk_path="$4"
    local module_search_path="$5"
    local module_cache_path="$6"
    local platform="$7"
    local raw_module_dir="$RAW_DIR/$module"
    mkdir -p "$raw_module_dir"

    local args=(
        "$SWIFT_SYMBOLGRAPH_EXTRACT"
        -module-name "$module"
        -target "$target_triple"
        -sdk "$sdk_path"
        -I "$module_search_path"
        -module-cache-path "$module_cache_path"
        -minimum-access-level public
        -skip-synthesized-members
        -skip-inherited-docs
        -omit-extension-block-symbols
        -output-dir "$raw_module_dir"
    )
    if [[ -n "$reexports" ]]; then
        args+=("-experimental-allowed-reexported-modules=$reexports")
    fi

    echo "Extracting public API for $module"
    "${args[@]}"
    normalize_module "$module" "$raw_module_dir" "$GENERATED_DIR/$module.symbols.txt" "$platform"
}

for entry in "${MACOS_MODULES[@]}"; do
    module="${entry%%:*}"
    reexports="${entry#*:}"
    extract_module "$module" "$reexports" "$MACOS_TARGET_TRIPLE" "$MACOS_SDK_PATH" "$MACOS_MODULE_SEARCH_PATH" "$MACOS_MODULE_CACHE_PATH" "macOS"
done

for entry in "${IOS_DEBUG_MODULES[@]}"; do
    module="${entry%%:*}"
    reexports="${entry#*:}"
    extract_module "$module" "$reexports" "$IOS_SIMULATOR_TRIPLE" "$IOS_SIMULATOR_SDK_PATH" "$IOS_MODULE_SEARCH_PATH" "$IOS_MODULE_CACHE_PATH" "iOS Simulator DEBUG"
done

if [[ "$UPDATE" == "1" ]]; then
    mkdir -p "$BASELINE_DIR"
    for generated in "$GENERATED_DIR"/*.symbols.txt; do
        cp "$generated" "$BASELINE_DIR/$(basename "$generated")"
    done
    echo "Updated Swift API baselines in $BASELINE_DIR"
    exit 0
fi

status=0
for generated in "$GENERATED_DIR"/*.symbols.txt; do
    baseline="$BASELINE_DIR/$(basename "$generated")"
    if [[ ! -f "$baseline" ]]; then
        echo "Error: missing Swift API baseline: $baseline" >&2
        status=1
        continue
    fi

    if ! diff -u "$baseline" "$generated"; then
        status=1
    fi
done

if [[ "$status" != "0" ]]; then
    cat >&2 <<EOF

Swift public API baseline drift detected.
If this is an intentional public API change, run:

  scripts/check-swift-api-baseline.sh --update

Then review and commit the updated files under $BASELINE_DIR.
EOF
    exit "$status"
fi

echo "Swift public API baselines are current."
