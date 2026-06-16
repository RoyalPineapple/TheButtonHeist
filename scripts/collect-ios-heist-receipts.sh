#!/usr/bin/env bash
# Copy Button Heist receipt artifacts out of an iOS simulator app container.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/collect-ios-heist-receipts.sh SIM_UDID DEST_DIR [BUNDLE_ID]

Copies *.json and *.json.gz files found below any buttonheist-receipts directory
inside the app data container. Missing containers or missing receipts are not
errors; the caller can still upload DEST_DIR with if-no-files-found: ignore.
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

if [[ -z "$CONTAINER" || ! -d "$CONTAINER" ]]; then
    echo "No app data container found for $BUNDLE_ID on $SIM_UDID"
    exit 0
fi

mkdir -p "$DEST_DIR"
FOUND=false

while IFS= read -r -d '' FILE; do
    RELATIVE_PATH="${FILE#"$CONTAINER"/}"
    TARGET="$DEST_DIR/ios-simulator/$BUNDLE_ID/$RELATIVE_PATH"
    mkdir -p "$(dirname "$TARGET")"
    cp "$FILE" "$TARGET"
    FOUND=true
done < <(
    find "$CONTAINER" \
        -type f \
        \( -name '*.json' -o -name '*.json.gz' \) \
        -path '*/buttonheist-receipts/*' \
        -print0
)

if [[ "$FOUND" == true ]]; then
    echo "Collected simulator heist receipts into $DEST_DIR"
else
    echo "No simulator heist receipts found in $CONTAINER"
fi
