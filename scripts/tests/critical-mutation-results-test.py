#!/usr/bin/env python3

import json
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
FILTER = ROOT / "scripts/critical-mutation-results.jq"
MANIFEST = ROOT / "scripts/mutations.json"
COMMIT = "0123456789abcdef0123456789abcdef01234567"


def result_fixture() -> dict[str, object]:
    identifiers = [
        mutation["id"]
        for mutation in json.loads(MANIFEST.read_text(encoding="utf-8"))["mutations"]
    ]
    return {
        "schemaVersion": 1,
        "commit": COMMIT,
        "score": {"detected": len(identifiers), "total": len(identifiers)},
        "results": [
            {"id": identifier, "outcome": "detected", "diagnosticMatches": 1}
            for identifier in identifiers
        ],
    }


def admitted(result: dict[str, object]) -> bool:
    with tempfile.TemporaryDirectory() as directory:
        path = Path(directory) / "result.json"
        path.write_text(json.dumps(result), encoding="utf-8")
        completed = subprocess.run(
            [
                "jq",
                "-e",
                "--arg",
                "commit",
                COMMIT,
                "--slurpfile",
                "manifest",
                str(MANIFEST),
                "-f",
                str(FILTER),
                str(path),
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    return completed.returncode == 0


class CriticalMutationResultsTests(unittest.TestCase):
    def test_complete_exact_sha_behavioral_result_is_admitted(self) -> None:
        self.assertTrue(admitted(result_fixture()))

    def test_wrong_sha_survived_missing_duplicate_and_inconclusive_results_are_rejected(self) -> None:
        cases = []
        wrong_sha = result_fixture()
        wrong_sha["commit"] = "f" * 40
        cases.append(wrong_sha)
        survived = result_fixture()
        survived["results"][0]["outcome"] = "survived"
        cases.append(survived)
        missing = result_fixture()
        missing["results"].pop()
        cases.append(missing)
        duplicate = result_fixture()
        duplicate["results"][-1] = duplicate["results"][0]
        cases.append(duplicate)
        inconclusive = result_fixture()
        inconclusive["results"][0]["outcome"] = "compile-error"
        cases.append(inconclusive)

        for result in cases:
            with self.subTest(result=result):
                self.assertFalse(admitted(result))

    def test_score_and_named_diagnostic_are_required(self) -> None:
        bad_score = result_fixture()
        bad_score["score"]["detected"] = 9
        no_diagnostic = result_fixture()
        no_diagnostic["results"][0]["diagnosticMatches"] = 0

        self.assertFalse(admitted(bad_score))
        self.assertFalse(admitted(no_diagnostic))


if __name__ == "__main__":
    unittest.main()
