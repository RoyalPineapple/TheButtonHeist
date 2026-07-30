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

The script discovers self-contained UUID.json and UUID.json.gz recordings.
It selects the newest failed recording that has a passed recording with the
same decoded plan fingerprint, then runs heist-doctor with that pair.
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

import gzip
import json
import math
import pathlib
import re
import sys
import zlib

last_pass_dir = pathlib.Path(sys.argv[1])
new_fail_dir = pathlib.Path(sys.argv[2])
recording_name = re.compile(
    r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.json(?:\.gz)?$"
)
recording_keys = {
    "schemaVersion",
    "result",
    "planName",
    "planFingerprint",
    "recordedAt",
    "producerVersion",
}


def recording_paths(root: pathlib.Path) -> list[pathlib.Path]:
    return sorted(
        (path for path in root.rglob("*") if path.is_file() and recording_name.fullmatch(path.name)),
        key=lambda path: path.as_posix(),
    )


def decoded_json(path: pathlib.Path) -> object:
    data = path.read_bytes()
    if data.startswith(b"\x1f\x8b"):
        data = gzip.decompress(data)
    return json.loads(data.decode("utf-8"))


def step_failed(step: object) -> bool:
    if not isinstance(step, dict) or set(step) != {"path", "node"}:
        raise ValueError("result step must contain exactly path and node")
    node = step["node"]
    if not isinstance(node, dict):
        raise ValueError("result step node must be an object")
    outcome = node.get("outcome")
    if outcome not in {"passed", "failed", "child_aborted", "skipped"}:
        raise ValueError("result step node has an invalid outcome")
    children = node.get("children")
    if not isinstance(children, list):
        raise ValueError("result step node children must be an array")
    return outcome in {"failed", "child_aborted"} or any(step_failed(child) for child in children)


def decode_recording(path: pathlib.Path) -> tuple[str, str, float, pathlib.Path]:
    recording = decoded_json(path)
    if not isinstance(recording, dict) or set(recording) != recording_keys:
        raise ValueError("recording root has an invalid shape")
    if recording["schemaVersion"] != 1:
        raise ValueError("recording schema version is unsupported")
    fingerprint = recording["planFingerprint"]
    if not isinstance(fingerprint, str) or re.fullmatch(r"[0-9a-f]{24}", fingerprint) is None:
        raise ValueError("recording plan fingerprint is invalid")
    recorded_at = recording["recordedAt"]
    if (
        isinstance(recorded_at, bool)
        or not isinstance(recorded_at, (int, float))
        or not math.isfinite(recorded_at)
    ):
        raise ValueError("recording time is invalid")
    result = recording["result"]
    if not isinstance(result, dict) or set(result) != {"steps", "durationMs"}:
        raise ValueError("recording result has an invalid shape")
    steps = result["steps"]
    if not isinstance(steps, list):
        raise ValueError("recording result steps must be an array")
    outcome = "failed" if any(step_failed(step) for step in steps) else "passed"
    return fingerprint, outcome, float(recorded_at), path


def recordings(root: pathlib.Path) -> list[tuple[str, str, float, pathlib.Path]]:
    decoded = []
    for path in recording_paths(root):
        try:
            decoded.append(decode_recording(path))
        except (
            EOFError,
            OSError,
            UnicodeError,
            gzip.BadGzipFile,
            json.JSONDecodeError,
            ValueError,
            zlib.error,
        ) as error:
            print(f"Warning: ignoring invalid heist result recording {path}: {error}", file=sys.stderr)
    return decoded


passes_by_fingerprint: dict[str, list[tuple[str, str, float, pathlib.Path]]] = {}
for recording in recordings(last_pass_dir):
    fingerprint, outcome, _, _ = recording
    if outcome == "passed":
        passes_by_fingerprint.setdefault(fingerprint, []).append(recording)

for matches in passes_by_fingerprint.values():
    matches.sort(key=lambda recording: (recording[2], recording[3].as_posix()), reverse=True)

failed_recordings = [
    recording
    for recording in recordings(new_fail_dir)
    if recording[1] == "failed"
]
failed_recordings.sort(key=lambda recording: (recording[2], recording[3].as_posix()), reverse=True)

for fingerprint, _, _, failed_path in failed_recordings:
    matches = passes_by_fingerprint.get(fingerprint, [])
    if matches:
        print(matches[0][3])
        print(failed_path)
        print(fingerprint)
        raise SystemExit(0)

print(
    "Error: no doctor-ready result pair found. "
    "Need a failed recording and a passed recording with the same decoded plan fingerprint.",
    file=sys.stderr,
)
raise SystemExit(1)
PY
)"

LAST_PASS_RESULT="$(printf '%s\n' "$PAIR_OUTPUT" | sed -n '1p')"
NEW_FAIL_RESULT="$(printf '%s\n' "$PAIR_OUTPUT" | sed -n '2p')"
PLAN_FINGERPRINT="$(printf '%s\n' "$PAIR_OUTPUT" | sed -n '3p')"

echo "Selected doctor result pair:"
echo "  fingerprint: $PLAN_FINGERPRINT"
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
