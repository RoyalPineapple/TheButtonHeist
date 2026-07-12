#!/usr/bin/env bash
# Guard source-level house rules that the compiler and API diff do not own.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUMPER_BOWLING_REPOSITORY="${BUMPER_BOWLING_REPOSITORY:-https://github.com/RoyalPineapple/BumperBowling.git}"
BUMPER_BOWLING_REVISION="${BUMPER_BOWLING_REVISION:-655ccf729898b4dc17b84238645befceb8863ec3}"
BUMPER_BOWLING_CHECKOUT="${BUMPER_BOWLING_CHECKOUT:-$REPO_ROOT/.build/bumper-bowling}"
BUMPER_CACHE_DIR="${BUMPER_CACHE_DIR:-$REPO_ROOT/.build/bumper-cache}"
export BUMPER_CACHE_DIR

fetch_bumper_revision() {
    local checkout="$1"

    if ! git -C "$checkout" fetch --depth=1 origin "$BUMPER_BOWLING_REVISION"; then
        git -C "$checkout" fetch --depth=1 origin main
    fi
    git -C "$checkout" checkout --detach "$BUMPER_BOWLING_REVISION" >/dev/null
}

ensure_bumper_checkout() {
    if [[ -d "$BUMPER_BOWLING_CHECKOUT/.git" ]]; then
        fetch_bumper_revision "$BUMPER_BOWLING_CHECKOUT"
        return
    fi

    if [[ -e "$BUMPER_BOWLING_CHECKOUT" ]]; then
        echo "Error: $BUMPER_BOWLING_CHECKOUT exists but is not a git checkout" >&2
        exit 1
    fi

    git clone --filter=blob:none --no-checkout "$BUMPER_BOWLING_REPOSITORY" "$BUMPER_BOWLING_CHECKOUT"
    fetch_bumper_revision "$BUMPER_BOWLING_CHECKOUT"
}

run_bumper() {
    if [[ -n "${BUMPER:-}" ]]; then
        "$BUMPER" lint "$REPO_ROOT" --fail-on error
        return
    fi

    if [[ -n "${BUMPER_BOWLING_PACKAGE_PATH:-}" ]]; then
        swift run --package-path "$BUMPER_BOWLING_PACKAGE_PATH" bumper lint "$REPO_ROOT" --fail-on error
        return
    fi

    ensure_bumper_checkout
    swift run --package-path "$BUMPER_BOWLING_CHECKOUT" bumper lint "$REPO_ROOT" --fail-on error
}

check_platform_boundary_sendable() {
    python3 - "$REPO_ROOT" <<'PY'
import pathlib
import re
import sys

repo_root = pathlib.Path(sys.argv[1])
boundary_prefix = "ButtonHeist/Sources/TheInsideJob/"
unchecked_pattern = re.compile(r"@unchecked\s+Sendable\b")
string_pattern = re.compile(r'"(?:\\.|[^"\\])*"')


def without_comments_and_strings(line, block_comment):
    output = []
    index = 0
    while index < len(line):
        if block_comment:
            end = line.find("*/", index)
            if end == -1:
                return "".join(output), True
            block_comment = False
            index = end + 2
        elif line.startswith("/*", index):
            block_comment = True
            index += 2
        elif line.startswith("//", index):
            break
        else:
            output.append(line[index])
            index += 1
    return string_pattern.sub('""', "".join(output)), block_comment


violations = []
for path in sorted((repo_root / "ButtonHeist/Sources").rglob("*.swift")):
    relative_path = path.relative_to(repo_root).as_posix()
    block_comment = False
    for line_number, line in enumerate(path.read_text().splitlines(), start=1):
        code, block_comment = without_comments_and_strings(line, block_comment)
        if unchecked_pattern.search(code) and not relative_path.startswith(boundary_prefix):
            violations.append(
                f"{relative_path}:{line_number}: "
                "UIKit/ObjC @unchecked Sendable outside TheInsideJob platform boundary"
            )

if violations:
    print("\n".join(violations), file=sys.stderr)
    sys.exit(1)
PY
}

platform_boundary_status=0
check_platform_boundary_sendable || platform_boundary_status=$?

bumper_status=0
run_bumper || bumper_status=$?

if ((platform_boundary_status != 0)); then
    exit "$platform_boundary_status"
fi
exit "$bumper_status"
