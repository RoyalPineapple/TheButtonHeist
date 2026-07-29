#!/usr/bin/env python3
"""Repeat typed adversarial contracts against independently launched BH Demo sessions."""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import uuid
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlencode

from e2e_runtime import (
    DemoApp,
    boot_simulator,
    error_summary,
    install_app,
    run,
    write_json_report,
)

class ScenarioExpectation(str, Enum):
    COMMAND_SUCCEEDS = "command-succeeds"
    COMMAND_FAILS_WITH_DIAGNOSTIC = "command-fails-with-diagnostic"


class ScenarioClassification(str, Enum):
    DETERMINISTIC = "deterministic"
    STATISTICAL = "statistical"


class OutcomeStatus(str, Enum):
    PASSED = "passed"
    FAILED = "failed"
    NOT_RUN = "not-run"


@dataclass(frozen=True)
class Scenario:
    name: str
    route: str
    plan: str
    classification: ScenarioClassification
    expectation: ScenarioExpectation
    expected_diagnostic: str | None

    @classmethod
    def decode(cls, value: Any) -> Scenario:
        if not isinstance(value, dict):
            raise ValueError("catalog scenario must be an object")
        evidence = value.get("expectedEvidence")
        if not isinstance(evidence, list) or not evidence:
            raise ValueError("catalog scenario requires expected evidence")
        if any(
            not isinstance(row, dict)
            or row.get("kind") not in {"diagnostic", "element", "notification"}
            or not isinstance(row.get("label"), str)
            or not row["label"]
            or (row.get("value") is not None and not isinstance(row["value"], str))
            for row in evidence
        ):
            raise ValueError("catalog evidence requires a typed kind and label")
        expectation = ScenarioExpectation(required_string(value, "expectedOutcome"))
        diagnostics = [
            row["label"]
            for row in evidence
            if isinstance(row, dict)
            and row.get("kind") == "diagnostic"
            and isinstance(row.get("label"), str)
            and row["label"]
        ]
        if expectation is ScenarioExpectation.COMMAND_FAILS_WITH_DIAGNOSTIC:
            if len(diagnostics) != 1:
                raise ValueError("failing catalog scenarios require one diagnostic contract")
        elif diagnostics:
            raise ValueError("passing catalog scenarios cannot require diagnostic evidence")
        return cls(
            name=required_string(value, "name"),
            route=required_string(value, "route"),
            plan=required_string(value, "plan"),
            classification=ScenarioClassification(required_string(value, "classification")),
            expectation=expectation,
            expected_diagnostic=diagnostics[0] if diagnostics else None,
        )


def required_string(value: dict[str, Any], key: str) -> str:
    result = value.get(key)
    if not isinstance(result, str) or not result:
        raise ValueError(f"catalog scenario requires non-empty {key}")
    return result


def load_catalog(cli: Path) -> list[Scenario]:
    result = run([str(cli), "adversarial_catalog"], timeout=30, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"adversarial catalog command failed: {result.stderr or result.stdout}")
    decoded = json.loads(result.stdout)
    if not isinstance(decoded, list):
        raise ValueError("adversarial catalog command must return an array")
    scenarios = [Scenario.decode(value) for value in decoded]
    if len({scenario.name for scenario in scenarios}) != len(scenarios):
        raise ValueError("adversarial catalog scenario names must be unique")
    return scenarios


def observe_primary(
    scenario: Scenario,
    result: subprocess.CompletedProcess[str],
) -> dict[str, Any]:
    diagnostic_matched: bool | None = None
    if scenario.expectation is ScenarioExpectation.COMMAND_SUCCEEDS:
        matched = result.returncode == 0
    else:
        diagnostic = scenario.expected_diagnostic
        if diagnostic is None:
            raise ValueError("failing scenario is missing its admitted diagnostic")
        diagnostic_matched = diagnostic.casefold() in f"{result.stdout}\n{result.stderr}".casefold()
        matched = result.returncode != 0 and diagnostic_matched
    return {
        "status": (OutcomeStatus.PASSED if matched else OutcomeStatus.FAILED).value,
        "returncode": result.returncode,
        "diagnosticMatched": diagnostic_matched,
    }


def run_heist(
    cli: Path,
    app: DemoApp,
    plan: str,
) -> subprocess.CompletedProcess[str]:
    env = os.environ.copy()
    env.update({"BUTTONHEIST_TOKEN": app.token, "BUTTONHEIST_DRIVER_ID": app.token})
    result = run(
        [
            str(cli),
            "run_heist",
            "--plan",
            plan,
            "--device",
            app.device,
            "--token",
            app.token,
            "--connect-timeout",
            "10",
            "--format",
            "json",
            "--quiet",
        ],
        env=env,
        timeout=60,
        check=False,
    )
    if result.returncode == 124:
        raise TimeoutError(result.stderr)
    return result


def open_route(simulator: str, route: str) -> None:
    query = urlencode({"scenario": route, "route_id": str(uuid.uuid4())})
    run(["xcrun", "simctl", "openurl", simulator, f"buttonheist-demo://adversarial?{query}"], timeout=20)


def execute_sample(
    cli: Path,
    simulator: str,
    scenario: Scenario,
    iteration: int,
    *,
    app_factory: Callable[..., DemoApp] = DemoApp,
    route_opener: Callable[[str, str], None] = open_route,
    heist_runner: Callable[[Path, DemoApp, str], subprocess.CompletedProcess[str]] = run_heist,
) -> dict[str, Any]:
    app: DemoApp | None = None
    sample: dict[str, Any] = {
        "iteration": iteration,
        "primary": {"status": OutcomeStatus.NOT_RUN.value},
        "infrastructure": {"status": OutcomeStatus.NOT_RUN.value},
        "recovery": {"status": OutcomeStatus.NOT_RUN.value},
    }
    try:
        app = app_factory(
            simulator,
            token_prefix=f"adversarial-{scenario.name}-{iteration}",
        )
        app.launch()
        route_opener(simulator, scenario.route)
        sample["infrastructure"]["status"] = OutcomeStatus.PASSED.value
        sample["primary"] = observe_primary(scenario, heist_runner(cli, app, scenario.plan))
    except Exception as error:
        sample["infrastructure"] = {
            "status": OutcomeStatus.FAILED.value,
            "diagnostics": error_summary(error),
        }
    finally:
        if app is not None:
            try:
                app.terminate(require_stopped=True)
                sample["recovery"]["status"] = OutcomeStatus.PASSED.value
            except Exception as error:
                sample["recovery"] = {
                    "status": OutcomeStatus.FAILED.value,
                    "diagnostics": error_summary(error),
                }
    return sample


def execute_samples(
    requested: int,
    execute: Callable[[int], dict[str, Any]],
) -> list[dict[str, Any]]:
    return [execute(iteration) for iteration in range(1, requested + 1)]


def scenario_report(
    scenario: Scenario,
    requested: int,
    observations: list[dict[str, Any]],
) -> dict[str, Any]:
    primary = [
        sample["primary"]
        for sample in observations
        if sample["primary"]["status"] != OutcomeStatus.NOT_RUN.value
    ]
    return {
        "name": scenario.name,
        "requested": requested,
        "recorded": len(observations),
        "productFailed": sum(item["status"] == OutcomeStatus.FAILED.value for item in primary),
        "infrastructureFailed": sum(
            sample["infrastructure"]["status"] == OutcomeStatus.FAILED.value
            for sample in observations
        ),
        "recoveryFailed": sum(
            sample["recovery"]["status"] == OutcomeStatus.FAILED.value
            for sample in observations
        ),
        "samples": observations,
    }


def gate_summary(scenarios: list[dict[str, Any]]) -> dict[str, Any]:
    product_failed = sum(scenario["productFailed"] for scenario in scenarios)
    infrastructure_failed = sum(scenario["infrastructureFailed"] for scenario in scenarios)
    recovery_failed = sum(scenario["recoveryFailed"] for scenario in scenarios)
    failure_kinds = []
    if product_failed:
        failure_kinds.append("product-scenario-failure")
    if infrastructure_failed:
        failure_kinds.append("infrastructure-failure")
    if recovery_failed:
        failure_kinds.append("recovery-failure")
    return {
        "requested": sum(scenario["requested"] for scenario in scenarios),
        "recorded": sum(scenario["recorded"] for scenario in scenarios),
        "productFailed": product_failed,
        "infrastructureFailed": infrastructure_failed,
        "recoveryFailed": recovery_failed,
        "failureKinds": failure_kinds,
    }


def gate_failed(summary: dict[str, Any]) -> bool:
    return any(
        summary[key]
        for key in ("productFailed", "infrastructureFailed", "recoveryFailed")
    )


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the BH Demo adversarial lab nightly gate")
    parser.add_argument("--cli", default=os.environ.get("BUTTONHEIST_CLI", "ButtonHeistCLI/.build/debug/buttonheist"))
    parser.add_argument("--app", default=os.environ.get("BH_DEMO_APP"))
    parser.add_argument("--sim-udid", default=os.environ.get("SIM_UDID"))
    parser.add_argument("--repeat-count", type=int, default=int(os.environ.get("BUTTONHEIST_ADVERSARIAL_REPEAT_COUNT", "20")))
    parser.add_argument("--report", default=str(Path(os.environ.get("TMPDIR", "/tmp")) / "buttonheist-adversarial-nightly-report.json"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report_path = Path(args.report)
    report: dict[str, Any] = {
        "gate": "ios-demo-adversarial-lab-nightly",
        "status": "starting",
        "configuration": {"repeatCount": args.repeat_count},
        "scenarios": [],
        "summary": gate_summary([]),
    }
    write_json_report(report_path, report)

    try:
        if args.repeat_count < 1:
            raise RuntimeError("--repeat-count must be at least 1")
        if not args.app:
            raise RuntimeError("--app is required")
        if not args.sim_udid:
            raise RuntimeError("--sim-udid is required")
        cli = Path(args.cli).resolve()
        app_path = Path(args.app).resolve()
        if not cli.exists():
            raise RuntimeError(f"missing CLI: {cli}")
        if not (app_path / "BHDemo").exists():
            raise RuntimeError(f"missing BHDemo executable under {app_path}")

        scenarios = [
            scenario
            for scenario in load_catalog(cli)
            if scenario.classification is ScenarioClassification.STATISTICAL
        ]
        if not scenarios:
            raise RuntimeError("typed adversarial catalog has no statistical scenarios")
        boot_simulator(args.sim_udid)
        install_app(args.sim_udid, app_path)

        report["status"] = "running"

        for scenario in scenarios:
            observations = execute_samples(
                args.repeat_count,
                lambda iteration, selected=scenario: execute_sample(
                    cli,
                    args.sim_udid,
                    selected,
                    iteration,
                ),
            )
            report["scenarios"].append(scenario_report(scenario, args.repeat_count, observations))
            report["summary"] = gate_summary(report["scenarios"])
            write_json_report(report_path, report)

        failed = gate_failed(report["summary"])
        report["status"] = "failed" if failed else "passed"
        report["failureKind"] = ", ".join(report["summary"]["failureKinds"]) if failed else "none"
        write_json_report(report_path, report)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1 if failed else 0
    except Exception as error:
        report["status"] = "failed"
        report["failureKind"] = (
            "infrastructure-timeout"
            if isinstance(error, (TimeoutError, subprocess.TimeoutExpired))
            else "infrastructure-failure"
        )
        report["error"] = error_summary(error)
        write_json_report(report_path, report)
        print(f"Adversarial lab gate failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
