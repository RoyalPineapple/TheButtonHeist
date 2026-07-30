#!/usr/bin/env python3

import gzip
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from uuid import UUID


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
from heist_doctor_pairing import TreeOutcome, pair_recordings

SCRIPT = ROOT / "scripts/heist-doctor-from-results.sh"
FINGERPRINT_A = "0123456789abcdef01234567"
FINGERPRINT_B = "89abcdef0123456789abcdef"


class HeistDoctorPairingTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.passes = self.root / "main"
        self.failures = self.root / "pr"
        self.passes.mkdir()
        self.failures.mkdir()

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_pairs_newest_eligible_failure_with_newest_prior_pass(self) -> None:
        older = self.record(self.passes, 1, 10, compressed=True)
        selected_pass = self.record(self.passes, 2, 20)
        self.record(self.passes, 3, 35)
        self.record(self.passes, 15, 25, TreeOutcome.CHILD_ABORTED, child=TreeOutcome.FAILED)
        selected_fail = self.record(self.failures, 4, 30, TreeOutcome.FAILED, compressed=True)
        self.record(self.failures, 5, 40, TreeOutcome.FAILED, fingerprint=FINGERPRINT_B)
        self.record(self.passes, 6, 25).rename(self.passes / "not-a-uuid.json")
        os.utime(older, (100, 100))
        os.utime(selected_pass, (1, 1))

        pairing = pair_recordings(self.passes, self.failures)

        self.assertEqual(pairing.warnings, ())
        self.assertEqual(
            pairing.pair and (pairing.pair.last_pass.path, pairing.pair.new_fail.path),
            (selected_pass, selected_fail),
        )

    def test_malformed_canonical_recordings_are_warnings(self) -> None:
        duplicate = self.path(self.passes, 9)
        duplicate.write_text('{"schemaVersion":1,"schemaVersion":1}', encoding="utf-8")
        inconsistent = self.record(self.passes, 10, 15, TreeOutcome.CHILD_ABORTED)
        selected_pass = self.record(self.passes, 11, 20)
        selected_fail = self.record(self.failures, 12, 30, TreeOutcome.FAILED)

        pairing = pair_recordings(self.passes, self.failures)

        self.assertEqual(
            pairing.pair and (pairing.pair.last_pass.path, pairing.pair.new_fail.path),
            (selected_pass, selected_fail),
        )
        self.assertEqual([warning.path for warning in pairing.warnings], [duplicate, inconsistent])
        self.assertIn("duplicate JSON key", pairing.warnings[0].reason)
        self.assertIn("requires a failed child", pairing.warnings[1].reason)

    def test_shell_preserves_flags_and_delegates(self) -> None:
        selected_pass = self.record(self.passes, 13, 10)
        selected_fail = self.record(self.failures, 14, 20, TreeOutcome.FAILED)
        capture = self.root / "arguments"
        doctor = self.root / "heist-doctor"
        doctor.write_text(
            "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > \"$DOCTOR_ARGUMENT_CAPTURE\"\n",
            encoding="utf-8",
        )
        doctor.chmod(0o755)
        environment = os.environ | {"DOCTOR_ARGUMENT_CAPTURE": str(capture)}

        completed = subprocess.run(
            [
                str(SCRIPT), "--last-pass-dir", str(self.passes),
                "--new-fail-dir", str(self.failures), "--doctor", str(doctor),
                "--format", "json", "--step-path", "$.body[0]", "--no-build",
            ],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertEqual(
            capture.read_text().splitlines(),
            [
                "--last-pass", str(selected_pass), "--new-fail", str(selected_fail),
                "--format", "json", "--step-path", "$.body[0]",
            ],
        )

    @staticmethod
    def path(root: Path, index: int, compressed: bool = False) -> Path:
        return root / f"{UUID(int=index)}.json{'.gz' if compressed else ''}"

    @classmethod
    def record(
        cls,
        root: Path,
        index: int,
        recorded_at: float,
        outcome: TreeOutcome = TreeOutcome.PASSED,
        *,
        fingerprint: str = FINGERPRINT_A,
        compressed: bool = False,
        child: TreeOutcome | None = None,
    ) -> Path:
        path = cls.path(root, index, compressed)
        children = [cls.step("$.body[0].body[0]", child)] if child else []
        recording = {
            "schemaVersion": 1,
            "result": {"steps": [cls.step("$.body[0]", outcome, children)], "durationMs": 1},
            "planName": "fixture",
            "planFingerprint": fingerprint,
            "recordedAt": recorded_at,
            "producerVersion": "1.0.0",
        }
        data = json.dumps(recording, separators=(",", ":")).encode()
        path.write_bytes(gzip.compress(data, mtime=0) if compressed else data)
        return path

    @staticmethod
    def step(
        path: str,
        outcome: TreeOutcome,
        children: list[dict[str, object]] | None = None,
    ) -> dict[str, object]:
        failure = {
            "category": "explicitFailure",
            "contract": "fixture",
            "observed": "fixture",
        }
        node = {
            "type": (
                "failure" if outcome is TreeOutcome.FAILED
                else "heist" if outcome is TreeOutcome.CHILD_ABORTED
                else "warning"
            ),
            "message": "fixture",
            "outcome": outcome.value,
            "children": children or [],
        }
        if outcome.failed:
            node["failure"] = failure
        return {"path": path, "node": node}


if __name__ == "__main__":
    unittest.main()
