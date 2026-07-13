#!/usr/bin/env bash
# Compile an external SwiftPM consumer that imports ButtonHeist only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/buttonheist-external-import-contract"
DSL_FIXTURE_DIR="$REPO_ROOT/tests/fixtures/buttonheist-dsl-import-contract"
PUBLIC_PRODUCTS_FIXTURE_DIR="$REPO_ROOT/tests/fixtures/buttonheist-public-products-import-contract"
IOS_PUBLIC_PRODUCTS_FIXTURE_DIR="$REPO_ROOT/tests/fixtures/buttonheist-ios-public-products-import-contract"
IOS_SIMULATOR_TRIPLE="${BUTTONHEIST_SWIFT_API_IOS_SIMULATOR_TRIPLE:-arm64-apple-ios17.0-simulator}"

fail() {
    echo "Error: $*" >&2
    exit 1
}

[[ -f "$FIXTURE_DIR/Package.swift" ]] || fail "missing external import fixture Package.swift"
[[ -f "$DSL_FIXTURE_DIR/Package.swift" ]] || fail "missing DSL import fixture Package.swift"
[[ -f "$PUBLIC_PRODUCTS_FIXTURE_DIR/Package.swift" ]] || fail "missing public products import fixture Package.swift"
[[ -f "$IOS_PUBLIC_PRODUCTS_FIXTURE_DIR/Package.swift" ]] || fail "missing iOS public products import fixture Package.swift"

"$SCRIPT_DIR/check-source-shape.sh"

normalize_exported_imports() {
    sed -E \
        -e "s#^$REPO_ROOT/##" \
        -e 's#:[0-9]+:[[:space:]]*@_exported[[:space:]]+import[[:space:]]+#:#'
}

EXPORTED_IMPORTS="$(grep -R -nE '^[[:space:]]*@_exported[[:space:]]+import[[:space:]]+' "$REPO_ROOT/ButtonHeist/Sources" | normalize_exported_imports || true)"
EXPECTED_EXPORTED_IMPORTS="$(cat <<EOF
ButtonHeist/Sources/ButtonHeistTesting/ButtonHeistTesting.swift:ButtonHeistDSL
ButtonHeist/Sources/TheButtonHeist/Exports.swift:ThePlans
ButtonHeist/Sources/TheButtonHeist/Exports.swift:TheScore
ButtonHeist/Sources/TheInsideJob/Heist.swift:TheScore
EOF
)"
if [[ "$(printf '%s\n' "$EXPORTED_IMPORTS" | sort)" != "$(printf '%s\n' "$EXPECTED_EXPORTED_IMPORTS" | sort)" ]]; then
    printf 'Observed @_exported imports:\n%s\n' "$EXPORTED_IMPORTS" >&2
    fail "@_exported imports must match the package-contract allowlist"
fi

IMPORTS="$(grep -R -nE '^[[:space:]]*import[[:space:]]+' "$FIXTURE_DIR/Sources" || true)"
[[ -n "$IMPORTS" ]] || fail "external import fixture must import ButtonHeist"
if printf '%s\n' "$IMPORTS" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*import[[:space:]]+ButtonHeist([[:space:]]|$)'
then
    fail "external import fixture must import ButtonHeist only"
fi

if grep -nE 'product:[[:space:]]*"ThePlans"|name:[[:space:]]*"ThePlans"' "$FIXTURE_DIR/Package.swift"; then
    fail "external import fixture must depend on the ButtonHeist product only, not ThePlans"
fi

DSL_IMPORTS="$(grep -R -nE '^[[:space:]]*import[[:space:]]+' "$DSL_FIXTURE_DIR/Sources" || true)"
[[ -n "$DSL_IMPORTS" ]] || fail "DSL import fixture must import ButtonHeistDSL"
if printf '%s\n' "$DSL_IMPORTS" \
    | grep -vE '^[^:]+:[0-9]+:[[:space:]]*import[[:space:]]+ButtonHeistDSL([[:space:]]|$)'
then
    fail "DSL import fixture must import ButtonHeistDSL only"
fi

if grep -nE 'product:[[:space:]]*"ThePlans"|name:[[:space:]]*"ThePlans"' "$DSL_FIXTURE_DIR/Package.swift"; then
    fail "DSL import fixture must depend on the ButtonHeistDSL product only, not ThePlans"
fi

PUBLIC_PRODUCT_IMPORTS="$(grep -R -nE '^[[:space:]]*import[[:space:]]+' "$PUBLIC_PRODUCTS_FIXTURE_DIR/Sources" || true)"
for product in ThePlans TheScore ButtonHeistDSL ButtonHeist; do
    if ! printf '%s\n' "$PUBLIC_PRODUCT_IMPORTS" \
        | grep -Eq "^[^:]+:[0-9]+:[[:space:]]*import[[:space:]]+$product([[:space:]]|$)"
    then
        fail "public products import fixture must import $product"
    fi
    if ! grep -Eq "\\.product\\(name:[[:space:]]*\"$product\"" "$PUBLIC_PRODUCTS_FIXTURE_DIR/Package.swift"; then
        fail "public products import fixture must depend on $product"
    fi
done

IOS_PUBLIC_PRODUCT_IMPORTS="$(grep -R -nE '^[[:space:]]*import[[:space:]]+' "$IOS_PUBLIC_PRODUCTS_FIXTURE_DIR/Sources" || true)"
for product in TheInsideJob ButtonHeistTesting; do
    if ! printf '%s\n' "$IOS_PUBLIC_PRODUCT_IMPORTS" \
        | grep -Eq "^[^:]+:[0-9]+:[[:space:]]*import[[:space:]]+$product([[:space:]]|$)"
    then
        fail "iOS public products import fixture must import $product"
    fi
    if ! grep -Eq "\\.product\\(name:[[:space:]]*\"$product\"" "$IOS_PUBLIC_PRODUCTS_FIXTURE_DIR/Package.swift"; then
        fail "iOS public products import fixture must depend on $product"
    fi
done

SCRATCH_PATH="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-import-contract-build.XXXXXX")"
SWIFT_CACHE_PATH="$(mktemp -d "${TMPDIR:-/tmp}/buttonheist-import-contract-cache.XXXXXX")"
cleanup() {
    rm -rf "$SCRATCH_PATH"
    rm -rf "$SWIFT_CACHE_PATH"
    rm -f "$FIXTURE_DIR/Package.resolved"
    rm -f "$DSL_FIXTURE_DIR/Package.resolved"
    rm -f "$PUBLIC_PRODUCTS_FIXTURE_DIR/Package.resolved"
    rm -f "$IOS_PUBLIC_PRODUCTS_FIXTURE_DIR/Package.resolved"
}
trap cleanup EXIT

build_fixture() {
    local label="$1"
    local fixture_dir="$2"
    shift 2
    local scratch_dir="$SCRATCH_PATH/$(basename "$fixture_dir")"

    echo "Compiling $label"
    CLANG_MODULE_CACHE_PATH="$SWIFT_CACHE_PATH/clang" \
        swift build \
        --disable-sandbox \
        --cache-path "$SWIFT_CACHE_PATH/swiftpm" \
        --package-path "$fixture_dir" \
        --scratch-path "$scratch_dir" \
        "$@"
}

build_fixture "external ButtonHeist import contract fixture" "$FIXTURE_DIR"
build_fixture "external ButtonHeistDSL import contract fixture" "$DSL_FIXTURE_DIR"
build_fixture "external public Swift product import contract fixture" "$PUBLIC_PRODUCTS_FIXTURE_DIR"
build_fixture \
    "iOS DEBUG public products import contract fixture" \
    "$IOS_PUBLIC_PRODUCTS_FIXTURE_DIR" \
    --triple "$IOS_SIMULATOR_TRIPLE" \
    --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -Xswiftc -DDEBUG

NEGATIVE_DSL_PROBE_DIR="$SCRATCH_PATH/buttonheist-dsl-negative-import-probes"
NEGATIVE_BUTTONHEIST_PROBE_DIR="$SCRATCH_PATH/buttonheist-negative-import-probes"
mkdir -p \
    "$NEGATIVE_DSL_PROBE_DIR/Sources/ButtonHeistDSLRawSymbolProbe" \
    "$NEGATIVE_DSL_PROBE_DIR/Sources/ButtonHeistDSLNegativeTheScoreImportProbe" \
    "$NEGATIVE_BUTTONHEIST_PROBE_DIR/Sources/ButtonHeistNegativeTheInsideJobImportProbe" \
    "$NEGATIVE_BUTTONHEIST_PROBE_DIR/Sources/ButtonHeistNegativeTestingImportProbe"
cat > "$NEGATIVE_DSL_PROBE_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeistDSLNegativeImportProbes",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "ButtonHeist", path: "$REPO_ROOT")
    ],
    targets: [
        .executableTarget(
            name: "ButtonHeistDSLRawSymbolProbe",
            dependencies: [
                .product(name: "ButtonHeistDSL", package: "ButtonHeist")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ButtonHeistDSLNegativeTheScoreImportProbe",
            dependencies: [
                .product(name: "ButtonHeistDSL", package: "ButtonHeist")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
EOF
cat > "$NEGATIVE_BUTTONHEIST_PROBE_DIR/Package.swift" <<EOF
// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ButtonHeistNegativeImportProbes",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(name: "ButtonHeist", path: "$REPO_ROOT")
    ],
    targets: [
        .executableTarget(
            name: "ButtonHeistNegativeTheInsideJobImportProbe",
            dependencies: [
                .product(name: "ButtonHeist", package: "ButtonHeist")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .executableTarget(
            name: "ButtonHeistNegativeTestingImportProbe",
            dependencies: [
                .product(name: "ButtonHeist", package: "ButtonHeist")
            ],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
EOF
cat > "$NEGATIVE_DSL_PROBE_DIR/Sources/ButtonHeistDSLRawSymbolProbe/main.swift" <<'EOF'
import ButtonHeistDSL

let command = HeistActionCommand.takeScreenshot
let step = try ActionStep(command: command)
let compiler = HeistPlanSourceCompiler()
let planning = HeistPlanning.rejectRawStructuredJSONIRSourceFieldsResult
_ = (step, compiler, planning)
EOF
cat > "$NEGATIVE_BUTTONHEIST_PROBE_DIR/Sources/ButtonHeistNegativeTheInsideJobImportProbe/main.swift" <<'EOF'
import TheInsideJob

print("TheInsideJob must not be importable through ButtonHeist")
EOF
cat > "$NEGATIVE_BUTTONHEIST_PROBE_DIR/Sources/ButtonHeistNegativeTestingImportProbe/main.swift" <<'EOF'
import ButtonHeistTesting

print("ButtonHeistTesting must not be importable through ButtonHeist")
EOF
cat > "$NEGATIVE_DSL_PROBE_DIR/Sources/ButtonHeistDSLNegativeTheScoreImportProbe/main.swift" <<'EOF'
import TheScore

print("TheScore must not be importable through ButtonHeistDSL")
EOF

negative_probe() {
    local label="$1"
    local probe_dir="$2"
    local target="$3"
    local failure="$4"
    if build_fixture "$label" "$probe_dir" --target "$target"; then
        fail "$failure"
    fi
}

negative_probe \
    "negative ButtonHeistDSL raw symbol probe" \
    "$NEGATIVE_DSL_PROBE_DIR" \
    "ButtonHeistDSLRawSymbolProbe" \
    "ButtonHeistDSL import exposed raw ThePlans symbols"
negative_probe \
    "negative ButtonHeist -> TheInsideJob import probe" \
    "$NEGATIVE_BUTTONHEIST_PROBE_DIR" \
    "ButtonHeistNegativeTheInsideJobImportProbe" \
    "ButtonHeist exposed disallowed import TheInsideJob"
negative_probe \
    "negative ButtonHeist -> ButtonHeistTesting import probe" \
    "$NEGATIVE_BUTTONHEIST_PROBE_DIR" \
    "ButtonHeistNegativeTestingImportProbe" \
    "ButtonHeist exposed disallowed import ButtonHeistTesting"
negative_probe \
    "negative ButtonHeistDSL -> TheScore import probe" \
    "$NEGATIVE_DSL_PROBE_DIR" \
    "ButtonHeistDSLNegativeTheScoreImportProbe" \
    "ButtonHeistDSL exposed disallowed import TheScore"
