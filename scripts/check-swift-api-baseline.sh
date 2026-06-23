#!/usr/bin/env bash
# Check compiler-exported Swift public API snapshots.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BASELINE_DIR="${BUTTONHEIST_SWIFT_API_BASELINE_DIR:-$REPO_ROOT/api-baselines/swift}"

MODULES=(
    "ThePlans:"
    "TheScore:"
    "ButtonHeistDSL:ThePlans"
    "ButtonHeist:ThePlans,TheScore"
)

UPDATE=0

usage() {
    cat <<'EOF'
Usage: scripts/check-swift-api-baseline.sh [--update]

Checks checked-in public Swift API snapshots for ThePlans, TheScore,
ButtonHeistDSL, and ButtonHeist.

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

SWIFT_SYMBOLGRAPH_EXTRACT="$(xcrun --find swift-symbolgraph-extract)"
SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
TARGET_TRIPLE="$(swiftc -print-target-info | python3 -c 'import json, sys; print(json.load(sys.stdin)["target"]["triple"])')"
SWIFT_TOOLCHAIN_ID="$(swiftc --version 2>&1 | shasum -a 256 | awk '{print substr($1, 1, 12)}')"
SCRATCH_PATH="${BUTTONHEIST_SWIFT_API_SCRATCH_PATH:-$REPO_ROOT/.build/swift-api-baseline/$SWIFT_TOOLCHAIN_ID}"
RAW_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-swift-api-raw.XXXXXX")"
GENERATED_DIR="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-swift-api-generated.XXXXXX")"

cleanup() {
    rm -rf "$RAW_DIR" "$GENERATED_DIR"
}
trap cleanup EXIT

echo "Building public Swift API targets"
mkdir -p "$SCRATCH_PATH"
for entry in "${MODULES[@]}"; do
    target="${entry%%:*}"
    swift build --scratch-path "$SCRATCH_PATH" --target "$target"
done

BIN_PATH="$(swift build --scratch-path "$SCRATCH_PATH" --show-bin-path)"
MODULE_SEARCH_PATH="$BIN_PATH/Modules"
MODULE_CACHE_PATH="$BIN_PATH/ModuleCache"
mkdir -p "$MODULE_CACHE_PATH"

normalize_module() {
    local module="$1"
    local raw_module_dir="$2"
    local output_file="$3"

    python3 - "$module" "$raw_module_dir" "$output_file" <<'PY'
import json
import pathlib
import sys

module = sys.argv[1]
raw_dir = pathlib.Path(sys.argv[2])
output = pathlib.Path(sys.argv[3])

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
    local raw_module_dir="$RAW_DIR/$module"
    mkdir -p "$raw_module_dir"

    local args=(
        "$SWIFT_SYMBOLGRAPH_EXTRACT"
        -module-name "$module"
        -target "$TARGET_TRIPLE"
        -sdk "$SDK_PATH"
        -I "$MODULE_SEARCH_PATH"
        -module-cache-path "$MODULE_CACHE_PATH"
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
    normalize_module "$module" "$raw_module_dir" "$GENERATED_DIR/$module.symbols.txt"
}

for entry in "${MODULES[@]}"; do
    module="${entry%%:*}"
    reexports="${entry#*:}"
    extract_module "$module" "$reexports"
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
