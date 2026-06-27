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

cd "$ROOT"

args=(
    run
    --package-path
    ButtonHeist
    --disable-automatic-resolution
    buttonheist-docgen
    --output-dir
    docs/reference
)

if [[ "$CHECK_MODE" -eq 1 ]]; then
    args+=(--check)
fi

swift "${args[@]}"

if [[ "$CHECK_MODE" -eq 1 ]]; then
    echo "Generated reference docs are up to date."
fi
