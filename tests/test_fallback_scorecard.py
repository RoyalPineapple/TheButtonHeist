import importlib.util
import io
import sys
import tempfile
import unittest
from contextlib import redirect_stdout
from pathlib import Path


def load_scorecard_module():
    script = Path(__file__).resolve().parents[1] / "scripts" / "fallback-scorecard.py"
    spec = importlib.util.spec_from_file_location("fallback_scorecard", script)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class FallbackScorecardTests(unittest.TestCase):
    def test_reports_actionable_categories_without_scoring_docs_or_comments(self):
        scorecard = load_scorecard_module()
        with tempfile.TemporaryDirectory() as directory:
            repo_root = Path(directory)
            self.write(
                repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/Core.swift",
                """
                // fallback in a comment should not count
                /*
                 let commentedFallback = true
                 */
                let fallbackValue = recoverElement()
                let optionalValue = try? loadElement()
                """,
            )
            self.write(
                repo_root / "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+FailureMapping.swift",
                """
                extension FenceError {
                    func encode(error: PublicErrorResponse) -> PublicErrorResponse {
                        encode(fallback: error)
                    }
                }
                """,
            )
            self.write(
                repo_root / "ButtonHeistCLI/Sources/Commands/WaitCommand.swift",
                """
                @Option(help: "Maximum wait time in seconds (default: 10)")
                var timeout: Double
                switch outputStyle {
                default:
                    print("unchanged")
                }
                """,
            )
            self.write(
                repo_root / "ButtonHeist/Sources/TheButtonHeist/TheHandoff/AutoReconnectRecoveryPolicy.swift",
                """
                let retryInterval = 0.2
                let attempts = 3
                """,
            )
            self.write(
                repo_root / "docs/FALLBACK.md",
                """
                fallback in docs should not count
                """,
            )

            report = scorecard.build_report(repo_root)
            counts = report["counts"]

            self.assertEqual(counts["fallback_code_refs"], 2)
            self.assertEqual(counts["silent_core_fallback_refs"], 2)
            self.assertEqual(counts["boundary_error_mapping_refs"], 1)
            self.assertEqual(counts["display_default_refs"], 1)
            self.assertEqual(counts["retry_policy_refs"], 2)
            self.assertEqual(counts["uncategorized_fallback_refs"], 0)

    def test_strip_slash_comments_preserves_strings_and_interpolation(self):
        scorecard = load_scorecard_module()

        uncommented = scorecard.strip_slash_comments(
            '''
            let visible = "fallback in string"
            let interpolated = "fallback \\(name == "x") still string"
            let raw = #"fallback // not a comment /* not a block */"#
            let rawMultiline = #"""
            fallback // not a comment in raw multiline
            """#
            // fallback in line comment
            /*
             fallback in block comment
             /*
              nested fallback in block comment
              */
             */
            let code = fallbackPolicy()
            '''
        )

        self.assertIn('"fallback in string"', uncommented)
        self.assertIn('"fallback \\(name == "x") still string"', uncommented)
        self.assertIn('#"fallback // not a comment /* not a block */"#', uncommented)
        self.assertIn("fallback // not a comment in raw multiline", uncommented)
        self.assertIn("fallbackPolicy()", uncommented)
        self.assertNotIn("fallback in line comment", uncommented)
        self.assertNotIn("fallback in block comment", uncommented)
        self.assertNotIn("nested fallback in block comment", uncommented)

    def test_strip_hash_comments_preserves_triple_quoted_strings(self):
        scorecard = load_scorecard_module()

        uncommented = scorecard.strip_hash_comments(
            '''
            visible = """fallback # not a comment"""
            single = 'fallback # not a comment'
            # fallback in hash comment
            value = fallback_policy()
            '''
        )

        self.assertIn('"""fallback # not a comment"""', uncommented)
        self.assertIn("'fallback # not a comment'", uncommented)
        self.assertIn("fallback_policy()", uncommented)
        self.assertNotIn("fallback in hash comment", uncommented)

    def test_category_for_matches_try_question_without_trailing_word_boundary(self):
        scorecard = load_scorecard_module()

        category = scorecard.category_for(
            "ButtonHeist/Sources/TheInsideJob/TheBrains/Actions.swift",
            "let result = try? performAction()",
            False,
        )

        self.assertEqual(category, "silent_core_fallback_refs")

    def test_category_for_does_not_count_switch_default_as_display_default(self):
        scorecard = load_scorecard_module()

        category = scorecard.category_for(
            "ButtonHeistCLI/Sources/Session/SessionRepl.swift",
            "default:",
            False,
        )

        self.assertIsNone(category)

    def test_display_default_ref_does_not_match_unrelated_default_words(self):
        scorecard = load_scorecard_module()

        self.assertTrue(scorecard.display_default_ref('@Option(help: "Timeout (default: 10)")'))
        self.assertTrue(scorecard.display_default_ref("let defaultLabel = name"))
        self.assertFalse(scorecard.display_default_ref("let defaults = UserDefaults.standard"))
        self.assertFalse(scorecard.display_default_ref("let value = defaultingBehavior"))

    def test_main_fails_when_silent_core_refs_exist(self):
        scorecard = load_scorecard_module()
        with tempfile.TemporaryDirectory() as directory:
            repo_root = Path(directory)
            self.write(
                repo_root / "ButtonHeist/Sources/TheInsideJob/TheBrains/Core.swift",
                "let value = try? loadElement()",
            )

            exit_code = self.run_main(
                scorecard,
                "--repo-root", str(repo_root),
                "--root", "ButtonHeist/Sources",
                "--fail-on-silent-core",
            )

        self.assertEqual(exit_code, 1)

    def test_main_succeeds_when_silent_core_refs_are_absent(self):
        scorecard = load_scorecard_module()
        with tempfile.TemporaryDirectory() as directory:
            repo_root = Path(directory)
            self.write(
                repo_root / "ButtonHeist/Sources/TheButtonHeist/TheFence/TheFence+FailureMapping.swift",
                "encode(fallback: error)",
            )

            exit_code = self.run_main(
                scorecard,
                "--repo-root", str(repo_root),
                "--root", "ButtonHeist/Sources",
                "--fail-on-silent-core",
            )

        self.assertEqual(exit_code, 0)

    def run_main(self, scorecard, *arguments: str) -> int:
        with redirect_stdout(io.StringIO()):
            return scorecard.main(list(arguments))

    def write(self, path: Path, contents: str):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(contents.strip() + "\n", encoding="utf-8")


if __name__ == "__main__":
    unittest.main()
