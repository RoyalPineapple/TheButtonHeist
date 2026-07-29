#!/usr/bin/env python3
"""Direct contract checks for adversarial sample isolation and classification."""

from __future__ import annotations

import importlib.util
import subprocess
import sys
from pathlib import Path


SCRIPT = Path(__file__).with_name("e2e-adversarial-lab.py")
SPEC = importlib.util.spec_from_file_location("e2e_adversarial_lab", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
lab = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lab
SPEC.loader.exec_module(lab)


def scenario(expectation: str, kind: str, label: str) -> lab.Scenario:
    return lab.Scenario.decode(
        {
            "name": "directContract",
            "route": "/direct-contract",
            "plan": "catalog projection",
            "classification": "statistical",
            "expectedOutcome": expectation,
            "expectedEvidence": [{"kind": kind, "label": label}],
        }
    )


passing = scenario("command-succeeds", "element", "Done")
expected_failure = scenario("command-fails-with-diagnostic", "diagnostic", "expected diagnostic")
success = lab.observe_primary(passing, subprocess.CompletedProcess(["buttonheist"], 0, "{}", ""))
product_failure = lab.observe_primary(passing, subprocess.CompletedProcess(["buttonheist"], 1, "{}", "recoverable failure"))
diagnostic = lab.observe_primary(expected_failure, subprocess.CompletedProcess(["buttonheist"], 1, "{}", "Expected Diagnostic"))
assert success["status"] == "passed"
assert product_failure["status"] == "failed"
assert diagnostic["status"] == "passed" and diagnostic["diagnosticMatched"] is True

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
    return subprocess.CompletedProcess(["buttonheist"], 0, "{}", "")


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
