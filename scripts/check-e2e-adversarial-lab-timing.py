#!/usr/bin/env python3
"""Self-check direct canonical ceiling evaluation in the adversarial gate."""

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
                    "elapsedMs": 526,
                    "path": "$.body[2]",
                    "kind": "conditional",
                    "status": "failed",
                },
            ],
        },
    },
}


assert lab.receipt_ceiling_hits(RECEIPT) == [
    {
        "path": "$.body[2]",
        "kind": "conditional",
        "status": "failed",
        "source": "caseSelection.timeout",
        "budgetMs": 500,
        "elapsedMs": 526,
    }
]

scenario = lab.Scenario(
    name="/deterministic-negative",
    plan="unused",
    repeat_count=2,
    expectation=lab.ScenarioExpectation.COMMAND_FAILS_WITH_DIAGNOSTIC,
    expected_diagnostic_text="expected diagnostic",
)
observations = [
    lab.observe_iteration(
        scenario,
        1,
        subprocess.CompletedProcess(
            args=["buttonheist"],
            returncode=1,
            stdout=json.dumps(RECEIPT),
            stderr="Expected Diagnostic was emitted",
        ),
    ),
    lab.observe_iteration(
        scenario,
        2,
        subprocess.CompletedProcess(
            args=["buttonheist"],
            returncode=0,
            stdout="{}",
            stderr="expected diagnostic was emitted",
        ),
    ),
]
report = lab.scenario_report(scenario, observations)

assert report["attempted"] == 2
assert report["passed"] == 1
assert report["failed"] == 1
assert report["unexpectedCeilingHits"][0]["iteration"] == 1
assert report["iterations"][0]["diagnosticMatched"] is True
assert report["iterations"][1]["passed"] is False

record_summary = lab.gate_summary([report], lab.CeilingPolicy.RECORD)
fail_summary = lab.gate_summary([report], lab.CeilingPolicy.FAIL)
assert record_summary["ceilingPolicyViolated"] is False
assert fail_summary["ceilingPolicyViolated"] is True
assert lab.gate_failed(fail_summary) is True
