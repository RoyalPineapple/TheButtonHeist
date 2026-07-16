#!/usr/bin/env python3

import importlib.util
import unittest
from pathlib import Path


SCRIPT = Path(__file__).resolve().parents[1] / "select-critical-mutations.py"
SPEC = importlib.util.spec_from_file_location("select_critical_mutations", SCRIPT)
assert SPEC is not None and SPEC.loader is not None
SELECTOR = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(SELECTOR)


class CriticalMutationSelectionTests(unittest.TestCase):
    def test_receipt_owner_selects_every_receipt_mutation_and_sentinel(self) -> None:
        self.assertEqual(
            SELECTOR.select([
                "ButtonHeist/Sources/TheScore/Receipts/HeistExecutionStepNode.swift",
            ]),
            [
                "receipt.warning-kind",
                "receipt.child-abort-path",
                "release.required-suite.accept-skipped",
                "receipt.action-legality",
            ],
        )

    def test_interaction_owner_selects_fifo_and_cancellation(self) -> None:
        self.assertEqual(
            SELECTOR.select([
                "ButtonHeist/Tests/TheInsideJobTests/ClientRequestPipelineTests.swift",
            ]),
            [
                "release.required-suite.accept-skipped",
                "interaction.fifo-bypass",
                "interaction.active-cancellation",
            ],
        )

    def test_docs_only_runs_the_always_on_release_sentinel(self) -> None:
        self.assertEqual(
            SELECTOR.select(["docs/CI.md"]),
            ["release.required-suite.accept-skipped"],
        )

    def test_mutation_tooling_and_unknown_production_owners_fail_open(self) -> None:
        all_mutations = [mutation["id"] for mutation in SELECTOR.load_inventory()[1]]
        self.assertEqual(SELECTOR.select(["scripts/mutations.json"]), all_mutations)
        self.assertEqual(
            SELECTOR.select(["ButtonHeist/Sources/NewOwner/NewDecision.swift"]),
            all_mutations,
        )
        self.assertEqual(SELECTOR.select([]), all_mutations)

    def test_arguments_preserve_manifest_order(self) -> None:
        self.assertEqual(
            SELECTOR.mutation_arguments([
                "release.required-suite.accept-skipped",
                "interaction.active-cancellation",
            ]),
            "--mutation release.required-suite.accept-skipped "
            "--mutation interaction.active-cancellation",
        )


if __name__ == "__main__":
    unittest.main()
