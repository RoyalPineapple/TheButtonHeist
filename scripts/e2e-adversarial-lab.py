#!/usr/bin/env python3
"""Nightly adversarial lab gate for BH Demo.

This is intentionally separate from PR correctness tests. It repeats hostile
demo flows through the public CLI and records fresh results as CI artifacts.
"""

from __future__ import annotations

import argparse
import json
import math
import os
import subprocess
import sys
import time
from dataclasses import dataclass
from enum import Enum
from pathlib import Path
from typing import Any

from e2e_runtime import (
    DemoApp,
    boot_simulator,
    error_summary,
    failure_kind,
    install_app,
    parse_jsonish,
    run,
    write_json_report,
)

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
    unexpected_ceiling_hits: list[dict[str, Any]]
    response: Any | None
    stdout: str
    stderr: str

    @property
    def requires_app_recovery(self) -> bool:
        return self.returncode != 0


def ms(value: Any) -> int | None:
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)) and math.isfinite(value):
        return max(0, int(round(value)))
    return None


def report_metrics_object(response: Any) -> dict[str, Any] | None:
    if not isinstance(response, dict):
        return None
    report = response.get("report")
    if not isinstance(report, dict):
        return None
    metrics = report.get("metrics")
    return metrics if isinstance(metrics, dict) else None


def result_ceiling_hits(response: Any) -> list[dict[str, Any]]:
    metrics = report_metrics_object(response)
    if metrics is None:
        return []
    ceiling_rows = metrics.get("ceilings")
    if not isinstance(ceiling_rows, list):
        return []
    hits: list[dict[str, Any]] = []
    for row in ceiling_rows:
        if not isinstance(row, dict):
            continue
        budget_ms = ms(row.get("budgetMs"))
        elapsed_ms = ms(row.get("elapsedMs"))
        if (
            not isinstance(row.get("source"), str)
            or not row["source"]
            or budget_ms is None
            or elapsed_ms is None
        ):
            continue
        if elapsed_ms > budget_ms + CEILING_HIT_TOLERANCE_MS:
            hits.append(row)
    return hits


def with_iteration(items: list[dict[str, Any]], iteration: int) -> list[dict[str, Any]]:
    return [{"iteration": iteration, **item} for item in items]


def observe_iteration(
    scenario: Scenario,
    iteration: int,
    result: subprocess.CompletedProcess[str],
) -> IterationObservation:
    parsed_stdout = parse_jsonish(result.stdout)
    parsed = parsed_stdout if parsed_stdout is not None else parse_jsonish(result.stderr)
    ceiling_hits = result_ceiling_hits(parsed)
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
    ceiling_hits: list[dict[str, Any]] = []
    for observation in observations:
        ceiling_hits.extend(with_iteration(observation.unexpected_ceiling_hits, observation.iteration))
    passed = sum(observation.passed for observation in observations)
    return {
        "name": scenario.name,
        "expectation": scenario.expectation.value,
        "expectedDiagnosticText": scenario.expected_diagnostic_text,
        "repeatCount": scenario.repeat_count,
        "attempted": len(observations),
        "passed": passed,
        "failed": len(observations) - passed,
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


OPEN_LAB = """
    Activate(.element(.label("Adversarial Lab"), .traits([.button])))
        .expect(.exists(.label("Async Reveal")), timeout: 8)
"""

BACK_TO_ROOT = """
    Activate(.element(.label("Adversarial Lab"), .traits([.backButton])))
        .expect(.exists(.label("Adversarial Lab")), timeout: 8)
    Activate(.element(.label("ButtonHeist Demo"), .traits([.backButton])))
        .expect(.exists(.label("Controls Demo")), timeout: 8)
"""


def scenario_plan(name: str, title: str, body: str) -> str:
    return f"""
HeistPlan("{name}") {{
{OPEN_LAB}
    Activate(.element(.label("{title}"), .traits([.button])))
        .expect(.exists(.label("{title}")), timeout: 8)
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
        .expect(.exists(.label("Delayed code: 7429")), timeout: 3)
""",
    ),
    "/async-reveal-silent": scenario_plan(
        "adversarialAsyncRevealSilentPass",
        "Async Reveal",
        """
    Activate(.label("Reveal silently"))
        .expect(.exists(.label("Delayed code: 7429")), timeout: 3)
""",
    ),
    "/offscreen-checkout": scenario_plan(
        "adversarialOffscreenCheckoutPass",
        "Offscreen Checkout",
        """
    Activate(.element(.label("Place order"), .traits([.button])))
        .expect(.exists(.label("Order placed")), timeout: 4)
""",
    ),
    "/duplicate-labels": scenario_plan(
        "adversarialDuplicateLabelsPass",
        "Duplicate Labels",
        """
    CustomAction("Toggle", on: .element(
        .label("Review PR"),
        .value("Active"),
        .customContent(.init(label: "Category", value: "Work")),
        .customContent(.init(label: "Priority", value: "High")),
        .actions([.custom("Toggle")])
    ))
        .expect(.exists(.element(
            .label("Review PR"),
            .value("Completed"),
            .customContent(.init(label: "Category", value: "Work")),
            .customContent(.init(label: "Priority", value: "High"))
        )), timeout: 2)
""",
    ),
    "/dynamic-cells": scenario_plan(
        "adversarialDynamicCellsPass",
        "Dynamic Cells",
        """
    Activate(.label("Churn menu"))
        .expect(.exists(.label("Menu churned")), timeout: 4)
    CustomAction("Add to Cart", on: .element(
        .label("Nebula Noodles"),
        .customContent(.init(label: "SKU", value: "SKU-72")),
        .customContent(.init(label: "Category", value: "Mains")),
        .customContent(.init(label: "Generation", value: "2")),
        .customContent(.init(label: "Menu Slot", value: "deep target after churn")),
        .customContent(.init(label: "Unit Price", value: "$18.00")),
        .actions([.custom("Add to Cart")])
    ))
        .expect(.exists(.element(
            .label("Nebula Noodles"),
            .customContent(.init(label: "SKU", value: "SKU-72")),
            .customContent(.init(label: "Generation", value: "2")),
            .customContent(.init(label: "Quantity", value: "1")),
            .customContent(.init(label: "Line Total", value: "$18.00")),
            .actions([.custom("Remove from Cart")])
        )), timeout: 6)
""",
    ),
    "/text-field-fallback": scenario_plan(
        "adversarialTextFieldFallbackPass",
        "Text Field Fallback",
        """
    TypeText(.replacing("fallback typed"), into: .element(.label("Fallback field"), .traits([.textEntry])))
        .expect(.exists(.value("fallback typed")), timeout: 3)
    dismissKeyboard()
        .withoutExpectation("Returns the app to navigation after text entry")
""",
    ),
    "/stale-live-object": scenario_plan(
        "adversarialStaleLiveObjectPass",
        "Stale Live Object",
        """
    WaitFor(.exists(.element(
        .label("Submit Order"),
        .value("Generation 2, actions 0, generation 1 actions 0")
    )), timeout: 3)
    Activate(.element(
        .label("Submit Order"),
        .value("Generation 2, actions 0, generation 1 actions 0")
    ))
        .expect(.exists(.label("Result: submitted generation 2")), timeout: 2)
""",
    ),
    "/modal-obstruction": scenario_plan(
        "adversarialModalObstructionPass",
        "Modal Obstruction",
        """
    Activate(.label("Review order"))
        .expect(.exists(.element(.label("Order review"), .value("Ready"))), timeout: 4)
    Activate(.label("Confirm review"))
        .expect(.exists(.label("Status: Review confirmed")), timeout: 2)
    Activate(.label("Close"))
        .expect(.missing(.label("Order review")), timeout: 4)
""",
    ),
    "/nested-scroll": scenario_plan(
        "adversarialNestedScrollPass",
        "Nested Scroll",
        """
    Activate(.label("Verified by The Vibe Check"))
        .expect(.exists(.label("Selected Verified")), timeout: 6)
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
    WaitFor(.exists(.label("Delayed code: 9999")), timeout: 0.2)
""",
        ),
        "Delayed code: 9999",
    ),
    "/offscreen-checkout": (
        scenario_plan(
            "adversarialOffscreenCheckoutDisabledFails",
            "Offscreen Checkout",
            """
    Activate(.element(.label("Unavailable order"), .traits([.button])))
""",
        ),
        "Unavailable order",
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
        .expect(.exists(.label("Menu churned")), timeout: 4)
    CustomAction("Add to Cart", on: .element(
        .label("Nebula Noodles"),
        .customContent(.init(label: "SKU", value: "SKU-72")),
        .customContent(.init(label: "Generation", value: "1")),
        .actions([.custom("Add to Cart")])
    ))
""",
        ),
        "Generation",
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
    WaitFor(.exists(.element(
        .label("Submit Order"),
        .value("Generation 2, actions 0, generation 1 actions 0")
    )), timeout: 3)
    Activate(.label("Show Duplicate Target"))
        .expect(.exists(.element(
            .label("Submit Order"),
            .value("Generation 3, actions 0, generation 1 actions 0")
        )), timeout: 2)
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
        .expect(.exists(.element(.label("Order review"), .value("Ready"))), timeout: 4)
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


def run_heist(
    cli: Path,
    app: DemoApp,
    plan: str,
    *,
    timeout: float = 60,
) -> subprocess.CompletedProcess[str]:
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
    return result


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
        result = run_heist(cli, app, scenario.plan)
        observation = observe_iteration(scenario, iteration, result)
        observations.append(observation)
        report["scenarios"][scenario_index] = scenario_report(scenario, observations)
        report["summary"] = gate_summary(report["scenarios"], ceiling_policy)
        write_report(report_path, report)

        stop_after_recovery = not observation.passed and observation.requires_app_recovery
        if observation.requires_app_recovery:
            app.launch()
        if stop_after_recovery:
            break


def write_report(path: Path, report: dict[str, Any]) -> None:
    write_json_report(path, report)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Run the BH Demo adversarial lab nightly gate")
    parser.add_argument(
        "--print-plan-catalog",
        action="store_true",
        help="Print every authored nightly plan as JSON without launching the app.",
    )
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
    if args.print_plan_catalog:
        catalog = [
            {
                "name": name,
                "expectation": ScenarioExpectation.COMMAND_SUCCEEDS.value,
                "plan": plan,
            }
            for name, plan in PASSING_PLANS.items()
        ] + [
            {
                "name": name,
                "expectation": ScenarioExpectation.COMMAND_FAILS_WITH_DIAGNOSTIC.value,
                "plan": plan,
            }
            for name, (plan, _) in FAILING_PLANS.items()
        ]
        print(json.dumps(catalog, sort_keys=True))
        return 0
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

        boot_simulator(args.sim_udid)

        install_app(args.sim_udid, app_path)
        app = DemoApp(args.sim_udid, token_prefix="adversarial-nightly")
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
        report["failureKind"] = failure_kind(
            error,
            scenario_started=False,
            product_failure="product-scenario-failure",
        )
        report["error"] = error_summary(error)
        write_report(report_path, report)
        print(f"Adversarial lab gate failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
