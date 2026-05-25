#!/usr/bin/env python3
"""Report fallback-related code references by actionable category."""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


DEFAULT_SOURCE_ROOTS = (
    "ButtonHeist/Sources",
    "ButtonHeistCLI/Sources",
    "ButtonHeistMCP/Sources",
    "TestApp/Sources",
    "TestApp/UIKitSources",
    "TestApp/ResearchSources",
    "scripts",
)

SOURCE_EXTENSIONS = {".swift", ".m", ".mm", ".h", ".py", ".sh"}
EXCLUDED_RELATIVE_PATHS = {
    "scripts/fallback-scorecard.py",
}

REPORT_KEYS = (
    "fallback_code_refs",
    "silent_core_fallback_refs",
    "display_default_refs",
    "boundary_error_mapping_refs",
    "retry_policy_refs",
    "uncategorized_fallback_refs",
)

FALLBACK_RE = re.compile(r"\bfall\s+back\b|\bfallback\w*\b", re.IGNORECASE)
DISPLAY_DEFAULT_RE = re.compile(
    r"\bdefault\s*:|\bdefault[A-Z]\w*\b",
)
DISPLAY_FALLBACK_RE = re.compile(r"\bfallback\w*\b", re.IGNORECASE)
RETRY_POLICY_RE = re.compile(
    r"\bretry\w*\b|\battempt\w*\b|\bbackoff\b|\bjitter\b|\btimeout\b",
    re.IGNORECASE,
)
SILENT_CORE_RE = re.compile(
    r"\bfallback\w*\b|\bsilent\w*\b|\btry\?",
    re.IGNORECASE,
)

DISPLAY_PATH_MARKERS = (
    "TheFence+CommandPresentation",
    "TheFence+Formatting",
    "AccessibilityTrace.swift",
    "ButtonHeistCLI/Sources/Commands",
    "ButtonHeistCLI/Sources/Session",
    "ButtonHeistCLI/Sources/Support/OutputOptions.swift",
    "ButtonHeistMCP/Sources/ToolDefinitions.swift",
    "TestApp/",
)

BOUNDARY_PATH_MARKERS = (
    "TheFence+FailureMapping.swift",
    "TheFence+FailureDetails.swift",
    "TheFence+FailureRendering.swift",
    "TheFence+FailureTaxonomy.swift",
    "TheFence+FailureTypes.swift",
    "TheFence+Failures.swift",
    "SchemaValidationError.swift",
    "PublicJSONSerializer.swift",
    "FenceJSON+",
    "WireCoding.swift",
    "WireConversion.swift",
    "ConnectionScope+Classify.swift",
)

RETRY_PATH_MARKERS = (
    "RecoveryPolicy",
    "Reconnect",
    "ReachableDeviceScanner.swift",
    "DeviceConnection.swift",
    "ConnectionResultWaiters.swift",
    "TheHandoff.swift",
)

SILENT_CORE_PATH_MARKERS = (
    "ButtonHeist/Sources/TheInsideJob/TheBrains",
    "ButtonHeist/Sources/TheInsideJob/TheSafecracker",
    "ButtonHeist/Sources/TheInsideJob/TheStash",
    "ButtonHeist/Sources/TheInsideJob/Server",
    "ButtonHeist/Sources/TheScore",
)


@dataclass(frozen=True)
class CodeRef:
    path: str
    line: int
    text: str

    def as_json(self) -> dict[str, object]:
        return {
            "path": self.path,
            "line": self.line,
            "text": self.text,
        }


def build_report(repo_root: Path, roots: Iterable[str] = DEFAULT_SOURCE_ROOTS) -> dict[str, object]:
    """Build a fallback scorecard report.

    `fallback_code_refs` is the broad total. The narrower category counts are
    assigned by path/pattern priority and isolate where the reference appears to live.
    """
    refs_by_key: dict[str, list[CodeRef]] = {key: [] for key in REPORT_KEYS}

    for source_path in source_files(repo_root, roots):
        relative_path = source_path.relative_to(repo_root).as_posix()
        original = source_path.read_text(encoding="utf-8")
        uncommented = strip_comments(original, source_path.suffix)

        for line_number, raw_line in enumerate(uncommented.splitlines(), start=1):
            text = raw_line.strip()
            if not text:
                continue

            ref = CodeRef(path=relative_path, line=line_number, text=text)
            is_fallback_ref = bool(FALLBACK_RE.search(text))
            if is_fallback_ref:
                refs_by_key["fallback_code_refs"].append(ref)

            category = category_for(relative_path, text, is_fallback_ref)
            if category is not None:
                refs_by_key[category].append(ref)

    report: dict[str, object] = {
        key: [ref.as_json() for ref in refs]
        for key, refs in refs_by_key.items()
    }
    report["counts"] = {key: len(refs) for key, refs in refs_by_key.items()}
    return report


def source_files(repo_root: Path, roots: Iterable[str]) -> Iterable[Path]:
    for root in roots:
        root_path = repo_root / root
        if not root_path.exists():
            continue
        if root_path.is_file():
            relative_path = root_path.relative_to(repo_root).as_posix()
            if is_source_file(root_path) and relative_path not in EXCLUDED_RELATIVE_PATHS:
                yield root_path
            continue
        for path in sorted(root_path.rglob("*")):
            relative_path = path.relative_to(repo_root).as_posix()
            if (
                path.is_file()
                and is_source_file(path)
                and relative_path not in EXCLUDED_RELATIVE_PATHS
            ):
                yield path


def is_source_file(path: Path) -> bool:
    return path.suffix in SOURCE_EXTENSIONS


def category_for(relative_path: str, text: str, is_fallback_ref: bool) -> str | None:
    if is_fallback_ref and matches_path(relative_path, BOUNDARY_PATH_MARKERS):
        return "boundary_error_mapping_refs"
    if (
        matches_path(relative_path, DISPLAY_PATH_MARKERS)
        and display_default_ref(text)
        and not is_switch_default_case(text)
    ):
        return "display_default_refs"
    if matches_path(relative_path, RETRY_PATH_MARKERS) and RETRY_POLICY_RE.search(text):
        return "retry_policy_refs"
    if matches_path(relative_path, SILENT_CORE_PATH_MARKERS) and SILENT_CORE_RE.search(text):
        return "silent_core_fallback_refs"
    if is_fallback_ref:
        return "uncategorized_fallback_refs"
    return None


def matches_path(relative_path: str, markers: Iterable[str]) -> bool:
    return any(marker in relative_path for marker in markers)


def display_default_ref(text: str) -> bool:
    return bool(DISPLAY_DEFAULT_RE.search(text) or DISPLAY_FALLBACK_RE.search(text))


def is_switch_default_case(text: str) -> bool:
    return text.strip() == "default:" or text.strip().startswith("default: ")


def strip_comments(text: str, suffix: str) -> str:
    if suffix in {".swift", ".m", ".mm", ".h"}:
        return strip_slash_comments(text)
    if suffix in {".py", ".sh"}:
        return strip_hash_comments(text)
    return text


def strip_slash_comments(text: str) -> str:
    output: list[str] = []
    index = 0
    state = "code"
    interpolation_depth = 0
    block_comment_depth = 0
    raw_string_hashes = 0
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""

        if state == "code":
            raw_hashes = raw_string_hash_count(text, index)
            if raw_hashes is not None:
                raw_string_hashes = raw_hashes
                delimiter_index = index + raw_hashes
                if text.startswith('"""', delimiter_index):
                    output.append(text[index:delimiter_index] + '"""')
                    index = delimiter_index + 3
                    state = "raw_multiline_string"
                else:
                    output.append(text[index:delimiter_index] + '"')
                    index = delimiter_index + 1
                    state = "raw_string"
                continue
            if char == "/" and next_char == "/":
                index += 2
                while index < len(text) and text[index] != "\n":
                    index += 1
                continue
            if char == "/" and next_char == "*":
                state = "block_comment"
                block_comment_depth = 1
                index += 2
                continue
            if text.startswith('"""', index):
                output.append('"""')
                index += 3
                state = "multiline_string"
                continue
            output.append(char)
            if char == '"':
                state = "string"
            index += 1
            continue

        if state == "string":
            output.append(char)
            if char == "\\" and next_char == "(":
                output.append(next_char)
                interpolation_depth = 1
                index += 2
                state = "string_interpolation"
                continue
            if char == "\\" and index + 1 < len(text):
                output.append(text[index + 1])
                index += 2
                continue
            if char == '"':
                state = "code"
            index += 1
            continue

        if state == "string_interpolation":
            output.append(char)
            if char == "(":
                interpolation_depth += 1
            if char == ")":
                interpolation_depth -= 1
                if interpolation_depth == 0:
                    state = "string"
            index += 1
            continue

        if state == "multiline_string":
            if text.startswith('"""', index):
                output.append('"""')
                index += 3
                state = "code"
                continue
            output.append(char)
            index += 1
            continue

        if state == "raw_string":
            if raw_string_closes(text, index, raw_string_hashes):
                output.append('"' + ("#" * raw_string_hashes))
                index += 1 + raw_string_hashes
                state = "code"
                continue
            output.append(char)
            index += 1
            continue

        if state == "raw_multiline_string":
            if raw_multiline_string_closes(text, index, raw_string_hashes):
                output.append('"""' + ("#" * raw_string_hashes))
                index += 3 + raw_string_hashes
                state = "code"
                continue
            output.append(char)
            index += 1
            continue

        if state == "block_comment":
            if char == "\n":
                output.append("\n")
            if char == "/" and next_char == "*":
                block_comment_depth += 1
                index += 2
                continue
            if char == "*" and next_char == "/":
                block_comment_depth -= 1
                if block_comment_depth == 0:
                    state = "code"
                index += 2
            else:
                index += 1
            continue

    return "".join(output)


def raw_string_hash_count(text: str, index: int) -> int | None:
    hash_count = 0
    while index + hash_count < len(text) and text[index + hash_count] == "#":
        hash_count += 1
    if hash_count == 0:
        return None
    delimiter_index = index + hash_count
    if delimiter_index >= len(text) or text[delimiter_index] != '"':
        return None
    return hash_count


def raw_string_closes(text: str, index: int, hash_count: int) -> bool:
    return (
        text[index] == '"'
        and text[index + 1:index + 1 + hash_count] == "#" * hash_count
    )


def raw_multiline_string_closes(text: str, index: int, hash_count: int) -> bool:
    return (
        text.startswith('"""', index)
        and text[index + 3:index + 3 + hash_count] == "#" * hash_count
    )


def strip_hash_comments(text: str) -> str:
    output: list[str] = []
    index = 0
    state = "code"
    triple_delimiter = ""
    while index < len(text):
        char = text[index]

        if state == "code":
            if text.startswith('"""', index) or text.startswith("'''", index):
                triple_delimiter = text[index:index + 3]
                output.append(triple_delimiter)
                index += 3
                state = "triple_string"
                continue
            if char == "#":
                while index < len(text) and text[index] != "\n":
                    index += 1
                continue
            output.append(char)
            if char == '"':
                state = "double_string"
            elif char == "'":
                state = "single_string"
            index += 1
            continue

        if state in {"double_string", "single_string"}:
            output.append(char)
            if char == "\\" and index + 1 < len(text):
                output.append(text[index + 1])
                index += 2
                continue
            if (state == "double_string" and char == '"') or (state == "single_string" and char == "'"):
                state = "code"
            index += 1
            continue

        if state == "triple_string":
            if text.startswith(triple_delimiter, index):
                output.append(triple_delimiter)
                index += 3
                state = "code"
                continue
            output.append(char)
            index += 1
            continue

    return "".join(output)


def render_text(report: dict[str, object]) -> str:
    counts = report["counts"]
    assert isinstance(counts, dict)
    lines = [f"{key}: {counts[key]}" for key in REPORT_KEYS]
    for key in REPORT_KEYS:
        refs = report[key]
        assert isinstance(refs, list)
        if not refs:
            continue
        lines.append("")
        lines.append(key)
        for ref in refs:
            assert isinstance(ref, dict)
            lines.append(f"  {ref['path']}:{ref['line']}: {ref['text']}")
    return "\n".join(lines)


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Report fallback-related code references by category."
    )
    parser.add_argument(
        "--repo-root",
        default=Path.cwd(),
        type=Path,
        help="Repository root to scan (default: current working directory).",
    )
    parser.add_argument(
        "--root",
        action="append",
        dest="roots",
        help="Source root to scan, relative to repo root. May be passed more than once.",
    )
    parser.add_argument(
        "--format",
        choices=("json", "text"),
        default="json",
        help="Output format (default: json).",
    )
    parser.add_argument(
        "--fail-on-silent-core",
        action="store_true",
        help="Exit non-zero when silent_core_fallback_refs is non-empty.",
    )
    return parser.parse_args(argv)


def main(argv: list[str]) -> int:
    args = parse_args(argv)
    repo_root = args.repo_root.resolve()
    roots = args.roots if args.roots is not None else DEFAULT_SOURCE_ROOTS
    report = build_report(repo_root, roots)

    if args.format == "json":
        print(json.dumps(report, indent=2, sort_keys=True))
    else:
        print(render_text(report))

    if args.fail_on_silent_core and report["silent_core_fallback_refs"]:
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
