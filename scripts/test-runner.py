#!/usr/bin/env python3
"""Canonical local and CI test runner."""

from __future__ import annotations

import argparse
import json
import math
import os
import runpy
import signal
import shutil
import subprocess
import sys
import tempfile
import time
from dataclasses import dataclass
from pathlib import Path
from typing import Sequence


ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT / "ButtonHeist.xcworkspace"
WRAPPER = ROOT / "scripts/run-with-heist-results.sh"
COLLECTOR = ROOT / "scripts/collect-ios-heist-results.sh"
SELECTOR = ROOT / "scripts/select-ios-ci-simulator.py"
IOS_DEVICE = "iPhone 16 Pro"
VERSION_KEY = runpy.run_path(str(SELECTOR))["version_key"]

# The only test-driving catalog: public name, scheme, platform, and CI behavior.
SUITES = {
    "TheScoreTests": {"platform": "macos"},
    "ButtonHeistTests": {"platform": "macos"},
    "TheInsideJobTests": {
        "platform": "ios",
        "disable_animations": True,
    },
    "TheInsideJobIntegrationTests": {
        "platform": "ios",
        "disable_animations": True,
    },
    "HostedBehaviorTests": {
        "platform": "ios",
        "serial": True,
        "disable_animations": True,
    },
    "MacFrameworkTests": {"platform": "macos"},
}

# Named focused projections onto the canonical suite catalog. Test identifiers
# use xcodebuild's Target[/Suite] spelling and are never interpreted by this
# runner.
FOCUSES = {
    "contract-actions": {
        "MacFrameworkTests": ("ThePlansTests",),
    },
    "contract-predicates": {
        "TheScoreTests": ("TheScoreTests/AccessibilityPredicateTests",),
    },
    "contract-results": {
        "TheScoreTests": ("TheScoreTests/HeistResultContractTests",),
    },
    "contract-wire": {
        "TheScoreTests": (
            "TheScoreTests/WireTypeRoundTripTests",
            "TheScoreTests/ClientMessageActionRoundTripTests",
            "TheScoreTests/ServerInfoTests",
            "TheScoreTests/AuthMessageTests",
        ),
        "TheInsideJobTests": ("TheInsideJobTests/WireConversionTests",),
    },
    "contract-targets": {
        "MacFrameworkTests": ("ThePlansTests",),
        "TheInsideJobTests": ("TheInsideJobTests/TheVaultResolutionTests",),
    },
}


@dataclass(frozen=True)
class PhaseResult:
    phase: str
    exit_code: int
    duration_seconds: float
    timed_out: bool = False


@dataclass(frozen=True)
class SourceState:
    commit: str
    clean: bool


def focus_runs(names: Sequence[str]) -> dict[str, tuple[str, ...]]:
    selected: dict[str, list[str]] = {}
    for name in names:
        for suite, identifiers in FOCUSES[name].items():
            tests = selected.setdefault(suite, [])
            tests.extend(identifier for identifier in identifiers if identifier not in tests)
    return {
        suite: tuple(selected[suite])
        for suite in SUITES
        if suite in selected
    }


def catalog_manifest() -> dict[str, object]:
    return {
        "suites": {
            name: dict(configuration)
            for name, configuration in SUITES.items()
        },
        "focuses": {
            name: {
                suite: list(identifiers)
                for suite, identifiers in selection.items()
            }
            for name, selection in FOCUSES.items()
        },
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
        "result_bundle": root / "result-bundles" / f"{name}.xcresult",
        "heist_results": root / "heist-results",
        "diagnostics": root / "diagnostics",
        "derived": derived / name,
        "record": root / "run.json",
    }


def run_phase(command: Sequence[str], phase: str, timeout_seconds: float) -> PhaseResult:
    started = time.monotonic()
    process = subprocess.Popen(command, start_new_session=True)
    try:
        exit_code = process.wait(timeout=timeout_seconds)
    except subprocess.TimeoutExpired:
        os.killpg(process.pid, signal.SIGTERM)
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            process.wait()
        return PhaseResult(
            phase=phase,
            exit_code=124,
            duration_seconds=time.monotonic() - started,
            timed_out=True,
        )
    return PhaseResult(
        phase=phase,
        exit_code=exit_code,
        duration_seconds=time.monotonic() - started,
    )


def source_state() -> SourceState:
    commit = subprocess.run(
        ["git", "rev-parse", "HEAD"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    ).stdout.strip()
    status = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        cwd=ROOT,
        check=True,
        text=True,
        capture_output=True,
    ).stdout
    return SourceState(commit=commit, clean=not status.strip())


def write_run_record(
    path: Path,
    *,
    name: str,
    mode: str,
    only_tests: Sequence[str],
    source: SourceState,
    result: PhaseResult,
    outcome: str,
    executed_test_count: int | None,
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "commit": source.commit,
                "sourceTreeClean": source.clean,
                "suite": name,
                "mode": mode,
                "onlyTests": list(only_tests),
                "phase": result.phase,
                "outcome": outcome,
                "exitCode": result.exit_code,
                "timedOut": result.timed_out,
                "durationSeconds": round(result.duration_seconds, 3),
                "executedTestCount": executed_test_count,
            },
            indent=2,
        ) + "\n",
        encoding="utf-8",
    )


def select_simulator(
    mode: str,
    suite: dict[str, object],
    requested_name: str | None,
    requested_runtime: str | None = None,
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
        runtime = requested_runtime or os.environ.get("BUTTONHEIST_TEST_SIMULATOR_RUNTIME")
        if runtime:
            command.extend(("--runtime", runtime))
        if mode in ("run", "test-without-building"):
            command.append("--wait")
        subprocess.run(command, check=True)
        values = dict(
            line.split("=", 1)
            for line in output.read_text(encoding="utf-8").splitlines()
        )
    simulator = {
        "udid": values["sim_udid"],
        "name": values["sim_name"],
        "device": values["sim_device_type"],
        "os": values["sim_os"],
    }
    sdk_version = values["sim_sdk"]
    if VERSION_KEY(simulator["os"]) > VERSION_KEY(sdk_version):
        cleanup_failed = not delete_simulator(simulator)
        raise RuntimeError(
            f"selected iOS simulator runtime {simulator['os']} exceeds active SDK {sdk_version}"
            + ("; cleanup failed to delete selected simulator" if cleanup_failed else "")
        )
    return simulator


def test_command(
    mode: str,
    name: str,
    suite: dict[str, object],
    paths: dict[str, Path],
    simulator: dict[str, str] | None,
    selection: str,
    only_tests: Sequence[str] = (),
) -> list[str]:
    if suite["platform"] == "ios":
        if simulator is None:
            raise ValueError("iOS suites require a simulator")
        test_destination = f"platform=iOS Simulator,id={simulator['udid']},arch=arm64"
    else:
        test_destination = "platform=macOS"
    only_testing = [f"-only-testing:{identifier}" for identifier in only_tests]
    disable_animations = suite.get("disable_animations", False)
    test_host_settings = (
        ["BUTTONHEIST_TEST_DISABLE_ANIMATIONS=1"]
        if disable_animations
        else []
    )
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
            *test_host_settings,
            *only_testing,
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
            str(paths["result_bundle"]),
            "--",
            "-destination",
            test_destination,
            "-derivedDataPath",
            str(paths["derived"]),
            *test_host_settings,
            *test_options,
            *only_testing,
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
            str(paths["result_bundle"]),
            *test_host_settings,
            *test_options,
            *only_testing,
        ]
    wrapper = [str(WRAPPER)]
    if suite["platform"] == "ios":
        wrapper.append("--ios-sandbox")
    else:
        wrapper.extend(("--dir", str(paths["heist_results"])))
    return wrapper + [
        "--mode",
        os.environ.get("BUTTONHEIST_RESULTS_MODE", "failures"),
        "--",
        *command,
    ]


def publish(paths: dict[str, Path], simulator: dict[str, str] | None) -> None:
    values = {
        "BUTTONHEIST_TEST_RESULT_BUNDLE": str(paths["result_bundle"]),
        "BUTTONHEIST_TEST_RESULTS_DIR": str(paths["heist_results"]),
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
    paths["heist_results"].mkdir(parents=True, exist_ok=True)
    if suite["platform"] != "ios":
        return
    simulator = os.environ.get("SIM_UDID")
    if simulator:
        subprocess.run([str(COLLECTOR), simulator, str(paths["heist_results"])], check=False)
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


def clear_simulator_results(simulator: dict[str, str] | None) -> None:
    if simulator is None:
        return
    containers = (
        Path.home() / "Library/Developer/CoreSimulator/Devices"
        / simulator["udid"] / "data/Containers/Data"
    )
    if not containers.exists():
        return
    for directory in containers.glob("**/buttonheist-results"):
        shutil.rmtree(directory)


def delete_simulator(simulator: dict[str, str]) -> bool:
    subprocess.run(
        ["xcrun", "simctl", "shutdown", simulator["udid"]],
        check=False,
        text=True,
        capture_output=True,
    )
    deletion = subprocess.run(
        ["xcrun", "simctl", "delete", simulator["udid"]],
        check=False,
        text=True,
        capture_output=True,
    )
    if deletion.returncode == 0:
        return True
    detail = (deletion.stderr or deletion.stdout).strip()
    suffix = f": {detail}" if detail else ""
    print(
        f"Error: could not delete simulator {simulator['name']} "
        f"({simulator['udid']}){suffix}",
        file=sys.stderr,
    )
    return False


def simulators_named(name: str) -> list[dict[str, str]]:
    completed = subprocess.run(
        ["xcrun", "simctl", "list", "devices", "--json"],
        check=True,
        text=True,
        capture_output=True,
    )
    devices = json.loads(completed.stdout).get("devices", {})
    return [
        {"udid": str(device["udid"]), "name": name}
        for runtime_devices in devices.values()
        for device in runtime_devices
        if device.get("name") == name
    ]


def delete_simulators(simulators: Sequence[dict[str, str]]) -> bool:
    deleted = True
    seen: set[str] = set()
    for simulator in simulators:
        if simulator["udid"] in seen:
            continue
        seen.add(simulator["udid"])
        deleted = delete_simulator(simulator) and deleted
    return deleted


def require_executed_tests(result_bundle: Path) -> int:
    summary = subprocess.run(
        [
            "xcrun",
            "xcresulttool",
            "get",
            "test-results",
            "summary",
            "--path",
            str(result_bundle),
            "--format",
            "json",
        ],
        check=True,
        text=True,
        capture_output=True,
    )
    count = int(json.loads(summary.stdout)["totalTestCount"])
    if count == 0:
        raise RuntimeError(f"Test result bundle executed zero tests: {result_bundle}")
    return count


def execute(
    args: argparse.Namespace,
    name: str,
    only_tests: Sequence[str] = (),
    selected_simulators: list[dict[str, str]] | None = None,
) -> int:
    suite = SUITES[name]
    paths = suite_paths(name)
    if args.mode == "collect":
        publish(paths, None)
        collect(suite, paths, include_diagnostics=True)
        return 0
    simulator = select_simulator(args.mode, suite, args.simulator_name, args.simulator_runtime)
    if simulator is not None and selected_simulators is not None:
        selected_simulators.append(simulator)
    publish(paths, simulator)

    for key in ("result_bundle", "heist_results", "diagnostics"):
        if paths[key].exists():
            shutil.rmtree(paths[key])
    paths["record"].unlink(missing_ok=True)
    paths["result_bundle"].parent.mkdir(parents=True, exist_ok=True)
    paths["heist_results"].mkdir(parents=True, exist_ok=True)
    if args.mode in ("run", "test-without-building"):
        clear_simulator_results(simulator)

    command = test_command(
        args.mode,
        name,
        suite,
        paths,
        simulator,
        args.selection,
        only_tests,
    )
    source = source_state()
    phase_name = "build" if args.mode == "build-for-testing" else "tests"
    phase = run_phase(command, f"{name}:{phase_name}", args.timeout_seconds)
    if phase.timed_out:
        collect(suite, paths, include_diagnostics=True)
        write_run_record(
            paths["record"],
            name=name,
            mode=args.mode,
            only_tests=only_tests,
            source=source,
            result=phase,
            outcome="timeout",
            executed_test_count=None,
        )
        print(
            f"Error: {phase.phase} timed out after {phase.duration_seconds:.1f}s",
            file=sys.stderr,
        )
        return phase.exit_code
    if args.mode in ("run", "test-without-building"):
        collect(suite, paths, include_diagnostics=phase.exit_code != 0)
        try:
            test_count = require_executed_tests(paths["result_bundle"])
        except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
            write_run_record(
                paths["record"],
                name=name,
                mode=args.mode,
                only_tests=only_tests,
                source=source,
                result=phase,
                outcome="inconclusive",
                executed_test_count=None,
            )
            print(f"Error: {error}", file=sys.stderr)
            return 2
    else:
        test_count = None
    write_run_record(
        paths["record"],
        name=name,
        mode=args.mode,
        only_tests=only_tests,
        source=source,
        result=phase,
        outcome="passed" if phase.exit_code == 0 else "failed",
        executed_test_count=test_count,
    )
    return phase.exit_code


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "mode",
        choices=(
            "run",
            "build-for-testing",
            "test-without-building",
            "collect",
            "cleanup",
            "catalog",
        ),
    )
    parser.add_argument("suites", nargs="*", choices=tuple(SUITES))
    parser.add_argument("--focus", action="append", choices=tuple(FOCUSES), default=[])
    parser.add_argument("--selection", choices=("selective", "full"), default="selective")
    parser.add_argument("--simulator-name")
    parser.add_argument("--simulator-runtime")
    parser.add_argument("--retain-simulator", action="store_true")
    parser.add_argument("--timeout-seconds", type=float, default=1_800)
    parser.add_argument("--install-dependencies", action="store_true")
    args = parser.parse_args(argv)
    if args.mode == "catalog":
        if args.suites or args.focus:
            raise ValueError("catalog does not accept suites or focuses")
        return args
    if args.mode == "cleanup":
        if args.suites or args.focus:
            raise ValueError("cleanup does not accept suites or focuses")
        if args.retain_simulator:
            raise ValueError("cleanup does not accept --retain-simulator")
        return args
    if bool(args.suites) == bool(args.focus):
        raise ValueError("select suites or focuses, but not both")
    simulator_modes = ("run", "build-for-testing", "test-without-building")
    if args.retain_simulator and args.mode not in simulator_modes:
        raise ValueError(
            "--retain-simulator requires a simulator-using test mode"
        )
    selected_suites = args.suites or tuple(focus_runs(args.focus))
    if args.retain_simulator and not any(
        SUITES[name]["platform"] == "ios"
        for name in selected_suites
    ):
        raise ValueError("--retain-simulator requires an iOS suite")
    if not math.isfinite(args.timeout_seconds) or args.timeout_seconds <= 0:
        raise ValueError("--timeout-seconds must be finite and positive")
    return args


def main(argv: Sequence[str] | None = None) -> int:
    args = parse_args(argv)
    if args.mode == "catalog":
        print(json.dumps(catalog_manifest(), indent=2, sort_keys=False))
        return 0
    if args.mode == "cleanup":
        name = (
            args.simulator_name
            or os.environ.get("BUTTONHEIST_TEST_SIMULATOR_NAME")
            or os.environ.get("SIM_NAME")
        )
        if not name:
            raise ValueError(
                "cleanup requires --simulator-name or a simulator name environment value"
            )
        return 0 if delete_simulators(simulators_named(name)) else 3
    if args.mode != "run" and args.install_dependencies:
        raise ValueError("--install-dependencies requires run mode")
    if args.install_dependencies:
        subprocess.run(["tuist", "install"], check=True)
    runs = focus_runs(args.focus) if args.focus else {
        name: () for name in args.suites
    }
    selected_simulators: list[dict[str, str]] = []
    status = 0
    cleanup_succeeded = True
    try:
        for name, only_tests in runs.items():
            status = execute(args, name, only_tests, selected_simulators)
            if status:
                break
    finally:
        if not args.retain_simulator:
            cleanup_succeeded = delete_simulators(selected_simulators)
    if status == 0 and not cleanup_succeeded:
        return 3
    return status


if __name__ == "__main__":
    raise SystemExit(main())
