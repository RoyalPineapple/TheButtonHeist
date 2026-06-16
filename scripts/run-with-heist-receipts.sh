#!/usr/bin/env bash
# Run a command with Button Heist receipt recording enabled.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RECEIPTS_DIR="${BUTTONHEIST_RECEIPTS_DIR:-}"
RECEIPTS_MODE="${BUTTONHEIST_RECEIPTS_MODE:-failures}"
SUITE_NAME=""

usage() {
    cat <<'EOF'
Usage: scripts/run-with-heist-receipts.sh [options] -- COMMAND [ARG...]

Options:
  --dir DIR       Directory for host-side receipt artifacts.
  --ios-sandbox  Use the process temp-directory sentinel for simulator-hosted tests.
  --mode MODE    Recording mode: failures, failing-and-passing, all, or off.
  --suite NAME   Derive the default directory from .rp1/work/heist-receipts/NAME.
  -h, --help     Show this help.

The wrapper only sets BUTTONHEIST_RECEIPTS_DIR and BUTTONHEIST_RECEIPTS_MODE.
The command's normal exit status is preserved.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dir)
            RECEIPTS_DIR="${2:-}"
            [[ -n "$RECEIPTS_DIR" ]] || {
                echo "Error: --dir requires a value" >&2
                exit 2
            }
            shift 2
            ;;
        --ios-sandbox)
            RECEIPTS_DIR="process-temporary-directory"
            shift
            ;;
        --mode)
            RECEIPTS_MODE="${2:-}"
            [[ -n "$RECEIPTS_MODE" ]] || {
                echo "Error: --mode requires a value" >&2
                exit 2
            }
            shift 2
            ;;
        --suite)
            SUITE_NAME="${2:-}"
            [[ -n "$SUITE_NAME" ]] || {
                echo "Error: --suite requires a value" >&2
                exit 2
            }
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ $# -lt 1 ]]; then
    usage >&2
    exit 2
fi

if [[ -z "$RECEIPTS_DIR" ]]; then
    if [[ -n "$SUITE_NAME" ]]; then
        RECEIPTS_DIR="$REPO_ROOT/.rp1/work/heist-receipts/$SUITE_NAME"
    else
        RECEIPTS_DIR="$REPO_ROOT/.rp1/work/heist-receipts/manual"
    fi
fi

if [[ "$RECEIPTS_DIR" != "process-temporary-directory" ]]; then
    mkdir -p "$RECEIPTS_DIR"
fi

export BUTTONHEIST_RECEIPTS_DIR="$RECEIPTS_DIR"
export BUTTONHEIST_RECEIPTS_MODE="$RECEIPTS_MODE"

exec "$@"
