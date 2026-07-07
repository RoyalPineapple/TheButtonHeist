#!/usr/bin/env python3
"""Self-check receipt timing extraction used by e2e-adversarial-lab.py."""

from __future__ import annotations

import importlib.util
from pathlib import Path


LAB_SCRIPT = Path(__file__).with_name("e2e-adversarial-lab.py")
SPEC = importlib.util.spec_from_file_location("e2e_adversarial_lab", LAB_SCRIPT)
assert SPEC is not None and SPEC.loader is not None
lab = importlib.util.module_from_spec(SPEC)
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
