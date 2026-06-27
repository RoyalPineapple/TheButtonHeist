#!/usr/bin/env bash
# Compile an external SwiftPM consumer that imports ButtonHeist only.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_DIR="$REPO_ROOT/tests/fixtures/buttonheist-external-import-contract"
PUBLIC_PRODUCTS_FIXTURE_DIR="$REPO_ROOT/tests/fixtures/buttonheist-public-products-import-contract"
IOS_PUBLIC_PRODUCTS_FIXTURE_DIR="$REPO_ROOT/tests/fixtures/buttonheist-ios-public-products-import-contract"
IOS_SIMULATOR_TRIPLE="${BUTTONHEIST_SWIFT_API_IOS_SIMULATOR_TRIPLE:-arm64-apple-ios17.0-simulator}"

fail() {
    echo "Error: $*" >&2
    exit 1
}

[[ -f "$FIXTURE_DIR/Package.swift" ]] || fail "missing external import fixture Package.swift"
[[ -f "$PUBLIC_PRODUCTS_FIXTURE_DIR/Package.swift" ]] || fail "missing public products import fixture Package.swift"
[[ -f "$IOS_PUBLIC_PRODUCTS_FIXTURE_DIR/Package.swift" ]] || fail "missing iOS public products import fixture Package.swift"

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
build_fixture "external public Swift product import contract fixture" "$PUBLIC_PRODUCTS_FIXTURE_DIR"
build_fixture \
    "iOS DEBUG public products import contract fixture" \
    "$IOS_PUBLIC_PRODUCTS_FIXTURE_DIR" \
    --triple "$IOS_SIMULATOR_TRIPLE" \
    --sdk "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
    -Xswiftc -DDEBUG
