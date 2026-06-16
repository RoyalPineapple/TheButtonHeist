#!/usr/bin/env bash
# Write a small manifest so CI receipt artifact bundles are discoverable.

set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/write-ci-heist-receipt-manifest.sh DEST_DIR [JOB_LABEL]

Creates DEST_DIR when needed and writes:
  manifest.txt       CI context and receipt counts
  receipt-files.txt  Receipt file list with byte counts, or "(none)"

The manifest is intentionally plain text so it remains useful from a browser,
terminal, or downloaded GitHub Actions artifact without extra tooling.
EOF
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage
    exit 0
fi

DEST_DIR="${1:-}"
JOB_LABEL="${2:-${GITHUB_JOB:-unknown}}"

if [[ -z "$DEST_DIR" ]]; then
    usage >&2
    exit 2
fi

mkdir -p "$DEST_DIR"

MANIFEST="$DEST_DIR/manifest.txt"
FILE_LIST="$DEST_DIR/receipt-files.txt"
receipt_count=0
receipt_bytes=0

: > "$FILE_LIST"
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    size="$(wc -c < "$file" | tr -d '[:space:]')"
    relative_path="${file#"$DEST_DIR"/}"
    printf '%s\t%s\n' "$size" "$relative_path" >> "$FILE_LIST"
    receipt_count=$((receipt_count + 1))
    receipt_bytes=$((receipt_bytes + size))
done < <(
    find "$DEST_DIR" \
        -type f \
        \( -name '*.json' -o -name '*.json.gz' \) \
        -print \
        | LC_ALL=C sort
)

if [[ "$receipt_count" -eq 0 ]]; then
    echo "(none)" > "$FILE_LIST"
fi

{
    echo "buttonheistReceiptArtifact=1"
    echo "job=$JOB_LABEL"
    echo "githubJob=${GITHUB_JOB:-}"
    echo "workflow=${GITHUB_WORKFLOW:-}"
    echo "runId=${GITHUB_RUN_ID:-}"
    echo "runAttempt=${GITHUB_RUN_ATTEMPT:-}"
    echo "event=${GITHUB_EVENT_NAME:-}"
    echo "ref=${GITHUB_REF:-}"
    echo "sha=${GITHUB_SHA:-}"
    echo "receiptMode=${BUTTONHEIST_RECEIPTS_MODE:-}"
    echo "receiptDirectory=$DEST_DIR"
    echo "receiptFileCount=$receipt_count"
    echo "receiptBytes=$receipt_bytes"
    echo "receiptList=receipt-files.txt"
    echo "createdAt=$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
} > "$MANIFEST"

echo "Wrote heist receipt manifest to $MANIFEST ($receipt_count receipt files, $receipt_bytes bytes)"
