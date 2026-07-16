#!/usr/bin/env python3
"""Canonical local and CI test runner."""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT / "ButtonHeist.xcworkspace"
WRAPPER = ROOT / "scripts/run-with-heist-receipts.sh"
COLLECTOR = ROOT / "scripts/collect-ios-heist-receipts.sh"
SELECTOR = ROOT / "scripts/select-ios-ci-simulator.py"
IOS_DEVICE = "iPhone 16 Pro"

# The only test-driving catalog: public name, scheme, platform, and CI behavior.
SUITES = {
    "TheScoreTests": {"platform": "macos"},
    "ButtonHeistTests": {"platform": "macos"},
    "TheInsideJobTests": {"platform": "ios"},
    "TheInsideJobIntegrationTests": {"platform": "ios"},
    "HostedBehaviorTests": {
        "platform": "ios",
        "serial": True,
    },
    "MacFrameworkTests": {"platform": "macos"},
}


def suite_paths(name: str) -> dict[str, Path]:
    artifacts = Path(os.environ.get(
        "BUTTONHEIST_TEST_ARTIFACTS_DIR", ROOT / ".build/test-artifacts"
    )).expanduser().resolve()
    derived = Path(os.environ.get(
        "BUTTONHEIST_TEST_DERIVED_DATA_ROOT", ROOT / ".build/test-derived-data"
    )).expanduser().resolve()
    root = artifacts / name
    return {
        "result": root / "results" / f"{name}.xcresult",
        "receipts": root / "receipts",
        "diagnostics": root / "diagnostics",
        "derived": derived / name,
    }


def select_simulator(
    mode: str,
    suite: dict[str, object],
    requested_name: str | None,
) -> dict[str, str] | None:
    if suite["platform"] != "ios":
        return None
    name = requested_name or os.environ.get("BUTTONHEIST_TEST_SIMULATOR_NAME")
    with tempfile.TemporaryDirectory() as directory:
        output = Path(directory) / "simulator.env"
        command = [
            sys.executable,
            str(SELECTOR),
            "--preferred-device",
            IOS_DEVICE,
            "--github-output",
            str(output),
        ]
        if name:
            command.extend(("--sim-name", name))
        if mode in ("run", "test-without-building"):
            command.append("--wait")
        subprocess.run(command, check=True)
        values = dict(
            line.split("=", 1)
            for line in output.read_text(encoding="utf-8").splitlines()
        )
    return {
        "udid": values["sim_udid"],
        "name": values["sim_name"],
        "device": values["sim_device_type"],
        "os": values["sim_os"],
    }


def test_command(
    mode: str,
    name: str,
    suite: dict[str, object],
    paths: dict[str, Path],
    simulator: dict[str, str] | None,
    selection: str,
) -> list[str]:
    if suite["platform"] == "ios":
        if simulator is None:
            raise ValueError("iOS suites require a simulator")
        test_destination = f"platform=iOS Simulator,id={simulator['udid']},arch=arm64"
    else:
        test_destination = "platform=macOS"
    if mode == "build-for-testing":
        return [
            "xcodebuild",
            mode,
            "-workspace",
            str(WORKSPACE),
            "-scheme",
            name,
            "-destination",
            test_destination,
            "-derivedDataPath",
            str(paths["derived"]),
        ]

    test_options = ["-collect-test-diagnostics", "never"]
    if suite.get("serial"):
        test_options.extend(("-parallel-testing-enabled", "NO"))
    if mode == "run":
        command = [
            "tuist",
            "test",
            name,
            "--selective-testing" if selection == "selective" else "--no-selective-testing",
            "--result-bundle-path",
            str(paths["result"]),
            "--",
            "-destination",
            test_destination,
            "-derivedDataPath",
            str(paths["derived"]),
            *test_options,
        ]
    else:
        command = [
            "xcodebuild",
            mode,
            "-workspace",
            str(WORKSPACE),
            "-scheme",
            name,
            "-destination",
            test_destination,
            "-derivedDataPath",
            str(paths["derived"]),
            "-resultBundlePath",
            str(paths["result"]),
            *test_options,
        ]
    wrapper = [str(WRAPPER)]
    if suite["platform"] == "ios":
        wrapper.append("--ios-sandbox")
    else:
        wrapper.extend(("--dir", str(paths["receipts"])))
    return wrapper + [
        "--mode",
        os.environ.get("BUTTONHEIST_RECEIPTS_MODE", "failures"),
        "--",
        *command,
    ]


def publish(paths: dict[str, Path], simulator: dict[str, str] | None) -> None:
    values = {
        "BUTTONHEIST_TEST_RESULT_BUNDLE": str(paths["result"]),
        "BUTTONHEIST_TEST_RECEIPTS_DIR": str(paths["receipts"]),
        "BUTTONHEIST_TEST_DIAGNOSTICS_DIR": str(paths["diagnostics"]),
        "BUTTONHEIST_TEST_DERIVED_DATA": str(paths["derived"]),
    }
    if simulator:
        values.update(
            {
                "SIM_UDID": simulator["udid"],
                "SIM_NAME": simulator["name"],
                "SIM_DEVICE_TYPE": simulator["device"],
                "SIM_OS": simulator["os"],
            }
        )
    os.environ.update(values)
    if os.environ.get("GITHUB_ENV"):
        with Path(os.environ["GITHUB_ENV"]).open("a", encoding="utf-8") as output:
            output.writelines(f"{key}={value}\n" for key, value in values.items())


def collect(
    suite: dict[str, object],
    paths: dict[str, Path],
    include_diagnostics: bool = False,
) -> None:
    paths["receipts"].mkdir(parents=True, exist_ok=True)
    if suite["platform"] != "ios":
        return
    simulator = os.environ.get("SIM_UDID")
    if simulator:
        subprocess.run([str(COLLECTOR), simulator, str(paths["receipts"])], check=False)
    if not include_diagnostics:
        return
    paths["diagnostics"].mkdir(parents=True, exist_ok=True)
    with (paths["diagnostics"] / "simulators.txt").open("w", encoding="utf-8") as output:
        subprocess.run(["xcrun", "simctl", "list", "devices"], stdout=output, check=False)
    if simulator:
        with (paths["diagnostics"] / "simulator.log").open("w", encoding="utf-8") as output:
            subprocess.run(
                ["xcrun", "simctl", "spawn", simulator, "log", "show", "--style", "compact", "--last", "30m"],
                stdout=output,
                stderr=subprocess.STDOUT,
                check=False,
            )


def clear_simulator_receipts(simulator: dict[str, str] | None) -> None:
    if simulator is None:
        return
    containers = (
        Path.home() / "Library/Developer/CoreSimulator/Devices"
        / simulator["udid"] / "data/Containers/Data"
    )
    if not containers.exists():
        return
    for directory in containers.glob("**/buttonheist-receipts"):
        shutil.rmtree(directory)


def execute(args: argparse.Namespace, name: str) -> int:
    suite = SUITES[name]
    if args.mode in ("build-for-testing", "test-without-building") and suite["platform"] != "ios":
        raise ValueError(f"{name} does not support {args.mode}")
    paths = suite_paths(name)
    if args.mode == "collect":
        publish(paths, None)
        collect(suite, paths, include_diagnostics=True)
        return 0
    simulator = select_simulator(args.mode, suite, args.simulator_name)
    publish(paths, simulator)

    for key in ("result", "receipts", "diagnostics"):
        if paths[key].exists():
            shutil.rmtree(paths[key])
    paths["result"].parent.mkdir(parents=True, exist_ok=True)
    paths["receipts"].mkdir(parents=True, exist_ok=True)
    if args.mode in ("run", "test-without-building"):
        clear_simulator_receipts(simulator)

    command = test_command(args.mode, name, suite, paths, simulator, args.selection)
    status = subprocess.run(command, check=False).returncode
    if status:
        collect(suite, paths, include_diagnostics=True)
        return status
    if args.mode in ("run", "test-without-building"):
        collect(suite, paths)
    return 0


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode",
        choices=("run", "build-for-testing", "test-without-building", "collect"),
    )
    parser.add_argument("suites", nargs="+", choices=tuple(SUITES))
    parser.add_argument("--selection", choices=("selective", "full"), default="selective")
    parser.add_argument("--simulator-name")
    parser.add_argument("--install-dependencies", action="store_true")
    return parser.parse_args(argv)


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.mode != "run" and args.install_dependencies:
        raise ValueError("--install-dependencies requires run mode")
    if args.install_dependencies:
        subprocess.run(["tuist", "install"], check=True)
    for name in args.suites:
        status = execute(args, name)
        if status:
            return status
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
