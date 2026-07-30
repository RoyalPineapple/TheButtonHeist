#!/usr/bin/env bash

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_RESULTS_DIR="${BUTTONHEIST_RESULTS_DIR:-$REPO_ROOT/.rp1/work/heist-results/manual}"
DOCTOR="${BUTTONHEIST_DOCTOR:-$REPO_ROOT/.build/debug/heist-doctor}"
BUILD_DOCTOR=true
LAST_PASS_SET=false
NEW_FAIL_SET=false
FORMAT_SET=false
ARGS=()

while [[ $# -gt 0 ]]; do
    case "$1" in
        --last-pass-dir) LAST_PASS_SET=true; ARGS+=("$1" "${2:?--last-pass-dir requires a value}"); shift 2 ;;
        --new-fail-dir) NEW_FAIL_SET=true; ARGS+=("$1" "${2:?--new-fail-dir requires a value}"); shift 2 ;;
        --doctor) DOCTOR="${2:?--doctor requires a value}"; shift 2 ;;
        --format) FORMAT_SET=true; ARGS+=("$1" "${2:?--format requires a value}"); shift 2 ;;
        --no-build) BUILD_DOCTOR=false; shift ;;
        *) ARGS+=("$1"); shift ;;
    esac
done

[[ "$LAST_PASS_SET" == true ]] || ARGS+=(--last-pass-dir "$DEFAULT_RESULTS_DIR")
[[ "$NEW_FAIL_SET" == true ]] || ARGS+=(--new-fail-dir "$DEFAULT_RESULTS_DIR")
[[ "$FORMAT_SET" == true ]] || ARGS+=(--format "${BUTTONHEIST_DOCTOR_FORMAT:-human}")

if [[ ! -x "$DOCTOR" ]]; then
    if [[ "$BUILD_DOCTOR" == true && "$DOCTOR" == "$REPO_ROOT/.build/debug/heist-doctor" ]]; then
        swift build --package-path "$REPO_ROOT" --product heist-doctor >/dev/null
    else
        echo "Error: heist-doctor executable not found: $DOCTOR" >&2
        exit 1
    fi
fi

exec "$DOCTOR" "${ARGS[@]}"
