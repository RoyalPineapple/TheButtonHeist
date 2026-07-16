#!/usr/bin/env python3
"""Run reviewed critical-invariant mutations in a disposable exact-SHA worktree."""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import platform
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "scripts/mutations.json"


@dataclass(frozen=True)
class CommandResult:
    exit_code: int
    duration_seconds: float
    output: str
    timed_out: bool = False


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def run_command(
    command: Sequence[str],
    *,
    cwd: Path,
    timeout_seconds: float,
    environment: dict[str, str] | None = None,
) -> CommandResult:
    started = time.monotonic()
    process = subprocess.Popen(
        command,
        cwd=cwd,
        env=environment,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )
    try:
        output, _ = process.communicate(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            output, _ = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            output, _ = process.communicate()
        return CommandResult(124, time.monotonic() - started, output, timed_out=True)
    return CommandResult(process.returncode, time.monotonic() - started, output)


def load_manifest(path: Path = MANIFEST) -> tuple[dict[str, object], list[dict[str, object]]]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    if manifest.get("schemaVersion") != 1:
        raise ValueError("mutation manifest schemaVersion must be 1")
    mutations = manifest.get("mutations")
    if not isinstance(mutations, list) or not mutations:
        raise ValueError("mutation manifest must contain mutations")
    identifiers = [mutation.get("id") for mutation in mutations]
    if len(identifiers) != len(set(identifiers)):
        raise ValueError("mutation identifiers must be unique")
    return manifest, mutations


def apply_mutation(worktree: Path, mutation: dict[str, object]) -> str:
    path = worktree / str(mutation["file"])
    source = path.read_text(encoding="utf-8")
    search = str(mutation["search"])
    replacement = str(mutation["replacement"])
    if source.count(search) != 1:
        raise ValueError(
            f"{mutation['id']} expected one exact production match, found {source.count(search)}"
        )
    path.write_text(source.replace(search, replacement, 1), encoding="utf-8")
    diff = subprocess.run(
        ["git", "diff", "--binary", "--", str(mutation["file"])],
        cwd=worktree,
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    if not diff:
        raise ValueError(f"{mutation['id']} produced no production diff")
    return sha256(diff.encode())


def classification(result: CommandResult, expected_diagnostic: str) -> tuple[str, int]:
    matches = result.output.count(expected_diagnostic)
    if result.exit_code == 0:
        return "survived", matches
    if matches:
        return "detected", matches
    if result.timed_out or result.exit_code == 124:
        return "timeout", matches
    if any(marker in result.output for marker in (
        "SwiftCompile normal", "CompileSwift", "emit-module command failed", "** BUILD FAILED **",
    )):
        return "compile-error", matches
    if any(marker in result.output for marker in (
        "Test crashed", "unexpectedly exited", "terminated due to signal",
    )):
        return "test-crash", matches
    if any(marker in result.output for marker in (
        "Unable to find a device", "No available simulator", "missing destination", "inconclusive",
    )):
        return "infrastructure-error", matches
    return "unexpected-failure", matches


def read_run_record(artifacts: Path) -> dict[str, object] | None:
    records = sorted(artifacts.glob("*/run.json"))
    if len(records) != 1:
        return None
    return json.loads(records[0].read_text(encoding="utf-8"))


def select_mutations(
    mutations: list[dict[str, object]],
    identifiers: Sequence[str],
    categories: Sequence[str],
    run_all: bool,
) -> list[dict[str, object]]:
    if sum((bool(identifiers), bool(categories), run_all)) != 1:
        raise ValueError("select exactly one of --mutation, --category, or --all")
    known_ids = {str(mutation["id"]) for mutation in mutations}
    unknown = set(identifiers) - known_ids
    if unknown:
        raise ValueError(f"unknown mutations: {', '.join(sorted(unknown))}")
    selected = [
        mutation for mutation in mutations
        if run_all
        or mutation["id"] in identifiers
        or mutation["category"] in categories
    ]
    if not selected:
        raise ValueError("mutation selection is empty")
    return selected


def run_mutations(args: argparse.Namespace) -> tuple[dict[str, object], int]:
    manifest, mutations = load_manifest()
    selected = select_mutations(mutations, args.mutation, args.category, args.all)
    commit = subprocess.run(
        ["git", "rev-parse", "--verify", f"{args.commit}^{{commit}}"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    manifest_bytes = MANIFEST.read_bytes()
    output_root = args.output.resolve()
    output_root.mkdir(parents=True, exist_ok=True)
    worktree = Path(tempfile.mkdtemp(prefix="button-heist-mutations-"))
    worktree.rmdir()
    results: list[dict[str, object]] = []
    started = time.monotonic()
    try:
        subprocess.run(
            ["git", "worktree", "add", "--detach", str(worktree), commit],
            cwd=ROOT,
            check=True,
            stdout=subprocess.DEVNULL,
        )
        install = run_command(
            ["tuist", "install"], cwd=worktree, timeout_seconds=args.setup_timeout_seconds
        )
        if install.exit_code != 0:
            raise RuntimeError(f"dependency setup failed:\n{install.output}")
        for mutation in selected:
            mutation_id = str(mutation["id"])
            mutation_output = output_root / mutation_id
            if mutation_output.exists():
                shutil.rmtree(mutation_output)
            artifacts = mutation_output / "test-artifacts"
            derived = mutation_output / "derived-data"
            mutation_output.mkdir(parents=True)
            patch_fingerprint = apply_mutation(worktree, mutation)
            changed = subprocess.run(
                ["git", "diff", "--name-only"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout.splitlines()
            if changed != [mutation["file"]]:
                raise RuntimeError(f"{mutation_id} changed unexpected files: {changed}")
            environment = dict(os.environ)
            environment.update({
                "BUTTONHEIST_TEST_ARTIFACTS_DIR": str(artifacts),
                "BUTTONHEIST_TEST_DERIVED_DATA_ROOT": str(derived),
            })
            command = [
                sys.executable,
                str(worktree / "scripts/test-runner.py"),
                "run",
                "--focus",
                str(mutation["focus"]),
                "--selection",
                "full",
                "--timeout-seconds",
                str(mutation["timeoutSeconds"]),
            ]
            if args.simulator_name:
                command.extend(("--simulator-name", args.simulator_name))
            command_result = run_command(
                command,
                cwd=worktree,
                timeout_seconds=float(mutation["timeoutSeconds"]) + 30,
                environment=environment,
            )
            log_path = mutation_output / "command.log"
            log_path.write_text(command_result.output, encoding="utf-8")
            outcome, diagnostic_matches = classification(
                command_result, str(mutation["expectedDiagnostic"])
            )
            run_record = read_run_record(artifacts)
            results.append({
                "id": mutation_id,
                "category": mutation["category"],
                "owner": mutation["owner"],
                "file": mutation["file"],
                "outcome": outcome,
                "exitCode": command_result.exit_code,
                "durationSeconds": round(command_result.duration_seconds, 3),
                "expectedDiagnostic": mutation["expectedDiagnostic"],
                "diagnosticMatches": diagnostic_matches,
                "patchFingerprint": patch_fingerprint,
                "testRun": run_record,
                "log": str(log_path),
            })
            subprocess.run(
                ["git", "restore", "--source", commit, "--", str(mutation["file"])],
                cwd=worktree,
                check=True,
            )
            if subprocess.run(
                ["git", "status", "--porcelain", "--untracked-files=no"],
                cwd=worktree,
                check=True,
                text=True,
                capture_output=True,
            ).stdout:
                raise RuntimeError(f"{mutation_id} cleanup left tracked changes")
    finally:
        subprocess.run(
            ["git", "worktree", "remove", "--force", str(worktree)],
            cwd=ROOT,
            check=False,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        if worktree.exists():
            shutil.rmtree(worktree)
    detected = sum(result["outcome"] == "detected" for result in results)
    report = {
        "schemaVersion": 1,
        "commit": commit,
        "manifestFingerprint": sha256(manifest_bytes),
        "runnerFingerprint": sha256((ROOT / "scripts/test-runner.py").read_bytes()),
        "environment": {
            "platform": platform.platform(),
            "python": platform.python_version(),
            "simulatorName": args.simulator_name,
        },
        "durationSeconds": round(time.monotonic() - started, 3),
        "score": {"detected": detected, "total": len(selected)},
        "results": results,
    }
    return report, 0 if detected == len(selected) else 1


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--commit", required=True)
    parser.add_argument("--mutation", action="append", default=[])
    parser.add_argument("--category", action="append", default=[])
    parser.add_argument("--all", action="store_true")
    parser.add_argument("--simulator-name")
    parser.add_argument("--setup-timeout-seconds", type=float, default=300)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    if args.setup_timeout_seconds <= 0:
        raise ValueError("--setup-timeout-seconds must be positive")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    report, status = run_mutations(args)
    report_path = args.output.resolve() / "mutation-results.json"
    report_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(report["score"]))
    return status


if __name__ == "__main__":
    raise SystemExit(main())
