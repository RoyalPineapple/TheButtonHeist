#!/usr/bin/env python3
"""Report SwiftPM Package.resolved pin drift across the repository."""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import defaultdict
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parents[1]
SKIPPED_DISCOVERY_DIRS = {
    ".build",
    ".git",
    ".swiftpm",
    "DerivedData",
}


@dataclass(frozen=True)
class ResolvedPin:
    identity: str
    package_file: Path
    version: str | None
    revision: str | None

    @property
    def comparable_pin(self) -> tuple[str | None, str | None]:
        return (self.version, self.revision)


def relative_path(path: Path) -> str:
    return path.relative_to(REPO_ROOT).as_posix()


def display_value(value: str | None) -> str:
    if value is None:
        return "<none>"
    return value


def discover_lockfiles() -> list[Path]:
    """Return tracked Package.resolved files, falling back to filesystem discovery."""
    result = subprocess.run(
        ["git", "ls-files", "*Package.resolved"],
        cwd=REPO_ROOT,
        check=False,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
    )
    if result.returncode == 0:
        paths = [
            REPO_ROOT / line
            for line in result.stdout.splitlines()
            if line.strip()
        ]
        if paths:
            return sorted(paths, key=relative_path)

    discovered: list[Path] = []
    for path in REPO_ROOT.rglob("Package.resolved"):
        relative_parts = path.relative_to(REPO_ROOT).parts
        if SKIPPED_DISCOVERY_DIRS.intersection(relative_parts):
            continue
        discovered.append(path)
    return sorted(discovered, key=relative_path)


def load_lockfile(path: Path) -> list[ResolvedPin]:
    try:
        with path.open(encoding="utf-8") as file:
            package_resolved = json.load(file)
    except json.JSONDecodeError as error:
        raise ValueError(f"{relative_path(path)} is not valid JSON: {error}") from error

    pins = package_resolved.get("pins")
    if pins is None and isinstance(package_resolved.get("object"), dict):
        pins = package_resolved["object"].get("pins")
    if not isinstance(pins, list):
        raise ValueError(f"{relative_path(path)} does not contain a pins array")

    resolved_pins: list[ResolvedPin] = []
    for index, pin in enumerate(pins):
        if not isinstance(pin, dict):
            raise ValueError(f"{relative_path(path)} pin #{index + 1} is not an object")

        identity = normalized_identity(pin)
        state = pin.get("state", {})
        if not isinstance(state, dict):
            raise ValueError(
                f"{relative_path(path)} pin {identity!r} has a non-object state"
            )

        resolved_pins.append(
            ResolvedPin(
                identity=identity,
                package_file=path,
                version=normalized_optional_string(state.get("version")),
                revision=normalized_optional_string(state.get("revision")),
            )
        )
    return resolved_pins


def normalized_identity(pin: dict[str, Any]) -> str:
    identity = pin.get("identity") or pin.get("package")
    if not isinstance(identity, str) or not identity.strip():
        raise ValueError(f"Package.resolved pin is missing an identity: {pin!r}")
    return identity.strip().lower()


def normalized_optional_string(value: Any) -> str | None:
    if value is None:
        return None
    if not isinstance(value, str):
        return str(value)
    return value


def drifted_shared_identities(
    pins: list[ResolvedPin],
) -> dict[str, dict[tuple[str | None, str | None], list[Path]]]:
    by_identity: dict[str, list[ResolvedPin]] = defaultdict(list)
    for pin in pins:
        by_identity[pin.identity].append(pin)

    drift: dict[str, dict[tuple[str | None, str | None], list[Path]]] = {}
    for identity, identity_pins in sorted(by_identity.items()):
        package_files = {pin.package_file for pin in identity_pins}
        comparable_pins = {pin.comparable_pin for pin in identity_pins}
        if len(package_files) < 2 or len(comparable_pins) < 2:
            continue

        by_comparable_pin: dict[
            tuple[str | None, str | None],
            list[Path],
        ] = defaultdict(list)
        for pin in identity_pins:
            by_comparable_pin[pin.comparable_pin].append(pin.package_file)
        drift[identity] = {
            comparable_pin: sorted(paths, key=relative_path)
            for comparable_pin, paths in sorted(
                by_comparable_pin.items(),
                key=lambda item: (
                    display_value(item[0][0]),
                    display_value(item[0][1]),
                ),
            )
        }
    return drift


def print_report(
    lockfiles: list[Path],
    drift: dict[str, dict[tuple[str | None, str | None], list[Path]]],
    *,
    fail_on_drift: bool,
) -> None:
    if not drift:
        print(
            "Checked "
            f"{len(lockfiles)} Package.resolved files; shared package pins are aligned."
        )
        return

    print("SwiftPM Package.resolved drift found.")
    print(f"Checked {len(lockfiles)} Package.resolved files.")
    for identity, pin_groups in drift.items():
        print(f"\n{identity}:")
        for (version, revision), package_files in pin_groups.items():
            print(
                "  pin "
                f"version={display_value(version)} "
                f"revision={display_value(revision)}"
            )
            for package_file in package_files:
                print(f"    - {relative_path(package_file)}")

    if fail_on_drift:
        print("\nFailing because --fail-on-drift was provided.")
    else:
        print("\nReport-only mode: exiting 0. Use --fail-on-drift to fail on drift.")


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Compare shared SwiftPM Package.resolved identities and report "
            "version/revision drift."
        )
    )
    parser.add_argument(
        "--report-only",
        action="store_true",
        help="Exit 0 even when drift is found. This is the default.",
    )
    parser.add_argument(
        "--fail-on-drift",
        action="store_true",
        help="Exit 1 when shared package identities have different pins.",
    )
    args = parser.parse_args(argv)
    if args.report_only and args.fail_on_drift:
        parser.error("--report-only and --fail-on-drift cannot be used together")
    return args


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    try:
        lockfiles = discover_lockfiles()
        if not lockfiles:
            raise ValueError("No Package.resolved files found")

        pins = [
            pin
            for lockfile in lockfiles
            for pin in load_lockfile(lockfile)
        ]
    except ValueError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1

    drift = drifted_shared_identities(pins)
    print_report(lockfiles, drift, fail_on_drift=args.fail_on_drift)
    if drift and args.fail_on_drift:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
