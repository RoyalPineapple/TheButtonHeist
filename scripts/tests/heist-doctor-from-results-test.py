#!/usr/bin/env python3

import gzip
import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / "scripts/heist-doctor-from-results.sh"
FINGERPRINT_A = "0123456789abcdef01234567"
FINGERPRINT_B = "89abcdef0123456789abcdef"


class HeistDoctorFromResultsTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name)
        self.last_pass_root = self.root / "main-artifact"
        self.new_fail_root = self.root / "pr-artifact"
        self.last_pass_root.mkdir()
        self.new_fail_root.mkdir()
        self.capture_path = self.root / "doctor-arguments"
        self.doctor_path = self.root / "heist-doctor"
        self.doctor_path.write_text(
            "#!/usr/bin/env bash\n"
            "set -euo pipefail\n"
            "printf '%s\\n' \"$@\" > \"$DOCTOR_ARGUMENT_CAPTURE\"\n",
            encoding="utf-8",
        )
        self.doctor_path.chmod(0o755)

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def test_pairs_by_decoded_fingerprint_and_outcome(self) -> None:
        older_pass = self.write_recording(
            self.last_pass_root / "passing-history" / "11111111-1111-4111-8111-111111111111.json.gz",
            fingerprint=FINGERPRINT_A,
            outcome="passed",
            recorded_at=10,
        )
        selected_pass = self.write_recording(
            self.last_pass_root / "unrelated-directory" / "22222222-2222-4222-8222-222222222222.json",
            fingerprint=FINGERPRINT_A,
            outcome="passed",
            recorded_at=20,
        )
        selected_fail = self.write_recording(
            self.new_fail_root / "different-directory" / "33333333-3333-4333-8333-333333333333.json.gz",
            fingerprint=FINGERPRINT_A,
            outcome="failed",
            recorded_at=30,
        )
        self.write_recording(
            self.new_fail_root / "newest-but-unmatched" / "44444444-4444-4444-8444-444444444444.json",
            fingerprint=FINGERPRINT_B,
            outcome="failed",
            recorded_at=40,
        )
        self.write_recording(
            self.last_pass_root / "legacy" / "20260730-123-passed.json.gz",
            fingerprint=FINGERPRINT_A,
            outcome="passed",
            recorded_at=50,
        )
        os.utime(older_pass, (100, 100))
        os.utime(selected_pass, (1, 1))

        completed = self.run_script()

        self.assertEqual(completed.returncode, 0, completed.stderr)
        self.assertIn(f"fingerprint: {FINGERPRINT_A}", completed.stdout)
        self.assertEqual(
            self.capture_path.read_text(encoding="utf-8").splitlines(),
            [
                "--last-pass",
                str(selected_pass),
                "--new-fail",
                str(selected_fail),
                "--format",
                "human",
            ],
        )

    def test_later_failed_step_cannot_supply_pass_baseline(self) -> None:
        self.write_recording(
            self.last_pass_root / "55555555-5555-4555-8555-555555555555.json",
            fingerprint=FINGERPRINT_A,
            outcome="passed",
            recorded_at=10,
            additional_outcome="failed",
        )
        self.write_recording(
            self.new_fail_root / "66666666-6666-4666-8666-666666666666.json.gz",
            fingerprint=FINGERPRINT_A,
            outcome="failed",
            recorded_at=20,
        )

        completed = self.run_script()

        self.assertEqual(completed.returncode, 1)
        self.assertIn("same decoded plan fingerprint", completed.stderr)
        self.assertFalse(self.capture_path.exists())

    def run_script(self) -> subprocess.CompletedProcess[str]:
        environment = os.environ.copy()
        environment["DOCTOR_ARGUMENT_CAPTURE"] = str(self.capture_path)
        return subprocess.run(
            [
                str(SCRIPT),
                "--last-pass-dir",
                str(self.last_pass_root),
                "--new-fail-dir",
                str(self.new_fail_root),
                "--doctor",
                str(self.doctor_path),
                "--no-build",
            ],
            cwd=ROOT,
            env=environment,
            capture_output=True,
            text=True,
            check=False,
        )

    def write_recording(
        self,
        path: Path,
        *,
        fingerprint: str,
        outcome: str,
        recorded_at: float,
        additional_outcome: str | None = None,
    ) -> Path:
        path.parent.mkdir(parents=True, exist_ok=True)
        steps = [self.step("$.body[0]", outcome)]
        if additional_outcome is not None:
            steps.append(self.step("$.body[1]", additional_outcome))
        recording = {
            "schemaVersion": 1,
            "result": {
                "steps": steps,
                "durationMs": 1,
            },
            "planName": "fixture",
            "planFingerprint": fingerprint,
            "recordedAt": recorded_at,
            "producerVersion": "1.0.0",
        }
        data = json.dumps(recording, sort_keys=True, separators=(",", ":")).encode("utf-8")
        path.write_bytes(gzip.compress(data, mtime=0) if path.name.endswith(".gz") else data)
        return path

    @staticmethod
    def step(path: str, outcome: str) -> dict[str, object]:
        if outcome == "failed":
            node = {
                "type": "failure",
                "message": "fixture failure",
                "outcome": "failed",
                "failure": {
                    "category": "explicitFailure",
                    "contract": "fixture",
                    "observed": "fixture failure",
                },
                "children": [],
            }
        else:
            node = {
                "type": "warning",
                "message": "fixture warning",
                "outcome": outcome,
                "children": [],
            }
        return {
            "path": path,
            "node": node,
        }


if __name__ == "__main__":
    unittest.main()
