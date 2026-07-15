#!/usr/bin/env python3
"""Nightly adversarial lab gate for BH Demo.

This is intentionally separate from PR correctness tests. It repeats hostile
demo flows through the public CLI and records fresh receipts as CI artifacts.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import socket
import subprocess
import sys
import time
import traceback
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any


BUNDLE_ID = "com.buttonheist.testapp"
CEILING_HIT_TOLERANCE_MS = 25


class ScenarioExpectation(str, Enum):
    COMMAND_SUCCEEDS = "command-succeeds"
    COMMAND_FAILS_WITH_DIAGNOSTIC = "command-fails-with-diagnostic"


class CeilingPolicy(str, Enum):
    RECORD = "record"
    FAIL = "fail"

    def __str__(self) -> str:
        return self.value


@dataclass(frozen=True)
class Scenario:
    name: str
    plan: str
    repeat_count: int
    expectation: ScenarioExpectation
    expected_diagnostic_text: str | None = None

    def __post_init__(self) -> None:
        if self.repeat_count < 1:
            raise ValueError("scenario repeat count must be at least 1")
        if self.expectation is ScenarioExpectation.COMMAND_FAILS_WITH_DIAGNOSTIC:
            if not self.expected_diagnostic_text:
                raise ValueError("failing scenarios require expected diagnostic text")
        elif self.expected_diagnostic_text is not None:
            raise ValueError("passing scenarios cannot expect diagnostic text")


@dataclass(frozen=True)
class IterationObservation:
    iteration: int
    passed: bool
    returncode: int
    diagnostic_matched: bool | None
    cli_wall_duration_ms: int
    receipt_timing_samples: dict[str, list[int]]
    unexpected_ceiling_hits: list[dict[str, Any]]
    response: Any | None
    stdout: str
    stderr: str

    @property
    def requires_app_recovery(self) -> bool:
        return self.returncode != 0


def percentile(values: list[int], pct: float) -> int:
    if not values:
        return 0
    ordered = sorted(values)
    index = min(len(ordered) - 1, int(round((pct / 100) * (len(ordered) - 1))))
    return ordered[index]


def stats(values: list[int]) -> dict[str, int]:
    return {
        "min": min(values) if values else 0,
        "p50": percentile(values, 50),
        "p95": percentile(values, 95),
        "p99": percentile(values, 99),
        "max": max(values) if values else 0,
        "total": sum(values),
    }


def run(cmd: list[str], *, env: dict[str, str] | None = None, timeout: float = 60, check: bool = True) -> subprocess.CompletedProcess[str]:
    result = subprocess.run(cmd, env=env, timeout=timeout, text=True, capture_output=True)
    if check and result.returncode != 0:
        raise RuntimeError(
            f"command failed ({result.returncode}): {' '.join(cmd)}\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
    return result


def parse_jsonish(text: str) -> Any | None:
    text = text.strip()
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


def sample_stats(values: list[int]) -> dict[str, int]:
    return {"count": len(values), **stats(values)}


def ms(value: Any, *, scale: int = 1) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(value):
        return max(0, int(round(value * scale)))
    return None


def empty_receipt_timing_samples() -> dict[str, list[int]]:
    return {}


def add_sample(samples: dict[str, list[int]], bucket: str, value: int | None) -> None:
    if value is not None:
        samples.setdefault(bucket, []).append(value)


def merge_receipt_timing_samples(target: dict[str, list[int]], source: dict[str, list[int]]) -> None:
    for bucket, values in source.items():
        target.setdefault(bucket, []).extend(values)


def summarize_receipt_timing(samples: dict[str, list[int]]) -> dict[str, dict[str, int]]:
    return {bucket: sample_stats(values) for bucket, values in sorted(samples.items()) if values}


def report_metrics_object(response: Any) -> dict[str, Any] | None:
    if not isinstance(response, dict):
        return None
    report = response.get("report")
    if not isinstance(report, dict):
        return None
    metrics = report.get("metrics")
    return metrics if isinstance(metrics, dict) else None


def add_receipt_metric_samples(samples: dict[str, list[int]], metrics: dict[str, Any]) -> None:
    sample_rows = metrics.get("samples")
    if not isinstance(sample_rows, list):
        return
    for row in sample_rows:
        if not isinstance(row, dict):
            continue
        name = row.get("name")
        if not isinstance(name, str) or not name:
            continue
        add_sample(samples, name, ms(row.get("valueMs")))


def ceiling_hit(
    *,
    path: Any,
    kind: Any,
    status: Any,
    source: str,
    budget_ms: int | None,
    elapsed_ms: int | None,
) -> dict[str, Any] | None:
    if budget_ms is None or elapsed_ms is None:
        return None
    threshold_ms = max(0, budget_ms - CEILING_HIT_TOLERANCE_MS)
    if elapsed_ms < threshold_ms:
        return None
    return {
        "path": path,
        "kind": kind,
        "status": status,
        "source": source,
        "budgetMs": budget_ms,
        "elapsedMs": elapsed_ms,
    }


def receipt_ceiling_hits(metrics: dict[str, Any]) -> list[dict[str, Any]]:
    ceiling_rows = metrics.get("ceilings")
    if not isinstance(ceiling_rows, list):
        return []
    hits: list[dict[str, Any]] = []
    for row in ceiling_rows:
        if not isinstance(row, dict):
            continue
        source = row.get("source")
        if not isinstance(source, str) or not source:
            continue
        hit = ceiling_hit(
            path=row.get("path"),
            kind=row.get("kind"),
            status=row.get("status"),
            source=source,
            budget_ms=ms(row.get("budgetMs")),
            elapsed_ms=ms(row.get("elapsedMs")),
        )
        if hit is not None:
            hits.append(hit)
    return hits


def receipt_metrics(response: Any) -> tuple[dict[str, Any], list[dict[str, Any]]]:
    samples = empty_receipt_timing_samples()
    ceiling_hits: list[dict[str, Any]] = []
    metrics = report_metrics_object(response)
    if metrics is None:
        return samples, ceiling_hits
    add_receipt_metric_samples(samples, metrics)
    ceiling_hits.extend(receipt_ceiling_hits(metrics))
    return samples, ceiling_hits


def with_iteration(items: list[dict[str, Any]], iteration: int) -> list[dict[str, Any]]:
    return [{"iteration": iteration, **item} for item in items]


def observe_iteration(
    scenario: Scenario,
    iteration: int,
    result: subprocess.CompletedProcess[str],
    duration_ms: int,
) -> IterationObservation:
    parsed_stdout = parse_jsonish(result.stdout)
    parsed = parsed_stdout if parsed_stdout is not None else parse_jsonish(result.stderr)
    timing_samples, ceiling_hits = receipt_metrics(parsed)
    diagnostic_matched: bool | None = None
    if scenario.expectation is ScenarioExpectation.COMMAND_SUCCEEDS:
        passed = result.returncode == 0
    else:
        expected_text = scenario.expected_diagnostic_text
        if expected_text is None:
            raise ValueError("failing scenarios require expected diagnostic text")
        diagnostic_matched = expected_text.casefold() in f"{result.stdout}\n{result.stderr}".casefold()
        passed = result.returncode != 0 and diagnostic_matched
    return IterationObservation(
        iteration=iteration,
        passed=passed,
        returncode=result.returncode,
        diagnostic_matched=diagnostic_matched,
        cli_wall_duration_ms=duration_ms,
        receipt_timing_samples=timing_samples,
        unexpected_ceiling_hits=ceiling_hits,
        response=parsed,
        stdout=result.stdout,
        stderr=result.stderr,
    )


def iteration_report(observation: IterationObservation) -> dict[str, Any]:
    report = {
        "iteration": observation.iteration,
        "passed": observation.passed,
        "returncode": observation.returncode,
        "diagnosticMatched": observation.diagnostic_matched,
        "requiresAppRecovery": observation.requires_app_recovery,
        "cliWallDurationMs": observation.cli_wall_duration_ms,
        "receiptTimingMs": summarize_receipt_timing(observation.receipt_timing_samples),
        "unexpectedCeilingHits": observation.unexpected_ceiling_hits,
    }
    if not observation.passed or observation.unexpected_ceiling_hits:
        report["diagnostics"] = {
            "response": observation.response,
            "stdout": observation.stdout,
            "stderr": observation.stderr,
        }
    return report


def scenario_report(scenario: Scenario, observations: list[IterationObservation]) -> dict[str, Any]:
    timing_samples = empty_receipt_timing_samples()
    ceiling_hits: list[dict[str, Any]] = []
    for observation in observations:
        merge_receipt_timing_samples(timing_samples, observation.receipt_timing_samples)
        ceiling_hits.extend(with_iteration(observation.unexpected_ceiling_hits, observation.iteration))
    durations = [observation.cli_wall_duration_ms for observation in observations]
    passed = sum(observation.passed for observation in observations)
    return {
        "name": scenario.name,
        "expectation": scenario.expectation.value,
        "expectedDiagnosticText": scenario.expected_diagnostic_text,
        "repeatCount": scenario.repeat_count,
        "attempted": len(observations),
        "passed": passed,
        "failed": len(observations) - passed,
        "cliWallTimingMs": sample_stats(durations),
        "receiptTimingMs": summarize_receipt_timing(timing_samples),
        "unexpectedCeilingHits": ceiling_hits,
        "iterations": [iteration_report(observation) for observation in observations],
    }


def gate_summary(scenarios: list[dict[str, Any]], ceiling_policy: CeilingPolicy) -> dict[str, Any]:
    ceiling_hit_count = sum(len(scenario["unexpectedCeilingHits"]) for scenario in scenarios)
    failed_count = sum(scenario["failed"] for scenario in scenarios)
    failure_kinds: list[str] = []
    if failed_count > 0:
        failure_kinds.append("product-scenario-failure")
    if ceiling_policy is CeilingPolicy.FAIL and ceiling_hit_count > 0:
        failure_kinds.append("product-ceiling-failure")
    return {
        "attempted": sum(scenario["attempted"] for scenario in scenarios),
        "passed": sum(scenario["passed"] for scenario in scenarios),
        "failed": failed_count,
        "unexpectedCeilingHits": ceiling_hit_count,
        "ceilingPolicyViolated": ceiling_policy is CeilingPolicy.FAIL and ceiling_hit_count > 0,
        "failureKinds": failure_kinds,
    }


def gate_failed(summary: dict[str, Any]) -> bool:
    return summary["failed"] > 0 or summary["ceilingPolicyViolated"]


def free_port() -> int:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        return int(sock.getsockname()[1])


def wait_port(port: int, timeout: float = 30) -> None:
    deadline = time.time() + timeout
    last_error: OSError | None = None
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError as error:
            last_error = error
            time.sleep(0.1)
    raise TimeoutError(f"port {port} did not open: {last_error}")


class DemoApp:
    def __init__(self, sim: str, app: Path):
        self.sim = sim
        self.app = app
        self.port = free_port()
        self.token = f"adversarial-nightly-{self.port}"

    @property
    def device(self) -> str:
        return f"127.0.0.1:{self.port}"

    def install(self) -> None:
        run(["xcrun", "simctl", "terminate", self.sim, BUNDLE_ID], check=False, timeout=20)
        run(["xcrun", "simctl", "uninstall", self.sim, BUNDLE_ID], check=False, timeout=20)
        run(["xcrun", "simctl", "install", self.sim, str(self.app)], timeout=120)

    def launch(self) -> None:
        env = os.environ.copy()
        env.update(
            {
                "SIMCTL_CHILD_INSIDEJOB_PORT": str(self.port),
                "SIMCTL_CHILD_INSIDEJOB_TOKEN": self.token,
                "SIMCTL_CHILD_INSIDEJOB_ID": self.token,
            }
        )
        run(["xcrun", "simctl", "terminate", self.sim, BUNDLE_ID], check=False, timeout=20)
        result = run(["xcrun", "simctl", "launch", self.sim, BUNDLE_ID], env=env, check=False, timeout=45)
        if result.returncode != 0:
            raise RuntimeError(f"BHDemo launch failed: stdout={result.stdout!r} stderr={result.stderr!r}")
        wait_port(self.port, timeout=45)

    def terminate(self) -> None:
        run(["xcrun", "simctl", "terminate", self.sim, BUNDLE_ID], check=False, timeout=20)


OPEN_LAB = """
    Activate(.element(.label("Adversarial Lab"), .traits([.button])))
        .expect(.exists(.label("Async Reveal")), timeout: .seconds(8))
"""

BACK_TO_ROOT = """
    Activate(.element(.label("Adversarial Lab"), .traits([.backButton])))
        .expect(.exists(.label("Adversarial Lab")), timeout: .seconds(8))
    Activate(.element(.label("ButtonHeist Demo"), .traits([.backButton])))
        .expect(.exists(.label("Controls Demo")), timeout: .seconds(8))
"""


def scenario_plan(name: str, title: str, body: str) -> str:
    return f"""
HeistPlan("{name}") {{
{OPEN_LAB}
    Activate(.element(.label("{title}"), .traits([.button])))
        .expect(.exists(.label("{title}")), timeout: .seconds(8))
{body}
{BACK_TO_ROOT}
}}
"""


PASSING_PLANS = {
    "/async-reveal-notification": scenario_plan(
        "adversarialAsyncRevealNotificationPass",
        "Async Reveal",
        """
    Activate(.label("Reveal with notification"))
        .expect(.exists(.label("Delayed code: 7429")), timeout: .seconds(3))
""",
    ),
    "/async-reveal-silent": scenario_plan(
        "adversarialAsyncRevealSilentPass",
        "Async Reveal",
        """
    Activate(.label("Reveal silently"))
        .expect(.exists(.label("Delayed code: 7429")), timeout: .seconds(3))
""",
    ),
    "/offscreen-checkout": scenario_plan(
        "adversarialOffscreenCheckoutPass",
        "Offscreen Checkout",
        """
    Activate(.label("Add Espresso"))
        .expect(.exists(.label("Remove Espresso")), timeout: .seconds(2))
    Activate(.element(.label("Place order"), .traits([.button])))
        .expect(.exists(.label("Order placed")), timeout: .seconds(4))
""",
    ),
    "/duplicate-labels": scenario_plan(
        "adversarialDuplicateLabelsPass",
        "Duplicate Labels",
        """
    CustomAction("Toggle", on: .element(
        .label("Review PR"),
        .value("Active"),
        .customContent(.match(label: "Category", value: "Work")),
        .customContent(.match(label: "Priority", value: "High")),
        .actions([.custom("Toggle")])
    ))
        .expect(.exists(.element(
            .label("Review PR"),
            .value("Completed"),
            .customContent(.match(label: "Category", value: "Work")),
            .customContent(.match(label: "Priority", value: "High"))
        )), timeout: .seconds(2))
""",
    ),
    "/dynamic-cells": scenario_plan(
        "adversarialDynamicCellsPass",
        "Dynamic Cells",
        """
    Activate(.label("Churn menu"))
        .expect(.exists(.label("Menu churned")), timeout: .seconds(4))
    CustomAction("Add to Cart", on: .element(
        .label("Nebula Noodles Prime"),
        .customContent(.match(label: "SKU", value: "SKU-72")),
        .customContent(.match(label: "Category", value: "Mains")),
        .customContent(.match(label: "Churn State", value: "post-churn")),
        .customContent(.match(label: "Menu Slot", value: "deep target after churn")),
        .customContent(.match(label: "Unit Price", value: "$18.00")),
        .actions([.custom("Add to Cart")])
    ))
        .expect(.exists(.element(
            .label("Nebula Noodles Prime"),
            .customContent(.match(label: "SKU", value: "SKU-72")),
            .customContent(.match(label: "Churn State", value: "post-churn")),
            .customContent(.match(label: "Quantity", value: "1")),
            .customContent(.match(label: "Line Total", value: "$18.00")),
            .actions([.custom("Remove from Cart")])
        )), timeout: .seconds(6))
""",
    ),
    "/text-field-fallback": scenario_plan(
        "adversarialTextFieldFallbackPass",
        "Text Field Fallback",
        """
    TypeText("fallback typed", into: .element(.label("Fallback field"), .traits([.textEntry])), replacingExisting: true)
        .expect(.exists(.value("fallback typed")), timeout: .seconds(3))
    DismissKeyboard()
        .withoutExpectation("Returns the app to navigation after text entry")
""",
    ),
    "/stale-live-object": scenario_plan(
        "adversarialStaleLiveObjectPass",
        "Stale Live Object",
        """
    WaitFor(.exists(.element(.label("Submit Order"), .value("version 1"))), timeout: .seconds(2))
    Activate(.label("Replace Target"))
        .expect(.exists(.element(.label("Submit Order"), .value("version 2"))), timeout: .seconds(2))
    Activate(.element(.label("Submit Order"), .value("version 2")))
        .expect(.exists(.label("Result: submitted version 2")), timeout: .seconds(2))
""",
    ),
    "/modal-obstruction": scenario_plan(
        "adversarialModalObstructionPass",
        "Modal Obstruction",
        """
    Activate(.label("Review order"))
        .expect(.exists(.label("Order review")), timeout: .seconds(4))
    Activate(.label("Confirm review"))
        .expect(.exists(.label("Status: Review confirmed")), timeout: .seconds(2))
    Activate(.label("Close"))
        .expect(.missing(.label("Order review")), timeout: .seconds(4))
""",
    ),
    "/nested-scroll": scenario_plan(
        "adversarialNestedScrollPass",
        "Nested Scroll",
        """
    Activate(.label("Verified by The Vibe Check"))
        .expect(.exists(.label("Selected Verified")), timeout: .seconds(6))
""",
    ),
}


FAILING_PLANS = {
    "/async-reveal": (
        scenario_plan(
            "adversarialAsyncRevealWrongDestinationFails",
            "Async Reveal",
            """
    Activate(.label("Reveal silently"))
        .withoutExpectation("The failing wait below proves async destination diagnostics")
    WaitFor(.exists(.label("Delayed code: 9999")), timeout: .seconds(0.2))
""",
        ),
        "Delayed code: 9999",
    ),
    "/offscreen-checkout": (
        scenario_plan(
            "adversarialOffscreenCheckoutDisabledFails",
            "Offscreen Checkout",
            """
    Activate(.element(.label("Place order"), .traits([.button])))
""",
        ),
        "Place order",
    ),
    "/duplicate-labels": (
        scenario_plan(
            "adversarialDuplicateLabelsAmbiguousFails",
            "Duplicate Labels",
        """
    CustomAction("Toggle", on: .label("Review PR"))
""",
        ),
        "ambiguous",
    ),
    "/dynamic-cells": (
        scenario_plan(
            "adversarialDynamicCellsStaleTargetFails",
            "Dynamic Cells",
            """
    Activate(.label("Churn menu"))
        .expect(.exists(.label("Menu churned")), timeout: .seconds(4))
    CustomAction("Add to Cart", on: .element(
        .label("Nebula Noodles"),
        .customContent(.match(label: "SKU", value: "SKU-72")),
        .customContent(.match(label: "Churn State", value: "pre-churn")),
        .actions([.custom("Add to Cart")])
    ))
""",
        ),
        "pre-churn",
    ),
    "/text-field-fallback": (
        scenario_plan(
            "adversarialTextFieldFallbackTargetlessFails",
            "Text Field Fallback",
            """
    TypeText("orphan typed")
""",
        ),
        "TypeText",
    ),
    "/stale-live-object": (
        scenario_plan(
            "adversarialStaleLiveObjectAmbiguousFails",
            "Stale Live Object",
        """
    Activate(.label("Replace Target"))
        .expect(.exists(.element(.label("Submit Order"), .value("version 2"))), timeout: .seconds(2))
    Activate(.label("Show Duplicate Target"))
        .expect(.exists(.element(.label("Submit Order"), .value("version duplicate"))), timeout: .seconds(2))
    Activate(.label("Submit Order"))
""",
        ),
        "ambiguous",
    ),
    "/modal-obstruction": (
        scenario_plan(
            "adversarialModalObstructionBackgroundFails",
            "Modal Obstruction",
            """
    Activate(.label("Review order"))
        .expect(.exists(.label("Order review")), timeout: .seconds(4))
    Activate(.label("Archive order 100"))
""",
        ),
        "Archive order 100",
    ),
    "/nested-scroll": (
        scenario_plan(
            "adversarialNestedScrollImpossibleFails",
            "Nested Scroll",
            """
    Activate(.label("Album That Does Not Exist"))
""",
        ),
        "Album That Does Not Exist",
    ),
}


def run_heist(cli: Path, app: DemoApp, plan: str, *, timeout: float = 60) -> tuple[subprocess.CompletedProcess[str], int]:
    start = time.monotonic_ns()
    env = os.environ.copy()
    env.update(
        {
            "BUTTONHEIST_TOKEN": app.token,
            "BUTTONHEIST_DRIVER_ID": app.token,
        }
    )
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
        timeout=timeout,
        check=False,
    )
    duration_ms = int((time.monotonic_ns() - start) / 1_000_000)
    return result, duration_ms


def execute_scenario(
    cli: Path,
    app: DemoApp,
    scenario: Scenario,
    report: dict[str, Any],
    report_path: Path,
    ceiling_policy: CeilingPolicy,
) -> None:
    observations: list[IterationObservation] = []
    scenario_index = len(report["scenarios"])
    report["scenarios"].append(scenario_report(scenario, observations))
    report["summary"] = gate_summary(report["scenarios"], ceiling_policy)
    write_report(report_path, report)

    for iteration in range(1, scenario.repeat_count + 1):
        result, duration_ms = run_heist(cli, app, scenario.plan)
        observation = observe_iteration(scenario, iteration, result, duration_ms)
        observations.append(observation)
        report["scenarios"][scenario_index] = scenario_report(scenario, observations)
        report["summary"] = gate_summary(report["scenarios"], ceiling_policy)
        write_report(report_path, report)

        stop_after_recovery = not observation.passed and observation.requires_app_recovery
        if observation.requires_app_recovery:
            app.launch()
        if stop_after_recovery:
            break


def error_summary(error: BaseException) -> dict[str, Any]:
    return {
        "type": type(error).__name__,
        "message": str(error),
        "traceback": traceback.format_exception(type(error), error, error.__traceback__),
    }


def write_report(path: Path, report: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the BH Demo adversarial lab nightly gate")
    parser.add_argument("--cli", default=os.environ.get("BUTTONHEIST_CLI", "ButtonHeistCLI/.build/debug/buttonheist"))
    parser.add_argument("--app", default=os.environ.get("BH_DEMO_APP"))
    parser.add_argument("--sim-udid", default=os.environ.get("SIM_UDID"))
    parser.add_argument("--repeat-count", type=int, default=int(os.environ.get("BUTTONHEIST_ADVERSARIAL_REPEAT_COUNT", "20")))
    parser.add_argument(
        "--failure-repeat-count",
        type=int,
        default=os.environ.get("BUTTONHEIST_ADVERSARIAL_FAILURE_REPEAT_COUNT"),
    )
    parser.add_argument(
        "--ceiling-policy",
        type=CeilingPolicy,
        choices=list(CeilingPolicy),
        default=os.environ.get("BUTTONHEIST_ADVERSARIAL_CEILING_POLICY", CeilingPolicy.RECORD.value),
    )
    parser.add_argument("--report", default=str(Path(os.environ.get("TMPDIR", "/tmp")) / "buttonheist-adversarial-nightly-report.json"))
    args = parser.parse_args()
    if args.failure_repeat_count is None:
        args.failure_repeat_count = args.repeat_count
    return args


def main() -> int:
    args = parse_args()
    report_path = Path(args.report)
    report: dict[str, Any] = {
        "gate": "ios-demo-adversarial-lab-nightly",
        "status": "starting",
        "configuration": {
            "repeatCount": args.repeat_count,
            "failureRepeatCount": args.failure_repeat_count,
            "ceilingPolicy": args.ceiling_policy.value,
        },
        "runtime": {
            "cli": args.cli,
            "app": args.app,
            "simulator": args.sim_udid,
        },
        "scenarios": [],
        "summary": gate_summary([], args.ceiling_policy),
    }
    write_report(report_path, report)

    try:
        if args.repeat_count < 1:
            raise RuntimeError("--repeat-count must be at least 1")
        if args.failure_repeat_count < 1:
            raise RuntimeError("--failure-repeat-count must be at least 1")
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

        run(["xcrun", "simctl", "boot", args.sim_udid], check=False, timeout=30)
        run(["xcrun", "simctl", "bootstatus", args.sim_udid, "-b"], timeout=120)

        app = DemoApp(args.sim_udid, app_path)
        app.install()
        app.launch()

        report["status"] = "running"
        report["runtime"] = {
            "cli": str(cli),
            "app": str(app_path),
            "simulator": args.sim_udid,
        }
        write_report(report_path, report)

        for scenario, plan in PASSING_PLANS.items():
            execute_scenario(
                cli,
                app,
                Scenario(
                    name=scenario,
                    plan=plan,
                    repeat_count=args.repeat_count,
                    expectation=ScenarioExpectation.COMMAND_SUCCEEDS,
                ),
                report,
                report_path,
                args.ceiling_policy,
            )

        for scenario, (plan, expected_text) in FAILING_PLANS.items():
            execute_scenario(
                cli,
                app,
                Scenario(
                    name=scenario,
                    plan=plan,
                    repeat_count=args.failure_repeat_count,
                    expectation=ScenarioExpectation.COMMAND_FAILS_WITH_DIAGNOSTIC,
                    expected_diagnostic_text=expected_text,
                ),
                report,
                report_path,
                args.ceiling_policy,
            )

        app.terminate()
        report["summary"] = gate_summary(report["scenarios"], args.ceiling_policy)
        failed = gate_failed(report["summary"])
        report["status"] = "failed" if failed else "passed"
        report["failureKind"] = ", ".join(report["summary"]["failureKinds"]) if failed else "none"
        write_report(report_path, report)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1 if failed else 0
    except Exception as error:
        report["status"] = "failed"
        report["failureKind"] = (
            "infrastructure-timeout"
            if isinstance(error, (subprocess.TimeoutExpired, TimeoutError))
            else "infrastructure-failure"
        )
        report["error"] = error_summary(error)
        write_report(report_path, report)
        print(f"Adversarial lab gate failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
