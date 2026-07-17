#!/usr/bin/env python3
"""End-to-end lifecycle gate for BHDemo and the Button Heist CLI.

This script exercises the production lifecycle cases that unit tests and the
happy-path demo smoke do not prove: session locks, reconnect after app relaunch,
and background/foreground behavior. It fails when a command hangs, returns
unstructured output, or crashes the host app.
"""

from __future__ import annotations

import argparse
import json
import os
import queue
import random
import re
import shutil
import subprocess
import sys
import threading
import time
import traceback
from pathlib import Path
from typing import Any

SCRIPT_DIR = Path(__file__).resolve().parent
if str(SCRIPT_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPT_DIR))

from e2e_runtime import (  # noqa: E402
    boot_simulator,
    free_port,
    install_app,
    launch_app,
    launch_environment,
    run,
    terminate_app,
    wait_port,
)

DEFAULT_REPORT = Path(os.environ.get("TMPDIR", "/tmp")) / "buttonheist-lifecycle-report.json"


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


def error_summary(error: BaseException) -> dict[str, Any]:
    return {
        "type": type(error).__name__,
        "message": str(error),
        "traceback": traceback.format_exception(type(error), error, error.__traceback__),
    }


def failure_kind(error: BaseException, *, scenario_started: bool) -> str:
    if scenario_started:
        return "product-lifecycle-failure"
    if isinstance(error, (TimeoutError, subprocess.TimeoutExpired)):
        return "infrastructure-timeout"
    return "infrastructure-setup-failure"


def parse_jsonish(text: str | None) -> Any | None:
    text = (text or "").strip()
    if not text:
        return None
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        pass
    for line in text.splitlines():
        line = line.strip()
        if not line.startswith("{"):
            continue
        try:
            return json.loads(line)
        except json.JSONDecodeError:
            continue
    return None


def contains_text(obj: Any | None, needle: str) -> bool:
    return needle in json.dumps(obj, sort_keys=True) if obj is not None else False


def choose_simulator(explicit: str | None) -> str:
    if explicit:
        return explicit
    if os.environ.get("BH_LIFECYCLE_SIM"):
        return os.environ["BH_LIFECYCLE_SIM"]
    data = json.loads(run(["xcrun", "simctl", "list", "-j", "devices", "available"]).stdout)
    candidates: list[dict[str, Any]] = []
    for runtime, devices in data["devices"].items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if device.get("isAvailable") and device.get("state") == "Booted":
                candidates.append(device)
    if not candidates:
        raise RuntimeError("no booted iOS simulator found; pass --sim-udid or boot one first")
    for preferred in ("buttonheist-e2e-accra", "iPhone 16 Pro", "iPhone 17"):
        for device in candidates:
            if device.get("name") == preferred:
                return str(device["udid"])
    return str(candidates[0]["udid"])


def prepare_app(sim: str, app_path: str | None, demo_zip: str | None, work_dir: Path) -> Path:
    if app_path:
        app = Path(app_path)
        if not (app / "BHDemo").exists():
            raise RuntimeError(f"demo app did not contain executable at {app / 'BHDemo'}")
    elif demo_zip:
        archive = Path(demo_zip)
        if not archive.exists():
            raise RuntimeError(f"missing demo zip: {archive}")
        extract_dir = work_dir / "demo-app"
        if extract_dir.exists():
            shutil.rmtree(extract_dir)
        extract_dir.mkdir(parents=True)
        run(["ditto", "-x", "-k", str(archive), str(extract_dir)])
        app = extract_dir / "BHDemo.app"
        if not (app / "BHDemo").exists():
            raise RuntimeError(f"demo zip did not contain executable at {app / 'BHDemo'}")
    else:
        raise RuntimeError("pass --app or --demo-zip")

    install_app(sim, app)
    return app


class DemoApp:
    def __init__(self, sim: str, port: int, token: str, *, server_timeout: float, app_id: str | None = None):
        self.sim = sim
        self.port = port
        self.token = token
        self.server_timeout = server_timeout
        self.app_id = app_id or token
        self.pid: int | None = None

    @property
    def device(self) -> str:
        return f"127.0.0.1:{self.port}"

    def launch(self) -> int | None:
        env = launch_environment(
            self.port,
            self.token,
            self.app_id,
            session_timeout=self.server_timeout,
        )
        failures: list[dict[str, Any]] = []
        for attempt in range(1, 4):
            if attempt > 1:
                terminate_app(self.sim)
                time.sleep(attempt)

            result = launch_app(self.sim, env)
            match = re.search(r":\s*(\d+)\s*$", result.stdout.strip())
            self.pid = int(match.group(1)) if match else None

            if result.returncode != 0:
                failures.append(
                    {
                        "attempt": attempt,
                        "returncode": result.returncode,
                        "stdout": result.stdout.strip(),
                        "stderr": result.stderr.strip(),
                    }
                )
                continue

            try:
                wait_port(self.port, open_expected=True, timeout=45)
                return self.pid
            except TimeoutError as error:
                failures.append(
                    {
                        "attempt": attempt,
                        "pid": self.pid,
                        "returncode": result.returncode,
                        "stdout": result.stdout.strip(),
                        "stderr": result.stderr.strip(),
                        "error": str(error),
                    }
                )

        raise TimeoutError(f"BHDemo did not open port {self.port} after launch attempts: {failures}")

    def terminate(self, *, require_stopped: bool = False) -> bool:
        result = terminate_app(self.sim)
        try:
            wait_port(self.port, open_expected=False, timeout=8)
            return True
        except TimeoutError:
            if require_stopped:
                raise AssertionError(
                    "terminate did not stop BHDemo or close the InsideJob port: "
                    + f"port={self.port} returncode={result.returncode} "
                    + f"stdout={result.stdout.strip()!r} stderr={result.stderr.strip()!r}"
                )
            return False


class PersistentJSONLines:
    def __init__(self, cli: Path, app: DemoApp, driver_id: str):
        self.cli = cli
        self.app = app
        self.driver_id = driver_id
        env = os.environ.copy()
        env.update(
            {
                "BUTTONHEIST_TOKEN": app.token,
                "BUTTONHEIST_DRIVER_ID": driver_id,
            }
        )
        self.proc = subprocess.Popen(
            [
                str(cli),
                "json_lines",
                "--device",
                app.device,
                "--token",
                app.token,
                "--idle-timeout",
                "0",
                "--format",
                "json",
            ],
            env=env,
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        self.stdout: queue.Queue[str] = queue.Queue()
        self.stderr: queue.Queue[str] = queue.Queue()
        self._threads = [
            threading.Thread(target=self._reader, args=(self.proc.stdout, self.stdout), daemon=True),
            threading.Thread(target=self._reader, args=(self.proc.stderr, self.stderr), daemon=True),
        ]
        for thread in self._threads:
            thread.start()

    @staticmethod
    def _reader(stream: Any, out: queue.Queue[str]) -> None:
        if stream is None:
            return
        for line in stream:
            out.put(line)

    def command(self, payload: dict[str, Any], *, timeout: float = 20) -> Any:
        if self.proc.poll() is not None:
            raise RuntimeError(f"JSON-lines process exited early: {self.proc.returncode}")
        if self.proc.stdin is None:
            raise RuntimeError("JSON-lines stdin is unavailable")
        self.proc.stdin.write(json.dumps(payload) + "\n")
        self.proc.stdin.flush()
        deadline = time.time() + timeout
        non_json: list[str] = []
        while time.time() < deadline:
            try:
                line = self.stdout.get(timeout=0.2)
            except queue.Empty:
                if self.proc.poll() is not None:
                    raise RuntimeError(f"JSON-lines process exited while waiting: {self.proc.returncode}")
                continue
            stripped = line.strip()
            if not stripped:
                continue
            try:
                return json.loads(stripped)
            except json.JSONDecodeError:
                non_json.append(stripped)
        stderr_lines: list[str] = []
        while not self.stderr.empty():
            stderr_lines.append(self.stderr.get_nowait().strip())
        raise TimeoutError(f"timed out waiting for JSON; stdout={non_json}; stderr={stderr_lines}")

    def close(self) -> None:
        if self.proc.poll() is not None:
            return
        try:
            if self.proc.stdin is not None:
                self.proc.stdin.close()
            self.proc.wait(timeout=3)
        except Exception:
            self.proc.terminate()
            try:
                self.proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                self.proc.kill()
                self.proc.wait(timeout=3)


def cli_once(cli: Path, app: DemoApp, driver_id: str, command: str, *, connect_timeout: float, timeout: float = 20) -> dict[str, Any]:
    env = os.environ.copy()
    env.update(
        {
            "BUTTONHEIST_TOKEN": app.token,
            "BUTTONHEIST_DRIVER_ID": driver_id,
        }
    )
    result = run(
        [
            str(cli),
            command,
            "--device",
            app.device,
            "--token",
            app.token,
            "--connect-timeout",
            str(connect_timeout),
            "--format",
            "json",
            "--quiet",
        ],
        env=env,
        timeout=timeout,
        check=False,
    )
    return {
        "returncode": result.returncode,
        "stdout": result.stdout,
        "stderr": result.stderr,
        "json": parse_jsonish(result.stdout) or parse_jsonish(result.stderr),
    }


def assert_success(response: Any, label: str) -> Any:
    if response is None:
        raise AssertionError(f"{label}: no JSON response")
    if isinstance(response, dict) and response.get("status") == "error":
        raise AssertionError(f"{label}: error response: {json.dumps(response, sort_keys=True)}")
    return response


def one_shot_success(result: dict[str, Any], label: str) -> Any:
    if result["returncode"] != 0:
        raise AssertionError(f"{label}: command failed: {result}")
    return assert_success(result["json"], label)


def wait_one_shot_success(
    cli: Path,
    app: DemoApp,
    driver_id: str,
    command: str,
    label: str,
    *,
    connect_timeout: float,
    timeout: float = 15,
) -> tuple[Any, list[dict[str, Any]]]:
    deadline = time.time() + timeout
    attempts: list[dict[str, Any]] = []
    while time.time() < deadline:
        result = cli_once(cli, app, driver_id, command, connect_timeout=connect_timeout, timeout=8)
        attempts.append(
            {
                "returncode": result["returncode"],
                "json": result["json"],
                "stderr": result["stderr"],
            }
        )
        if result["returncode"] == 0:
            try:
                return assert_success(result["json"], label), attempts
            except AssertionError:
                pass
        time.sleep(0.5)
    raise AssertionError(f"{label}: did not recover before timeout; attempts={attempts}")


def start_app(sim: str, label: str, timeout: float) -> tuple[DemoApp, int | None]:
    port = free_port()
    token = f"lifecycle-{label}-{random.randint(1000, 9999)}"
    app = DemoApp(sim, port, token, server_timeout=timeout)
    app.terminate()
    return app, app.launch()


def scenario_session_lock(cli: Path, sim: str, connect_timeout: float) -> dict[str, Any]:
    app, pid = start_app(sim, "lock", timeout=2.0)
    session = PersistentJSONLines(cli, app, "driver-a")
    try:
        first = session.command({"command": "get_interface"}, timeout=20)
        assert_success(first, "driver-a persistent initial interface")
        other_driver = cli_once(cli, app, "driver-b", "get_interface", connect_timeout=connect_timeout)
        if other_driver["returncode"] == 0 or not contains_text(other_driver["json"], "session.locked"):
            raise AssertionError(f"different driver should receive session.locked: {other_driver}")
        session.close()
        same_driver_drain = cli_once(cli, app, "driver-a", "get_interface", connect_timeout=connect_timeout)
        one_shot_success(same_driver_drain, "same driver during drain")
        draining_driver = cli_once(cli, app, "driver-b", "get_interface", connect_timeout=connect_timeout)
        if draining_driver["returncode"] == 0 or not contains_text(draining_driver["json"], "session.locked"):
            raise AssertionError(f"different driver should remain locked during drain: {draining_driver}")
        time.sleep(app.server_timeout + 1.25)
        released_driver = cli_once(cli, app, "driver-b", "get_interface", connect_timeout=connect_timeout)
        one_shot_success(released_driver, "different driver after lock timeout")
        return {
            "initial_pid": pid,
            "same_driver_drain_returncode": same_driver_drain["returncode"],
            "locked_code_seen": contains_text(other_driver["json"], "session.locked"),
            "drain_lock_seen": contains_text(draining_driver["json"], "session.locked"),
            "release_returncode": released_driver["returncode"],
        }
    finally:
        session.close()
        app.terminate()


def scenario_reconnect(cli: Path, sim: str) -> dict[str, Any]:
    app, pid1 = start_app(sim, "reconnect", timeout=5.0)
    session = PersistentJSONLines(cli, app, "reconnect-driver")
    try:
        before = session.command({"command": "get_interface"}, timeout=20)
        assert_success(before, "persistent session before app restart")
        app.terminate(require_stopped=True)
        time.sleep(1.0)
        pid2 = app.launch()
        if pid1 is None or pid2 is None:
            raise AssertionError(f"reconnect scenario could not prove process identity: before={pid1} after={pid2}")
        if pid1 == pid2:
            raise AssertionError(f"reconnect scenario did not relaunch BHDemo: pid stayed {pid1}")
        after = session.command({"command": "get_interface"}, timeout=30)
        assert_success(after, "persistent session after app restart")
        return {"pid_before": pid1, "pid_after": pid2, "pid_changed": pid1 != pid2}
    finally:
        session.close()
        app.terminate()


def background_app(sim: str) -> dict[str, Any]:
    result = run(["xcrun", "simctl", "launch", sim, "com.apple.Preferences"], check=False, timeout=20)
    if result.returncode == 0:
        return {"method": "settings", "stdout": result.stdout.strip()}
    fallback = run(["xcrun", "simctl", "ui", sim, "home"], check=False, timeout=20)
    return {
        "method": "home",
        "settings_error": result.stderr.strip(),
        "returncode": fallback.returncode,
        "stdout": fallback.stdout.strip(),
        "stderr": fallback.stderr.strip(),
    }


def scenario_background_foreground(cli: Path, sim: str, connect_timeout: float) -> dict[str, Any]:
    app, pid1 = start_app(sim, "background", timeout=3.0)
    try:
        foreground_before = cli_once(cli, app, "bg-driver", "get_interface", connect_timeout=connect_timeout)
        one_shot_success(foreground_before, "foreground get_interface before background")
        background_method = background_app(sim)
        time.sleep(1.0)
        while_background = cli_once(cli, app, "bg-driver", "get_interface", connect_timeout=connect_timeout, timeout=25)
        if while_background["json"] is None:
            raise AssertionError(f"background command did not return structured JSON: {while_background}")
        if (
            while_background["returncode"] == 0
            or not isinstance(while_background["json"], dict)
            or while_background["json"].get("status") != "error"
        ):
            raise AssertionError(f"background command should return a structured error: {while_background}")
        pid2 = app.launch()
        if pid1 is None or pid2 is None:
            raise AssertionError(f"background scenario could not prove process identity: before={pid1} after={pid2}")
        if pid1 != pid2:
            raise AssertionError(f"BHDemo relaunched during background/foreground scenario: before={pid1} after={pid2}")
        _, foreground_attempts = wait_one_shot_success(
            cli,
            app,
            "bg-driver",
            "get_interface",
            "foreground get_interface after background",
            connect_timeout=connect_timeout,
            timeout=15,
        )
        return {
            "pid_before": pid1,
            "pid_after_foreground": pid2,
            "same_pid_after_foreground": pid1 == pid2,
            "background_method": background_method,
            "background_returncode": while_background["returncode"],
            "background_structured": while_background["json"] is not None,
            "foreground_attempt_count": len(foreground_attempts),
            "foreground_transient_failures": [
                attempt for attempt in foreground_attempts if attempt["returncode"] != 0
            ],
        }
    finally:
        app.terminate()


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run BHDemo lifecycle release gate")
    parser.add_argument("--cli", default=os.environ.get("BUTTONHEIST_CLI", "ButtonHeistCLI/.build/debug/buttonheist"))
    parser.add_argument("--app", default=os.environ.get("BH_DEMO_APP"))
    parser.add_argument("--demo-zip", default=os.environ.get("BH_DEMO_ZIP"))
    parser.add_argument("--sim-udid", default=os.environ.get("BH_LIFECYCLE_SIM"))
    parser.add_argument("--report", default=str(DEFAULT_REPORT))
    parser.add_argument("--connect-timeout", type=float, default=float(os.environ.get("BH_CONNECT_TIMEOUT", "5")))
    parser.add_argument("--work-dir", default=str(Path(os.environ.get("TMPDIR", "/tmp")) / "buttonheist-lifecycle-gate"))
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    report_path = Path(args.report)
    cli = Path(args.cli).resolve()
    report = {
        "cli": str(cli),
        "version": "",
        "simulator": "",
        "demo_app": "",
        "status": "starting",
        "scenarios": {},
    }

    try:
        if not cli.exists():
            raise RuntimeError(f"missing CLI: {cli}")
        work_dir = Path(args.work_dir)
        work_dir.mkdir(parents=True, exist_ok=True)
        sim = choose_simulator(args.sim_udid)
        report["simulator"] = sim
        report["status"] = "booting-simulator"
        write_report(report_path, report)
        boot_simulator(sim)
        app = prepare_app(sim, args.app, args.demo_zip, work_dir)
        report["demo_app"] = str(app)
        version = run([str(cli), "--version"]).stdout.strip()
        report["version"] = version
        report["status"] = "running"
        write_report(report_path, report)

        scenarios = [
            ("session_lock", lambda: scenario_session_lock(cli, sim, args.connect_timeout)),
            ("reconnect", lambda: scenario_reconnect(cli, sim)),
            ("background_foreground", lambda: scenario_background_foreground(cli, sim, args.connect_timeout)),
        ]
        for name, run_scenario in scenarios:
            report["current_scenario"] = name
            write_report(report_path, report)
            try:
                report["scenarios"][name] = run_scenario()
            except Exception as exc:
                report["status"] = "failed"
                report["failureKind"] = failure_kind(exc, scenario_started=True)
                report["failed_scenario"] = name
                report["scenarios"][name] = {
                    "status": "failed",
                    "error": error_summary(exc),
                }
                write_report(report_path, report)
                raise
            write_report(report_path, report)

        report.pop("current_scenario", None)
        report["status"] = "passed"
        report["failureKind"] = "none"
        write_report(report_path, report)
        print(json.dumps(report, indent=2, sort_keys=True))
    except Exception as exc:
        report["status"] = "failed"
        report.setdefault(
            "failureKind",
            failure_kind(exc, scenario_started="current_scenario" in report),
        )
        report["error"] = error_summary(exc)
        write_report(report_path, report)
        raise


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 - script gate needs the concrete failure in CI logs.
        print(f"Lifecycle gate failed: {exc}", file=sys.stderr)
        raise
