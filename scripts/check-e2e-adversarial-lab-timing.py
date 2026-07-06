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


ACTION_TIMING = {
    "targetResolutionMs": 1,
    "actionDispatchMs": 2,
    "settleMs": 3,
    "beforeObservationMs": 4,
    "finalSemanticEvidenceMs": 5,
    "totalMs": 15,
}

RECEIPT = {
    "report": {
        "summary": {"durationMs": 1234},
        "nodes": [
            {
                "evidence": {
                    "action": {
                        "result": {
                            "method": "activate",
                            "timing": ACTION_TIMING,
                        }
                    }
                }
            }
        ],
    }
}


samples, _ = lab.receipt_metrics(RECEIPT)
summary = lab.summarize_receipt_timing(samples)

assert samples["heistDurationMs"] == [1234]
assert summary["heistDurationMs"]["total"] == 1234
for bucket, value in ACTION_TIMING.items():
    assert samples[f"actionPipeline.{bucket}"] == [value]
assert summary["actionPipeline.totalMs"]["total"] == ACTION_TIMING["totalMs"]
