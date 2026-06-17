#!/usr/bin/env bash
# Copy Button Heist receipt artifacts out of an iOS simulator.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/collect-ios-heist-receipts.sh SIM_UDID DEST_DIR [BUNDLE_ID]

Copies *.json and *.json.gz files found below any buttonheist-receipts directory
inside simulator data containers. Missing containers or missing receipts are not
errors; the caller can still upload DEST_DIR with diagnostic files.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

SIM_UDID="${1:-}"
DEST_DIR="${2:-}"
BUNDLE_ID="${3:-com.buttonheist.testapp}"

if [[ -z "$SIM_UDID" || -z "$DEST_DIR" ]]; then
    usage >&2
    exit 2
fi

CONTAINER="$(
    xcrun simctl get_app_container "$SIM_UDID" "$BUNDLE_ID" data 2>/dev/null || true
)"

DEVICE_DATA="$HOME/Library/Developer/CoreSimulator/Devices/$SIM_UDID/data"
SEARCH_ROOT="$DEVICE_DATA/Containers/Data"

mkdir -p "$DEST_DIR"

DIAGNOSTICS="$DEST_DIR/collection-diagnostics.txt"
{
    echo "buttonheistReceiptCollection=1"
    echo "simulatorUDID=$SIM_UDID"
    echo "bundleID=$BUNDLE_ID"
    echo "appDataContainer=${CONTAINER:-}"
    echo "deviceData=$DEVICE_DATA"
    echo "searchRoot=$SEARCH_ROOT"
    echo "receiptPattern=*/buttonheist-receipts/*.{json,json.gz}"
    echo "simctlChildReceiptsDir=${SIMCTL_CHILD_BUTTONHEIST_RECEIPTS_DIR:-}"
    echo "simctlChildReceiptsMode=${SIMCTL_CHILD_BUTTONHEIST_RECEIPTS_MODE:-}"
} > "$DIAGNOSTICS"

if [[ ! -d "$DEVICE_DATA" ]]; then
    echo "result=device-data-missing" >> "$DIAGNOSTICS"
    echo "No simulator data directory found for $SIM_UDID"
    exit 0
fi

if [[ ! -d "$SEARCH_ROOT" ]]; then
    echo "result=container-data-missing" >> "$DIAGNOSTICS"
    echo "No simulator container data directory found for $SIM_UDID"
    exit 0
fi

FOUND=false
COUNT=0

while IFS= read -r -d '' FILE; do
    RELATIVE_PATH="${FILE#"$DEVICE_DATA"/}"
    TARGET="$DEST_DIR/ios-simulator/$SIM_UDID/$RELATIVE_PATH"
    mkdir -p "$(dirname "$TARGET")"
    cp "$FILE" "$TARGET"
    FOUND=true
    COUNT=$((COUNT + 1))
done < <(
    find "$SEARCH_ROOT" \
        -type f \
        \( -name '*.json' -o -name '*.json.gz' \) \
        -path '*/buttonheist-receipts/*' \
        -print0
)

if [[ "$FOUND" == true ]]; then
    echo "result=collected" >> "$DIAGNOSTICS"
    echo "receiptFileCount=$COUNT" >> "$DIAGNOSTICS"
    echo "Collected $COUNT simulator heist receipt file(s) into $DEST_DIR"
else
    echo "result=no-receipts-found" >> "$DIAGNOSTICS"
    echo "receiptFileCount=0" >> "$DIAGNOSTICS"
    if [[ -z "$CONTAINER" || ! -d "$CONTAINER" ]]; then
        echo "note=No app data container found for $BUNDLE_ID; searched simulator data containers anyway." >> "$DIAGNOSTICS"
    fi
    echo "No simulator heist receipts found below $SEARCH_ROOT"
fi
