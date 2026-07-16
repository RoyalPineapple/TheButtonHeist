#!/usr/bin/env python3

import json
import runpy
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).resolve().parents[1]
GATE = runpy.run_path(str(SCRIPTS / "mutation-gate.py"))
TEST_RUNNER = runpy.run_path(str(SCRIPTS / "test-runner.py"))


class MutationGateTests(unittest.TestCase):
    def test_manifest_registers_the_ten_named_mutations_once(self) -> None:
        _, mutations = GATE["load_manifest"]()

        self.assertEqual(len(mutations), 10)
        self.assertEqual(len({mutation["id"] for mutation in mutations}), 10)
        self.assertEqual(
            {mutation["focus"] for mutation in mutations},
            {
                "mutation-receipt-kind",
                "mutation-child-abort-path",
                "mutation-release-proof",
                "mutation-live-target-refresh",
                "mutation-interaction-fifo",
                "mutation-receipt-legality",
                "mutation-screen-generation",
                "mutation-active-cancellation",
                "mutation-settlement-threshold",
                "mutation-stale-discovery",
            },
        )
        self.assertTrue(
            {mutation["focus"] for mutation in mutations}.issubset(TEST_RUNNER["FOCUSES"])
        )

    def test_every_mutation_matches_one_current_production_decision(self) -> None:
        _, mutations = GATE["load_manifest"]()

        for mutation in mutations:
            source = (GATE["ROOT"] / mutation["file"]).read_text(encoding="utf-8")
            self.assertEqual(
                source.count(mutation["search"]),
                1,
                f"{mutation['id']} must match exactly one decision",
            )

    def test_selection_preserves_manifest_order(self) -> None:
        _, mutations = GATE["load_manifest"]()

        selected = GATE["select_mutations"](
            mutations,
            ["interaction.active-cancellation", "receipt.warning-kind"],
            [],
            False,
        )

        self.assertEqual(
            [mutation["id"] for mutation in selected],
            ["receipt.warning-kind", "interaction.active-cancellation"],
        )
        with self.assertRaisesRegex(ValueError, "select exactly one"):
            GATE["select_mutations"](mutations, [], [], False)
        with self.assertRaisesRegex(ValueError, "unknown mutations"):
            GATE["select_mutations"](mutations, ["missing"], [], False)

    def test_only_expected_diagnostic_is_detection(self) -> None:
        result = GATE["CommandResult"](
            exit_code=1,
            duration_seconds=1,
            output="testRequiredInvariant failed",
        )
        unrelated = GATE["CommandResult"](
            exit_code=1,
            duration_seconds=1,
            output="another assertion failed",
        )

        self.assertEqual(
            GATE["classification"](result, "testRequiredInvariant"),
            ("detected", 1),
        )
        self.assertEqual(
            GATE["classification"](unrelated, "testRequiredInvariant"),
            ("unexpected-failure", 0),
        )

    def test_nonbehavioral_outcomes_remain_distinct_and_inconclusive(self) -> None:
        cases = [
            (GATE["CommandResult"](0, 1, ""), "survived"),
            (GATE["CommandResult"](124, 1, "", timed_out=True), "timeout"),
            (GATE["CommandResult"](1, 1, "SwiftCompile normal"), "compile-error"),
            (GATE["CommandResult"](1, 1, "Test crashed"), "test-crash"),
            (GATE["CommandResult"](1, 1, "No available simulator"), "infrastructure-error"),
        ]

        for result, expected in cases:
            self.assertEqual(GATE["classification"](result, "required assertion")[0], expected)

    def test_exact_replacement_produces_a_reviewable_patch_fingerprint(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repository = Path(directory)
            subprocess.run(["git", "init", "-q"], cwd=repository, check=True)
            subprocess.run(["git", "config", "core.hooksPath", "/dev/null"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.email", "test@example.com"], cwd=repository, check=True)
            subprocess.run(["git", "config", "user.name", "Test"], cwd=repository, check=True)
            source = repository / "Owner.swift"
            source.write_text("before\n", encoding="utf-8")
            subprocess.run(["git", "add", "Owner.swift"], cwd=repository, check=True)
            subprocess.run(["git", "commit", "-qm", "baseline"], cwd=repository, check=True)

            fingerprint = GATE["apply_mutation"](repository, {
                "id": "owner.boundary",
                "file": "Owner.swift",
                "search": "before\n",
                "replacement": "after\n",
            })

            self.assertEqual(source.read_text(encoding="utf-8"), "after\n")
            self.assertEqual(len(fingerprint), 64)

    def test_result_contract_is_json_serializable(self) -> None:
        manifest = json.loads((SCRIPTS / "mutations.json").read_text(encoding="utf-8"))
        json.dumps(manifest)


if __name__ == "__main__":
    unittest.main()
