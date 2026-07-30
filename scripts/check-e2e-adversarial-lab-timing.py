#!/usr/bin/env python3
"""Direct contract checks for adversarial sample isolation and classification."""

from __future__ import annotations

import importlib.util
import json
import subprocess
import sys
from pathlib import Path


SCRIPT = Path(__file__).with_name("e2e-adversarial-lab.py")
SPEC = importlib.util.spec_from_file_location("e2e_adversarial_lab", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
lab = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lab
SPEC.loader.exec_module(lab)


def scenario(
    expectation: str,
    evidence: list[dict[str, str]],
) -> lab.Scenario:
    return lab.Scenario.decode(
        {
            "name": "directContract",
            "route": "/direct-contract",
            "plan": "catalog projection",
            "classification": "statistical",
            "expectedOutcome": expectation,
            "expectedEvidence": evidence,
        }
    )


def run_heist_output(
    *,
    element_value: str = "1",
    announcement: str | None = "Saved",
) -> str:
    result = {
        "delta": {
            "kind": "elementsChanged",
            "elementCount": 1,
            "edits": {
                "updated": [{
                    "after": {
                        "traits": ["staticText"],
                        "label": "Activations",
                        "value": element_value,
                    }
                }]
            },
        }
    }
    if announcement is not None:
        result["announcement"] = announcement
    return json.dumps({
        "status": "ok",
        "report": {
            "nodes": [{
                "path": "$.body[0]",
                "kind": "action",
                "status": "passed",
                "evidence": {"action": {"result": result}},
                "children": [],
            }]
        },
    })


passing = scenario(
    "command-succeeds",
    [
        {"kind": "element", "label": "Activations", "value": "1"},
        {"kind": "notification", "label": "Saved"},
    ],
)
assert passing.expected_evidence == (
    lab.EvidenceFact(lab.EvidenceKind.ELEMENT, "Activations", "1"),
    lab.EvidenceFact(lab.EvidenceKind.NOTIFICATION, "Saved", None),
)
expected_failure = scenario(
    "command-fails-with-diagnostic",
    [{"kind": "diagnostic", "label": "expected diagnostic"}],
)
success = lab.observe_primary(
    passing,
    subprocess.CompletedProcess(["buttonheist"], 0, run_heist_output(), ""),
)
product_failure = lab.observe_primary(
    passing,
    subprocess.CompletedProcess(["buttonheist"], 1, "{}", "recoverable failure"),
)
diagnostic = lab.observe_primary(
    expected_failure,
    subprocess.CompletedProcess(["buttonheist"], 1, "{}", "Expected Diagnostic"),
)
missing_notification = lab.observe_primary(
    passing,
    subprocess.CompletedProcess(
        ["buttonheist"],
        0,
        run_heist_output(announcement=None),
        "",
    ),
)
mismatched_value = lab.observe_primary(
    passing,
    subprocess.CompletedProcess(
        ["buttonheist"],
        0,
        run_heist_output(element_value="2"),
        "",
    ),
)
assert success["status"] == "passed" and success["evidenceMatched"] is True
assert product_failure["status"] == "failed"
assert diagnostic["status"] == "passed" and diagnostic["diagnosticMatched"] is True
assert missing_notification["status"] == "failed"
assert missing_notification["missingEvidence"] == [
    {"kind": "notification", "label": "Saved"}
]
assert mismatched_value["status"] == "failed"
assert mismatched_value["missingEvidence"] == [
    {"kind": "element", "label": "Activations", "value": "1"}
]

samples = lab.execute_samples(
    5,
    lambda iteration: {
        "iteration": iteration,
        "primary": product_failure if iteration == 1 else success,
        "infrastructure": {"status": "passed"},
        "recovery": {"status": "passed"},
    },
)
assert lab.scenario_report(passing, 5, samples)["recorded"] == 5
assert [sample["iteration"] for sample in samples] == [1, 2, 3, 4, 5]


class FakeApp:
    instances = []

    def __init__(self, simulator: str, *, token_prefix: str):
        self.token = token_prefix
        self.instances.append(self)

    def launch(self) -> None:
        pass

    def terminate(self, *, require_stopped: bool) -> None:
        if len(self.instances) == 1:
            raise RuntimeError("first recovery failed")


def fake_heist(*_args) -> subprocess.CompletedProcess[str]:
    return subprocess.CompletedProcess(["buttonheist"], 0, run_heist_output(), "")


routes = []


def flaky_route(*_args) -> None:
    routes.append(_args)
    if len(routes) == 1:
        raise RuntimeError("first route failed")


isolated = lab.execute_samples(
    3,
    lambda iteration: lab.execute_sample(
        Path("buttonheist"),
        "simulator",
        passing,
        iteration,
        app_factory=FakeApp,
        route_opener=flaky_route,
        heist_runner=fake_heist,
    ),
)
assert len({app.token for app in FakeApp.instances}) == 3
assert isolated[0]["recovery"]["status"] == "failed"
assert isolated[0]["infrastructure"]["status"] == "failed"
assert isolated[0]["primary"]["status"] == "not-run"
assert all(sample["primary"]["status"] == "passed" for sample in isolated[1:])
