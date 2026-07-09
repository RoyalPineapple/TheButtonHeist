#!/usr/bin/env bash
# Guard source-level API shape that Swift's API diff reports too late.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

python3 - "$REPO_ROOT" <<'PY'
import json
import pathlib
import re
import sys

repo_root = pathlib.Path(sys.argv[1])
source_roots = [
    repo_root / "ButtonHeist/Sources",
    repo_root / "ButtonHeistCLI/Sources",
    repo_root / "ButtonHeistMCP/Sources",
]
top_level_typealias_allowlist = {
    repo_root / "ButtonHeist/Sources/ButtonHeistDSL/ButtonHeistDSL.swift"
}

access_pattern = re.compile(r"^\s*(public|package)\b")
top_level_typealias_pattern = re.compile(r"^\s*(public|package)\s+typealias\b")
top_level_selector_shortcut_pattern = re.compile(
    r"^\s*(public|package)\s+func\s+(predicateCandidates|minimumUniquePredicate)\b"
)
declaration_name_pattern = re.compile(r"\b(?:func|var|let|typealias)\s+`?([A-Za-z_][A-Za-z0-9_]*)`?")
compatibility_name_pattern = re.compile(
    r"(^legacy|^compat(?!ible)|^compatibility|^deprecated|Legacy|Compat(?!ible)|Compatibility|Deprecated)"
)


def strip_comments(lines):
    stripped_lines = []
    in_block = False
    for line in lines:
        stripped = []
        index = 0
        while index < len(line):
            if in_block:
                end = line.find("*/", index)
                if end == -1:
                    index = len(line)
                else:
                    in_block = False
                    index = end + 2
            elif line.startswith("/*", index):
                in_block = True
                index += 2
            elif line.startswith("//", index):
                break
            else:
                stripped.append(line[index])
                index += 1
        stripped_lines.append("".join(stripped))
    return stripped_lines


def collect_declaration(lines, start):
    parts = []
    for line in lines[start:start + 16]:
        stripped = line.strip()
        if not stripped:
            continue
        parts.append(stripped)
        if "{" in stripped or "=" in stripped:
            break
    return " ".join(parts)


def matching_paren(text, open_index):
    depth = 0
    for index in range(open_index, len(text)):
        if text[index] == "(":
            depth += 1
        elif text[index] == ")":
            depth -= 1
            if depth == 0:
                return index
    return None


def before_boundary(text):
    depth = 0
    for index, character in enumerate(text):
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth = max(0, depth - 1)
        elif depth == 0 and character in "={":
            return text[:index]
    return text


def is_tuple_type(text):
    text = text.strip()
    if not text.startswith("("):
        return False
    close_index = matching_paren(text, 0)
    if close_index is None:
        return False
    if text[close_index + 1:].lstrip().startswith("->"):
        return False

    content = text[1:close_index]
    depth = 0
    has_comma = False
    has_colon = False
    has_top_level_arrow = False
    index = 0
    while index < len(content):
        character = content[index]
        if character in "([{":
            depth += 1
        elif character in ")]}":
            depth = max(0, depth - 1)
        elif depth == 0:
            if content.startswith("->", index):
                has_top_level_arrow = True
                index += 1
            elif character == ",":
                has_comma = True
            elif character == ":":
                has_colon = True
        index += 1
    return (has_comma or has_colon) and not has_top_level_arrow


def function_return_type(declaration):
    match = re.search(r"\b(?:func|subscript)\b", declaration)
    if not match:
        return None

    open_index = declaration.find("(", match.end())
    if open_index == -1:
        return None
    close_index = matching_paren(declaration, open_index)
    if close_index is None:
        return None

    tail = before_boundary(declaration[close_index + 1:])
    arrow_index = tail.find("->")
    return None if arrow_index == -1 else tail[arrow_index + 2:]


def property_type(declaration):
    match = re.search(r"\b(?:let|var)\s+`?[A-Za-z_][A-Za-z0-9_]*`?\s*:", declaration)
    return None if not match else before_boundary(declaration[match.end():])


violations = []
for source_root in source_roots:
    for path in sorted(source_root.rglob("*.swift")):
        raw_lines = path.read_text().splitlines()
        lines = strip_comments(raw_lines)
        depth = 0
        pending_deprecated = None

        for index, line in enumerate(lines):
            stripped = line.strip()
            line_number = index + 1
            display_line = raw_lines[index].strip()

            if stripped.startswith("@available") and "deprecated" in stripped:
                pending_deprecated = (line_number, display_line)
                continue
            if stripped.startswith("@"):
                continue

            if depth == 0 and top_level_typealias_pattern.match(line) and path not in top_level_typealias_allowlist:
                violations.append((path, line_number, "exported top-level typealias outside ButtonHeistDSL facade", display_line))
            if depth == 0 and top_level_selector_shortcut_pattern.match(line):
                violations.append((path, line_number, "exported top-level minimum predicate selector shortcut", display_line))

            if access_pattern.match(line):
                declaration = collect_declaration(lines, index)
                declaration_name = declaration_name_pattern.search(declaration)
                return_type = function_return_type(declaration)
                stored_type = property_type(declaration)

                if pending_deprecated is not None:
                    violations.append((path, line_number, "exported deprecated compatibility helper", display_line))
                    pending_deprecated = None
                if declaration_name and compatibility_name_pattern.search(declaration_name.group(1)):
                    violations.append((path, line_number, "exported compatibility/legacy helper name", display_line))
                if return_type and is_tuple_type(return_type):
                    violations.append((path, line_number, "exported tuple return type", display_line))
                if stored_type and is_tuple_type(stored_type):
                    violations.append((path, line_number, "exported tuple property type", display_line))
            elif stripped:
                pending_deprecated = None

            depth += line.count("{") - line.count("}")
            depth = max(0, depth)

if violations:
    for path, line_number, reason, line in violations:
        relative_path = path.relative_to(repo_root)
        print(f"{relative_path}:{line_number}: {reason}: {line}", file=sys.stderr)
    sys.exit(1)

fixture_violations = []
fixture_root = repo_root / "tests/fixtures"


def scan_json_fixture(value, path, trail):
    if isinstance(value, dict):
        for key, child in value.items():
            child_trail = [*trail, key]
            if key == "match" and isinstance(child, str):
                fixture_violations.append((path, ".".join(child_trail), child))
            scan_json_fixture(child, path, child_trail)
    elif isinstance(value, list):
        for index, child in enumerate(value):
            scan_json_fixture(child, path, [*trail, f"[{index}]"])


if fixture_root.exists():
    for path in sorted(fixture_root.rglob("*.json")):
        try:
            scan_json_fixture(json.loads(path.read_text()), path, [])
        except json.JSONDecodeError as error:
            relative_path = path.relative_to(repo_root)
            print(f"{relative_path}: invalid JSON fixture: {error}", file=sys.stderr)
            sys.exit(1)

if fixture_violations:
    for path, trail, observed in fixture_violations:
        relative_path = path.relative_to(repo_root)
        print(
            f"{relative_path}: raw StringMatch fixture value at {trail}: {observed!r}; "
            'use {"mode":"exact","value":...}',
            file=sys.stderr,
        )
    sys.exit(1)
PY
