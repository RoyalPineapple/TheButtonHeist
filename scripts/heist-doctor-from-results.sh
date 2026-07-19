#!/usr/bin/env bash
# Find a matching passed/failed result pair and run heist-doctor.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEFAULT_RESULTS_DIR="${BUTTONHEIST_RESULTS_DIR:-$REPO_ROOT/.rp1/work/heist-results/manual}"
LAST_PASS_DIR="$DEFAULT_RESULTS_DIR"
NEW_FAIL_DIR="$DEFAULT_RESULTS_DIR"
DOCTOR="${BUTTONHEIST_DOCTOR:-$REPO_ROOT/.build/debug/heist-doctor}"
FORMAT="${BUTTONHEIST_DOCTOR_FORMAT:-human}"
STEP_PATH=""
BUILD_DOCTOR=true

usage() {
    cat <<'EOF'
Usage: scripts/heist-doctor-from-results.sh [options]

Options:
  --last-pass-dir DIR  Root containing passed result artifacts.
  --new-fail-dir DIR   Root containing failed result artifacts.
  --doctor PATH        heist-doctor executable. Defaults to .build/debug/heist-doctor.
  --format FORMAT      Doctor output format: human or json. Defaults to human.
  --step-path PATH     Optional action step path to pass to heist-doctor.
  --no-build           Do not build heist-doctor when the executable is missing.
  -h, --help           Show this help.

The script matches results by their parent heist-name/fingerprint directory.
It selects the newest failed result that has a matching passed result, then
runs heist-doctor with that pair.
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --last-pass-dir)
            LAST_PASS_DIR="${2:-}"
            [[ -n "$LAST_PASS_DIR" ]] || {
                echo "Error: --last-pass-dir requires a value" >&2
                exit 2
            }
            shift 2
            ;;
        --new-fail-dir)
            NEW_FAIL_DIR="${2:-}"
            [[ -n "$NEW_FAIL_DIR" ]] || {
                echo "Error: --new-fail-dir requires a value" >&2
                exit 2
            }
            shift 2
            ;;
        --doctor)
            DOCTOR="${2:-}"
            [[ -n "$DOCTOR" ]] || {
                echo "Error: --doctor requires a value" >&2
                exit 2
            }
            shift 2
            ;;
        --format)
            FORMAT="${2:-}"
            [[ "$FORMAT" == "human" || "$FORMAT" == "json" ]] || {
                echo "Error: --format must be human or json" >&2
                exit 2
            }
            shift 2
            ;;
        --step-path)
            STEP_PATH="${2:-}"
            [[ -n "$STEP_PATH" ]] || {
                echo "Error: --step-path requires a value" >&2
                exit 2
            }
            shift 2
            ;;
        --no-build)
            BUILD_DOCTOR=false
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Error: unknown option: $1" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if [[ ! -d "$LAST_PASS_DIR" ]]; then
    echo "Error: last-pass result directory not found: $LAST_PASS_DIR" >&2
    exit 1
fi
if [[ ! -d "$NEW_FAIL_DIR" ]]; then
    echo "Error: new-fail result directory not found: $NEW_FAIL_DIR" >&2
    exit 1
fi

if [[ ! -x "$DOCTOR" ]]; then
    if [[ "$BUILD_DOCTOR" == true && "$DOCTOR" == "$REPO_ROOT/.build/debug/heist-doctor" ]]; then
        swift build --package-path "$REPO_ROOT" --product heist-doctor >/dev/null
    else
        echo "Error: heist-doctor executable not found: $DOCTOR" >&2
        exit 1
    fi
fi

PAIR_OUTPUT="$(
    python3 - "$LAST_PASS_DIR" "$NEW_FAIL_DIR" <<'PY'
from __future__ import annotations

import pathlib
import sys

last_pass_dir = pathlib.Path(sys.argv[1])
new_fail_dir = pathlib.Path(sys.argv[2])


def results(root: pathlib.Path, status: str) -> list[pathlib.Path]:
    suffixes = (f"-{status}.json", f"-{status}.json.gz")
    return sorted(
        (
            path
            for path in root.rglob("*")
            if path.is_file() and path.name.endswith(suffixes)
        ),
        key=lambda path: (path.stat().st_mtime_ns, path.as_posix()),
        reverse=True,
    )


passes_by_key: dict[str, list[pathlib.Path]] = {}
for result in results(last_pass_dir, "passed"):
    passes_by_key.setdefault(result.parent.name, []).append(result)

for failed in results(new_fail_dir, "failed"):
    matches = passes_by_key.get(failed.parent.name, [])
    if matches:
        print(matches[0])
        print(failed)
        print(failed.parent.name)
        raise SystemExit(0)

print(
    "Error: no doctor-ready result pair found. "
    "Need a failed result and a passed result with the same heist fingerprint directory.",
    file=sys.stderr,
)
raise SystemExit(1)
PY
)"

LAST_PASS_RESULT="$(printf '%s\n' "$PAIR_OUTPUT" | sed -n '1p')"
NEW_FAIL_RESULT="$(printf '%s\n' "$PAIR_OUTPUT" | sed -n '2p')"
FINGERPRINT_DIR="$(printf '%s\n' "$PAIR_OUTPUT" | sed -n '3p')"

echo "Selected doctor result pair:"
echo "  fingerprint: $FINGERPRINT_DIR"
echo "  last pass:   $LAST_PASS_RESULT"
echo "  new fail:    $NEW_FAIL_RESULT"
echo

ARGS=(
    --last-pass "$LAST_PASS_RESULT"
    --new-fail "$NEW_FAIL_RESULT"
    --format "$FORMAT"
)
if [[ -n "$STEP_PATH" ]]; then
    ARGS+=(--step-path "$STEP_PATH")
fi

"$DOCTOR" "${ARGS[@]}"
