#!/usr/bin/env python3
"""Select critical mutations by stable subsystem ownership."""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Iterable
from pathlib import Path


ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "scripts/mutations.json"
OWNER_PREFIXES = {
    "receipts": (
        "ButtonHeist/Sources/TheScore/Receipts/",
        "ButtonHeist/Tests/TheScoreTests/HeistExecution",
        "ButtonHeist/Tests/TheScoreTests/ButtonHeistTestSupportTests.swift",
        "ButtonHeist/Tests/ButtonHeistTests/TheFenceCompactFormattingContractTests.swift",
    ),
    "release": (
        ".github/workflows/",
        "scripts/exact-sha-suite.jq",
        "scripts/require-successful-ci-for-commit.sh",
        "scripts/tests/require-successful-ci-for-commit-test.sh",
        "scripts/validate-release-contract.sh",
    ),
    "inflation": (
        "ButtonHeist/Sources/TheInsideJob/TheBrains/ElementInflation",
        "ButtonHeist/Tests/TheInsideJobTests/ElementInflationProductTests.swift",
    ),
    "interaction": (
        "ButtonHeist/Sources/TheInsideJob/TheBrains/TheBrains.swift",
        "ButtonHeist/Tests/TheInsideJobTests/ClientRequestPipelineTests.swift",
    ),
    "screen-generation": (
        "ButtonHeist/Sources/TheInsideJob/TheBrains/ScreenClassifier.swift",
        "ButtonHeist/Tests/TheInsideJobTests/ScreenClassifierTests.swift",
    ),
    "settlement": (
        "ButtonHeist/Sources/TheInsideJob/TheBrains/SettleSession.swift",
        "ButtonHeist/Tests/TheInsideJobTests/SettleSessionTests.swift",
    ),
    "discovery": (
        "ButtonHeist/Sources/TheButtonHeist/TheHandoff/DeviceDiscovery",
        "ButtonHeist/Tests/ButtonHeistTests/TheHandoffStateTests.swift",
    ),
}
MUTATION_TOOLING = {
    "scripts/mutation-gate.py",
    "scripts/mutations.json",
    "scripts/select-critical-mutations.py",
    "scripts/test-runner.py",
    "scripts/tests/mutation-gate-test.py",
    "scripts/tests/select-critical-mutations-test.py",
    "scripts/tests/test-runner-test.py",
}


def normalize(path: str) -> str:
    normalized = path.strip().replace("\\", "/")
    while normalized.startswith("./"):
        normalized = normalized[2:]
    return normalized


def load_inventory() -> tuple[list[str], list[dict[str, object]]]:
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return manifest["alwaysOn"], manifest["mutations"]


def select(paths: Iterable[str]) -> list[str]:
    always_on, mutations = load_inventory()
    changed = sorted({normalize(path) for path in paths if normalize(path)})
    if not changed or any(path in MUTATION_TOOLING for path in changed):
        return [str(mutation["id"]) for mutation in mutations]
    scopes = {
        scope
        for path in changed
        for scope, prefixes in OWNER_PREFIXES.items()
        if any(path.startswith(prefix) for prefix in prefixes)
    }
    if any(
        path.startswith("ButtonHeist/Sources/")
        and not any(path.startswith(prefix) for prefixes in OWNER_PREFIXES.values() for prefix in prefixes)
        for path in changed
    ):
        return [str(mutation["id"]) for mutation in mutations]
    selected = set(always_on)
    selected.update(
        str(mutation["id"])
        for mutation in mutations
        if mutation["scope"] in scopes
    )
    return [str(mutation["id"]) for mutation in mutations if mutation["id"] in selected]


def mutation_arguments(identifiers: Iterable[str]) -> str:
    return " ".join(f"--mutation {identifier}" for identifier in identifiers)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--github-output", type=Path)
    args = parser.parse_args()
    paths = args.paths or sys.stdin.read().splitlines()
    identifiers = select(paths)
    output = mutation_arguments(identifiers)
    print(output)
    if args.github_output:
        with args.github_output.open("a", encoding="utf-8") as handle:
            handle.write(f"mutation_args={output}\n")


if __name__ == "__main__":
    main()
