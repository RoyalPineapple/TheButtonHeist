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
from pathlib import Path
from typing import Any


BUNDLE_ID = "com.buttonheist.testapp"
CEILING_HIT_TOLERANCE_MS = 25


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
    parser.add_argument("--report", default=str(Path(os.environ.get("TMPDIR", "/tmp")) / "buttonheist-adversarial-nightly-report.json"))
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    report_path = Path(args.report)
    report: dict[str, Any] = {
        "gate": "ios-demo-adversarial-lab-nightly",
        "repeatCount": args.repeat_count,
        "status": "starting",
        "scenarios": {},
        "diagnostics": {},
    }
    write_report(report_path, report)

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

        run(["xcrun", "simctl", "boot", args.sim_udid], check=False, timeout=30)
        run(["xcrun", "simctl", "bootstatus", args.sim_udid, "-b"], timeout=120)

        app = DemoApp(args.sim_udid, app_path)
        app.install()
        app.launch()

        report["status"] = "running"
        report["cli"] = str(cli)
        report["app"] = str(app_path)
        report["simulator"] = args.sim_udid
        write_report(report_path, report)

        overall_failed = False
        for scenario, plan in PASSING_PLANS.items():
            durations: list[int] = []
            failures: list[dict[str, Any]] = []
            timing_samples = empty_receipt_timing_samples()
            ceiling_hits: list[dict[str, Any]] = []
            for iteration in range(1, args.repeat_count + 1):
                result, duration_ms = run_heist(cli, app, plan)
                durations.append(duration_ms)
                parsed = parse_jsonish(result.stdout) or parse_jsonish(result.stderr)
                iteration_timing, hits = receipt_metrics(parsed)
                merge_receipt_timing_samples(timing_samples, iteration_timing)
                iteration_hits = with_iteration(hits, iteration)
                ceiling_hits.extend(iteration_hits)
                if result.returncode != 0:
                    failures.append({
                        "iteration": iteration,
                        "returncode": result.returncode,
                        "cliWallDurationMs": duration_ms,
                        "receiptTimingMs": summarize_receipt_timing(iteration_timing),
                        "ceilingHits": iteration_hits,
                        "response": parsed,
                        "stderr": result.stderr[-4000:],
                    })
                    overall_failed = True
                    app.launch()
                    break
            report["scenarios"][scenario] = {
                "attempted": len(durations),
                "passed": len(durations) - len(failures),
                "failed": len(failures),
                "cliWallDurationMs": stats(durations),
                "receiptTimingMs": summarize_receipt_timing(timing_samples),
                "unexpectedCeilingHits": ceiling_hits,
                "failures": failures,
            }
            write_report(report_path, report)

        for scenario, (plan, expected_text) in FAILING_PLANS.items():
            result, duration_ms = run_heist(cli, app, plan)
            parsed = parse_jsonish(result.stdout) or parse_jsonish(result.stderr)
            timing_samples, ceiling_hits = receipt_metrics(parsed)
            text = json.dumps(parsed, sort_keys=True) if parsed is not None else result.stdout + result.stderr
            matched = result.returncode != 0 and expected_text.lower() in text.lower()
            if not matched:
                overall_failed = True
            report["diagnostics"][scenario] = {
                "passed": matched,
                "expectedText": expected_text,
                "returncode": result.returncode,
                "cliWallDurationMs": duration_ms,
                "receiptTimingMs": summarize_receipt_timing(timing_samples),
                "ceilingHits": ceiling_hits,
                "response": parsed,
                "stderr": result.stderr[-4000:],
            }
            write_report(report_path, report)
            app.launch()

        app.terminate()
        report["status"] = "failed" if overall_failed else "passed"
        write_report(report_path, report)
        print(json.dumps(report, indent=2, sort_keys=True))
        return 1 if overall_failed else 0
    except Exception as error:
        report["status"] = "failed"
        report["error"] = error_summary(error)
        write_report(report_path, report)
        print(f"Adversarial lab gate failed: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
