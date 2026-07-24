#!/usr/bin/env python3
"""Select, create if needed, and boot the iOS simulator used by CI."""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
from pathlib import Path
from typing import Any


DEFAULT_PREFERRED_DEVICE = "iPhone 16 Pro"


def run(cmd: list[str], *, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(cmd, check=check, text=True, capture_output=True)


def load_json(cmd: list[str]) -> Any:
    return json.loads(run(cmd).stdout)


def version_key(version: str) -> tuple[int, ...]:
    if re.fullmatch(r"\d+(?:\.\d+)*", version) is None:
        raise ValueError(f"Invalid platform version: {version}")
    parts = [int(part) for part in version.split(".")]
    while len(parts) > 1 and parts[-1] == 0:
        parts.pop()
    return tuple(parts)


def sanitize(value: str) -> str:
    value = re.sub(r"[^A-Za-z0-9]+", "-", value.lower()).strip("-")
    return value or "simulator"


def default_sim_name(preferred_device: str) -> str:
    job = sanitize(os.environ.get("GITHUB_JOB", "ios"))
    run_id = sanitize(os.environ.get("GITHUB_RUN_ID", "local"))
    attempt = sanitize(os.environ.get("GITHUB_RUN_ATTEMPT", "1"))
    device = sanitize(preferred_device)
    return f"buttonheist-ci-{job}-{run_id}-{attempt}-{device}"


def ios_runtimes(
    runtimes: list[dict[str, Any]], maximum: tuple[int, ...],
    requested: tuple[int, ...] | None = None,
) -> list[dict[str, Any]]:
    return sorted(
        [
            runtime
            for runtime in runtimes
            if runtime.get("platform") == "iOS" and runtime.get("isAvailable") is True
            and version_key(str(runtime.get("version", ""))) <= maximum
            and (requested is None or version_key(str(runtime.get("version", ""))) == requested)
        ],
        key=lambda runtime: version_key(str(runtime.get("version", ""))),
        reverse=True,
    )


def supported_type_lookup(runtime: dict[str, Any]) -> dict[str, dict[str, Any]]:
    return {
        device_type["identifier"]: device_type
        for device_type in runtime.get("supportedDeviceTypes", [])
        if device_type.get("identifier")
    }


def is_iphone_type(device_type: dict[str, Any] | None, device_name: str) -> bool:
    if device_type:
        return (
            device_type.get("productFamily") == "iPhone"
            and str(device_type.get("name", "")).startswith("iPhone")
        )
    return device_name.startswith("iPhone")


def existing_simulator(
    runtimes: list[dict[str, Any]],
    devices: dict[str, list[dict[str, Any]]],
    sim_name: str,
) -> dict[str, str] | None:
    for runtime in runtimes:
        runtime_id = str(runtime["identifier"])
        type_lookup = supported_type_lookup(runtime)
        for device in devices.get(runtime_id, []):
            if device.get("isAvailable") is not True or device.get("name") != sim_name:
                continue
            device_type = type_lookup.get(str(device.get("deviceTypeIdentifier", "")))
            return {
                "source": "existing",
                "udid": str(device["udid"]),
                "name": str(device.get("name", "")),
                "device_type": str(device_type.get("name", device.get("name", "")) if device_type else device.get("name", "")),
                "runtime_id": runtime_id,
                "runtime_version": str(runtime.get("version", "")),
            }
    return None


def create_candidates(runtimes: list[dict[str, Any]], preferred: str) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    preferred_types: list[dict[str, Any]] = []
    fallback_types: list[dict[str, Any]] = []

    for runtime in runtimes:
        runtime_id = str(runtime["identifier"])
        runtime_version = str(runtime.get("version", ""))
        for device_type in runtime.get("supportedDeviceTypes", []):
            if not device_type.get("identifier"):
                continue
            candidate = {
                "source": "created",
                "name": "",
                "device_type": str(device_type.get("name", "")),
                "device_type_identifier": str(device_type["identifier"]),
                "runtime_id": runtime_id,
                "runtime_version": runtime_version,
            }
            if device_type.get("name") == preferred:
                preferred_types.append(candidate)
            elif is_iphone_type(device_type, ""):
                fallback_types.append(candidate)

    return preferred_types, fallback_types


def select_or_create_simulator(
    preferred: str, sim_name: str, maximum_runtime: str,
    requested_runtime: str | None = None,
) -> dict[str, str]:
    maximum = version_key(maximum_runtime)
    requested = version_key(requested_runtime) if requested_runtime else None
    if requested is not None and requested > maximum:
        raise RuntimeError(
            f"requested iOS simulator runtime {requested_runtime} exceeds active SDK {maximum_runtime}"
        )
    runtimes = ios_runtimes(
        load_json(["xcrun", "simctl", "list", "runtimes", "-j"])["runtimes"],
        maximum, requested,
    )
    if not runtimes:
        if requested_runtime:
            raise RuntimeError(
                f"Requested iOS simulator runtime {requested_runtime} is not installed and available"
            )
        raise RuntimeError(
            f"No available iOS simulator runtime at or below active SDK {maximum_runtime}"
        )

    devices = load_json(["xcrun", "simctl", "list", "devices", "available", "-j"])["devices"]
    existing = existing_simulator(runtimes, devices, sim_name)
    if existing:
        return existing

    preferred_types, fallback_types = create_candidates(runtimes, preferred)
    create = preferred_types
    if not create:
        create = fallback_types
    if not create:
        raise RuntimeError("No available iPhone simulator device type found")

    candidate = create[0]
    candidate["name"] = sim_name
    result = run(
        [
            "xcrun",
            "simctl",
            "create",
            sim_name,
            candidate["device_type_identifier"],
            candidate["runtime_id"],
        ]
    )
    candidate["udid"] = result.stdout.strip()
    return candidate


def write_env(path: str | None, values: dict[str, str]) -> None:
    if not path:
        return
    with Path(path).open("a", encoding="utf-8") as handle:
        for key, value in values.items():
            handle.write(f"{key}={value}\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Select and boot a CI iOS simulator")
    parser.add_argument(
        "--preferred-device",
        default=os.environ.get("BUTTONHEIST_CI_PREFERRED_SIMULATOR", DEFAULT_PREFERRED_DEVICE),
    )
    parser.add_argument("--sim-name", default=os.environ.get("BUTTONHEIST_CI_SIM_NAME"))
    parser.add_argument("--runtime")
    parser.add_argument("--github-env", default=os.environ.get("GITHUB_ENV"))
    parser.add_argument("--github-output", default=os.environ.get("GITHUB_OUTPUT"))
    parser.add_argument("--wait", action="store_true", help="Wait for the selected simulator to finish booting")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    sim_name = args.sim_name or default_sim_name(args.preferred_device)
    sdk_version = run(["xcrun", "--sdk", "iphonesimulator", "--show-sdk-version"]).stdout.strip()
    selected = select_or_create_simulator(
        args.preferred_device, sim_name, sdk_version, args.runtime,
    )
    try:
        boot = run(["xcrun", "simctl", "boot", selected["udid"]], check=False)
        if boot.returncode != 0:
            message = (boot.stderr or boot.stdout).strip()
            already_booted = "current state: booted" in message.lower() or "already booted" in message.lower()
            if message and not already_booted:
                print(f"simctl boot returned {boot.returncode}: {message}", file=sys.stderr)
        if args.wait:
            run(["xcrun", "simctl", "bootstatus", selected["udid"], "-b"])

        env = {
            "SIM_UDID": selected["udid"],
            "SIM_OS": selected["runtime_version"],
            "SIM_NAME": selected["name"],
            "SIM_DEVICE_TYPE": selected["device_type"],
            "SIM_SDK": sdk_version,
        }
        write_env(args.github_env, env)
        write_env(args.github_output, {key.lower(): value for key, value in env.items()})

        print(
            "Selected {device_type} ({name}) on iOS {runtime_version}: {udid} [{source}]".format(
                **selected
            )
        )
    except BaseException:
        run(["xcrun", "simctl", "shutdown", selected["udid"]], check=False)
        run(["xcrun", "simctl", "delete", selected["udid"]], check=False)
        raise


if __name__ == "__main__":
    main()
