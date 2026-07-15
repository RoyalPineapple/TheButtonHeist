#!/usr/bin/env python3
"""Self-check adversarial lab timing and report aggregation."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path


LAB_SCRIPT = Path(__file__).with_name("e2e-adversarial-lab.py")
SPEC = importlib.util.spec_from_file_location("e2e_adversarial_lab", LAB_SCRIPT)
assert SPEC is not None and SPEC.loader is not None
lab = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lab
SPEC.loader.exec_module(lab)


RECEIPT = {
    "report": {
        "metrics": {
            "samples": [
                {"name": "heistDurationMs", "valueMs": 1234},
                {"name": "actionPipeline.targetResolutionMs", "valueMs": 1, "path": "$.body[0]"},
                {"name": "actionPipeline.actionDispatchMs", "valueMs": 2, "path": "$.body[0]"},
                {"name": "actionPipeline.settleMs", "valueMs": 3, "path": "$.body[0]"},
                {"name": "actionPipeline.beforeObservationMs", "valueMs": 4, "path": "$.body[0]"},
                {"name": "actionPipeline.finalSemanticEvidenceMs", "valueMs": 5, "path": "$.body[0]"},
                {"name": "actionPipeline.totalMs", "valueMs": 15, "path": "$.body[0]"},
                {"name": "waitPipeline.totalMs", "valueMs": 20, "path": "$.body[0]"},
                {"name": "expectationWaitMs", "valueMs": 20, "path": "$.body[0]"},
            ],
            "ceilings": [
                {
                    "source": "intent.wait.timeout",
                    "budgetMs": 1000,
                    "elapsedMs": 800,
                    "path": "$.body[1]",
                    "kind": "wait",
                    "status": "passed",
                },
                {
                    "source": "caseSelection.timeout",
                    "budgetMs": 500,
                    "elapsedMs": 490,
                    "path": "$.body[2]",
                    "kind": "if",
                    "status": "failed",
                },
            ],
        }
    }
}


samples, ceiling_hits = lab.receipt_metrics(RECEIPT)
summary = lab.summarize_receipt_timing(samples)

assert samples["heistDurationMs"] == [1234]
assert summary["heistDurationMs"]["total"] == 1234
assert samples["actionPipeline.targetResolutionMs"] == [1]
assert samples["actionPipeline.actionDispatchMs"] == [2]
assert samples["actionPipeline.settleMs"] == [3]
assert samples["actionPipeline.beforeObservationMs"] == [4]
assert samples["actionPipeline.finalSemanticEvidenceMs"] == [5]
assert samples["actionPipeline.totalMs"] == [15]
assert samples["waitPipeline.totalMs"] == [20]
assert samples["expectationWaitMs"] == [20]
assert summary["actionPipeline.totalMs"]["total"] == 15
assert summary["waitPipeline.totalMs"]["total"] == 20
assert ceiling_hits == [
    {
        "path": "$.body[2]",
        "kind": "if",
        "status": "failed",
        "source": "caseSelection.timeout",
        "budgetMs": 500,
        "elapsedMs": 490,
    }
]


negative_scenario = lab.Scenario(
    name="/deterministic-negative",
    plan="unused",
    repeat_count=3,
    expectation=lab.ScenarioExpectation.COMMAND_FAILS_WITH_DIAGNOSTIC,
    expected_diagnostic_text="expected diagnostic",
)
negative_results = [
    subprocess.CompletedProcess(
        args=["buttonheist"],
        returncode=1,
        stdout=json.dumps(RECEIPT),
        stderr="Expected Diagnostic was emitted",
    ),
    subprocess.CompletedProcess(
        args=["buttonheist"],
        returncode=1,
        stdout=json.dumps(RECEIPT),
        stderr="different diagnostic",
    ),
    subprocess.CompletedProcess(
        args=["buttonheist"],
        returncode=0,
        stdout=json.dumps(RECEIPT),
        stderr="expected diagnostic was emitted",
    ),
]
negative_observations = [
    lab.observe_iteration(negative_scenario, iteration, result, duration_ms)
    for iteration, result, duration_ms in zip(
        range(1, 4),
        negative_results,
        [30, 10, 20],
        strict=True,
    )
]
negative_report = lab.scenario_report(negative_scenario, negative_observations)

assert negative_report["attempted"] == 3
assert negative_report["passed"] == 1
assert negative_report["failed"] == 2
assert negative_report["cliWallTimingMs"] == {
    "count": 3,
    "min": 10,
    "p50": 20,
    "p95": 30,
    "p99": 30,
    "max": 30,
    "total": 60,
}
assert negative_report["receiptTimingMs"]["heistDurationMs"]["count"] == 3
assert negative_report["receiptTimingMs"]["heistDurationMs"]["total"] == 3702
assert [iteration["diagnosticMatched"] for iteration in negative_report["iterations"]] == [
    True,
    False,
    True,
]
assert [iteration["passed"] for iteration in negative_report["iterations"]] == [
    True,
    False,
    False,
]
assert [hit["iteration"] for hit in negative_report["unexpectedCeilingHits"]] == [1, 2, 3]
assert negative_report["iterations"][0]["diagnostics"]["response"] == RECEIPT
assert negative_report["iterations"][1]["diagnostics"]["stderr"] == "different diagnostic"

passing_scenario = lab.Scenario(
    name="/passing",
    plan="unused",
    repeat_count=1,
    expectation=lab.ScenarioExpectation.COMMAND_SUCCEEDS,
)
passing_observation = lab.observe_iteration(
    passing_scenario,
    1,
    subprocess.CompletedProcess(
        args=["buttonheist"],
        returncode=0,
        stdout=json.dumps({"report": {"metrics": {"samples": [], "ceilings": []}}}),
        stderr="",
    ),
    5,
)
passing_iteration = lab.iteration_report(passing_observation)

assert passing_iteration["passed"] is True
assert "diagnostics" not in passing_iteration

ceiling_only_report = lab.scenario_report(negative_scenario, negative_observations[:1])
record_summary = lab.gate_summary([ceiling_only_report], lab.CeilingPolicy.RECORD)
fail_summary = lab.gate_summary([ceiling_only_report], lab.CeilingPolicy.FAIL)

assert record_summary["ceilingPolicyViolated"] is False
assert lab.gate_failed(record_summary) is False
assert fail_summary["ceilingPolicyViolated"] is True
assert lab.gate_failed(fail_summary) is True
