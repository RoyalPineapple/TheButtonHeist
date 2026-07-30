#!/usr/bin/env python3

from __future__ import annotations

import argparse
import gzip
import json
import math
import os
import re
import subprocess
import sys
import zlib
from dataclasses import dataclass
from enum import Enum
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
RECORDING_NAME = re.compile(
    r"^[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-"
    r"[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.json(?:\.gz)?$"
)
FINGERPRINT = re.compile(r"^[0-9a-f]{24}$")
SEMVER = re.compile(r"^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)$")
RECORDING_KEYS = {
    "schemaVersion", "result", "planName", "planFingerprint", "recordedAt", "producerVersion",
}


class TreeOutcome(str, Enum):
    PASSED = "passed"
    FAILED = "failed"
    CHILD_ABORTED = "child_aborted"
    SKIPPED = "skipped"

    @property
    def failed(self) -> bool:
        return self in (TreeOutcome.FAILED, TreeOutcome.CHILD_ABORTED)


@dataclass(frozen=True)
class Recording:
    path: Path
    fingerprint: str
    recorded_at: float
    outcome: TreeOutcome


@dataclass(frozen=True)
class RecordingWarning:
    path: Path
    reason: str


@dataclass(frozen=True)
class RecordingPair:
    last_pass: Recording
    new_fail: Recording


@dataclass(frozen=True)
class Pairing:
    pair: RecordingPair | None
    warnings: tuple[RecordingWarning, ...]


def _unique_object(pairs: list[tuple[str, object]]) -> dict[str, object]:
    value: dict[str, object] = {}
    for key, item in pairs:
        if key in value:
            raise ValueError(f"duplicate JSON key: {key}")
        value[key] = item
    return value


def _decoded_json(path: Path) -> object:
    data = path.read_bytes()
    if data.startswith(b"\x1f\x8b"):
        data = gzip.decompress(data)
    return json.loads(
        data.decode(),
        object_pairs_hook=_unique_object,
        parse_constant=lambda value: (_ for _ in ()).throw(ValueError(f"invalid JSON number: {value}")),
    )


def _object(value: object, keys: set[str], description: str) -> dict[str, object]:
    if not isinstance(value, dict) or set(value) != keys:
        raise ValueError(f"{description} has an invalid shape")
    return value


def _tree_outcome(value: object) -> TreeOutcome:
    step = _object(value, {"path", "node"}, "result step")
    if not isinstance(step["path"], str) or not step["path"]:
        raise ValueError("result step path is invalid")
    node = step["node"]
    if not isinstance(node, dict):
        raise ValueError("result step node must be an object")
    try:
        outcome = TreeOutcome(node.get("outcome"))
    except (TypeError, ValueError) as error:
        raise ValueError("result step node has an invalid outcome") from error
    children = node.get("children")
    if not isinstance(children, list):
        raise ValueError("result step node children must be an array")
    child_outcomes = tuple(_tree_outcome(child) for child in children)
    child_failed = any(child.failed for child in child_outcomes)
    if outcome is TreeOutcome.CHILD_ABORTED and not child_failed:
        raise ValueError("child-aborted result step requires a failed child")
    if outcome is not TreeOutcome.CHILD_ABORTED and child_failed:
        raise ValueError(f"{outcome.value} result step cannot contain a failed child")
    if outcome is TreeOutcome.SKIPPED and any(child is not TreeOutcome.SKIPPED for child in child_outcomes):
        raise ValueError("skipped result step children must all be skipped")
    return outcome


def decode_recording(path: Path) -> Recording:
    recording = _object(_decoded_json(path), RECORDING_KEYS, "recording root")
    version = recording["schemaVersion"]
    if isinstance(version, bool) or version != 1:
        raise ValueError("recording schema version is unsupported")
    fingerprint = recording["planFingerprint"]
    if not isinstance(fingerprint, str) or FINGERPRINT.fullmatch(fingerprint) is None:
        raise ValueError("recording plan fingerprint is invalid")
    recorded_at = recording["recordedAt"]
    if isinstance(recorded_at, bool) or not isinstance(recorded_at, (int, float)) or not math.isfinite(recorded_at):
        raise ValueError("recording time is invalid")
    plan_name = recording["planName"]
    if plan_name is not None and (not isinstance(plan_name, str) or not plan_name):
        raise ValueError("recording plan name is invalid")
    producer_version = recording["producerVersion"]
    if not isinstance(producer_version, str) or SEMVER.fullmatch(producer_version) is None:
        raise ValueError("recording producer version is invalid")
    result = _object(recording["result"], {"steps", "durationMs"}, "recording result")
    duration = result["durationMs"]
    if isinstance(duration, bool) or not isinstance(duration, int) or duration < 0:
        raise ValueError("recording result duration is invalid")
    steps = result["steps"]
    if not isinstance(steps, list):
        raise ValueError("recording result steps must be an array")
    outcomes = tuple(_tree_outcome(step) for step in steps)
    outcome = TreeOutcome.FAILED if any(item.failed for item in outcomes) else TreeOutcome.PASSED
    return Recording(path, fingerprint, float(recorded_at), outcome)


def _discover(root: Path) -> tuple[tuple[Recording, ...], tuple[RecordingWarning, ...]]:
    recordings: list[Recording] = []
    warnings: list[RecordingWarning] = []
    paths = sorted(
        (path for path in root.rglob("*") if path.is_file() and RECORDING_NAME.fullmatch(path.name)),
        key=lambda path: path.as_posix(),
    )
    for path in paths:
        try:
            recordings.append(decode_recording(path))
        except (EOFError, OSError, RecursionError, UnicodeError, ValueError, zlib.error) as error:
            warnings.append(RecordingWarning(path, str(error)))
    return tuple(recordings), tuple(warnings)


def pair_recordings(last_pass_root: Path, new_fail_root: Path) -> Pairing:
    passes, pass_warnings = _discover(last_pass_root)
    if last_pass_root.resolve() == new_fail_root.resolve():
        failures, fail_warnings = passes, ()
    else:
        failures, fail_warnings = _discover(new_fail_root)
    newest_first = sorted(
        (recording for recording in failures if recording.outcome is TreeOutcome.FAILED),
        key=lambda recording: (recording.recorded_at, recording.path.as_posix()),
        reverse=True,
    )
    for failure in newest_first:
        last_pass = max(
            (
                recording for recording in passes
                if recording.outcome is TreeOutcome.PASSED
                and recording.fingerprint == failure.fingerprint
                and recording.recorded_at < failure.recorded_at
            ),
            key=lambda recording: (recording.recorded_at, recording.path.as_posix()),
            default=None,
        )
        if last_pass:
            return Pairing(RecordingPair(last_pass, failure), pass_warnings + fail_warnings)
    return Pairing(None, pass_warnings + fail_warnings)


def _arguments(argv: list[str] | None) -> argparse.Namespace:
    results = Path(os.environ.get(
        "BUTTONHEIST_RESULTS_DIR", REPO_ROOT / ".rp1/work/heist-results/manual",
    ))
    parser = argparse.ArgumentParser(description="Pair result recordings and run heist-doctor.")
    parser.add_argument("--last-pass-dir", type=Path, default=results)
    parser.add_argument("--new-fail-dir", type=Path, default=results)
    parser.add_argument("--doctor", type=Path, default=Path(os.environ.get(
        "BUTTONHEIST_DOCTOR", REPO_ROOT / ".build/debug/heist-doctor",
    )))
    parser.add_argument(
        "--format", choices=("human", "json"),
        default=os.environ.get("BUTTONHEIST_DOCTOR_FORMAT", "human"),
    )
    parser.add_argument("--step-path")
    parser.add_argument("--no-build", action="store_true")
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    arguments = _arguments(argv)
    for label, root in (("last-pass", arguments.last_pass_dir), ("new-fail", arguments.new_fail_dir)):
        if not root.is_dir():
            print(f"Error: {label} result directory not found: {root}", file=sys.stderr)
            return 1
    default_doctor = REPO_ROOT / ".build/debug/heist-doctor"
    if not os.access(arguments.doctor, os.X_OK):
        if arguments.no_build or arguments.doctor != default_doctor:
            print(f"Error: heist-doctor executable not found: {arguments.doctor}", file=sys.stderr)
            return 1
        build = subprocess.run(
            ("swift", "build", "--package-path", str(REPO_ROOT), "--product", "heist-doctor"),
            check=False,
            stdout=subprocess.DEVNULL,
        )
        if build.returncode:
            return build.returncode

    pairing = pair_recordings(arguments.last_pass_dir, arguments.new_fail_dir)
    for warning in pairing.warnings:
        print(f"Warning: ignoring invalid heist result recording {warning.path}: {warning.reason}", file=sys.stderr)
    if pairing.pair is None:
        print(
            "Error: no doctor-ready result pair found. Need a failed recording and a prior "
            "passed recording with the same decoded plan fingerprint.",
            file=sys.stderr,
        )
        return 1
    pair = pairing.pair
    print(
        f"Selected doctor result pair:\n  fingerprint: {pair.new_fail.fingerprint}\n"
        f"  last pass:   {pair.last_pass.path}\n  new fail:    {pair.new_fail.path}\n"
    )
    doctor_arguments = [
        str(arguments.doctor), "--last-pass", str(pair.last_pass.path),
        "--new-fail", str(pair.new_fail.path), "--format", arguments.format,
    ]
    if arguments.step_path:
        doctor_arguments.extend(("--step-path", arguments.step_path))
    return subprocess.run(doctor_arguments, check=False).returncode


if __name__ == "__main__":
    raise SystemExit(main())
