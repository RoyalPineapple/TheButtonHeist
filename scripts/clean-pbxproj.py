#!/usr/bin/env python3
"""Auto-clean common pbxproj corruption that creeps in between `tuist generate`
runs (Xcode UI edits, double-generates, etc.).

Two patterns are handled:

1. Hardcoded absolute `SRCROOT = "/Users/..."` build settings. Xcode resolves
   SRCROOT from the .xcodeproj location, so an absolute path here breaks
   builds for every other developer and CI.

2. Duplicate entries inside parenthesized list values such as
   `HEADER_SEARCH_PATHS = ( ... );` or `LD_RUNPATH_SEARCH_PATHS = ( ... );`.
   Repeated `"$(inherited)"` and repeated path entries are silently appended
   when the file is regenerated against an already-dirty state.

The cleaner is line-based and conservative: it only edits lines it recognises
and never reorders content. Idempotent: running on a clean file is a no-op.

Exit code is 0 whether or not edits were made; pass `--check` to exit non-zero
if changes would be required (useful in CI / pre-commit guards).
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ABSOLUTE_SRCROOT = re.compile(r'^\s*SRCROOT = "?/[^"]*"?;\s*$')
LIST_OPEN = re.compile(r'^\s*([A-Z_][A-Z0-9_]*)\s*=\s*\(\s*$')
LIST_CLOSE = re.compile(r'^\s*\)\s*;')

# Build settings whose values are unordered path sets — duplicates are
# meaningless and safe to dedupe. Settings like OTHER_LDFLAGS or
# OTHER_SWIFT_FLAGS use positional flag pairs (e.g. `-Xcc` followed by an
# argument) and MUST NOT be deduped.
DEDUPABLE_LISTS = frozenset({
    "FRAMEWORK_SEARCH_PATHS",
    "HEADER_SEARCH_PATHS",
    "LD_RUNPATH_SEARCH_PATHS",
    "LIBRARY_SEARCH_PATHS",
    "SYSTEM_FRAMEWORK_SEARCH_PATHS",
    "SYSTEM_HEADER_SEARCH_PATHS",
    "USER_HEADER_SEARCH_PATHS",
})


def clean(text: str) -> str:
    out: list[str] = []
    dedupe_active = False
    seen: set[str] = set()

    for line in text.splitlines(keepends=True):
        stripped = line.strip()

        if not dedupe_active and ABSOLUTE_SRCROOT.match(line):
            continue

        if not dedupe_active:
            out.append(line)
            match = LIST_OPEN.match(line)
            if match and match.group(1) in DEDUPABLE_LISTS:
                dedupe_active = True
                seen = set()
            continue

        if LIST_CLOSE.match(stripped):
            dedupe_active = False
            seen = set()
            out.append(line)
            continue

        entry = stripped.rstrip(",").strip()
        if entry and entry in seen:
            continue
        if entry:
            seen.add(entry)
        out.append(line)

    return "".join(out)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument(
        "--check",
        action="store_true",
        help="exit 1 if any file would change; do not write",
    )
    args = parser.parse_args()

    needs_change = False
    for path in args.paths:
        original = path.read_text()
        cleaned = clean(original)
        if cleaned == original:
            continue
        needs_change = True
        if args.check:
            print(f"would clean: {path}", file=sys.stderr)
        else:
            path.write_text(cleaned)
            print(f"cleaned: {path}")

    if args.check and needs_change:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
