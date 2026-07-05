#!/usr/bin/env bash
# Verify that the parser dependency has a single, auditable release contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PARSER_REPO_URL="https://github.com/RoyalPineapple/AccessibilitySnapshotBH"
PARSER_IDENTITY="accessibilitysnapshotbh"
SUBMODULE_PATH="submodules/AccessibilitySnapshotBH"
SEMVER_PATTERN='[0-9]+\.[0-9]+\.[0-9]+'

fail() {
    echo "::error::$*"
    exit 1
}

tracked_files_referencing_parser() {
    local pattern="$1"
    local file

    while IFS= read -r file; do
        [[ -n "$file" ]] || continue
        if grep -Fq "$PARSER_REPO_URL" "$file" || grep -Fqi "$PARSER_IDENTITY" "$file"; then
            printf '%s\n' "$file"
        fi
    done < <(git ls-files -- "$pattern")
}

MANIFEST_FILES=()
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    MANIFEST_FILES+=("$file")
done < <(tracked_files_referencing_parser '*Package.swift')

LOCKFILES=()
while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    LOCKFILES+=("$file")
done < <(tracked_files_referencing_parser '*Package.resolved')

[[ "${#MANIFEST_FILES[@]}" -gt 0 ]] || fail "no tracked Package.swift declares $PARSER_REPO_URL"

MANIFEST_TAGS=()
for manifest in "${MANIFEST_FILES[@]}"; do
    manifest_tags=$(grep -F "$PARSER_REPO_URL" "$manifest" \
        | grep -oE "exact:[[:space:]]*\"$SEMVER_PATTERN\"" \
        | grep -oE "$SEMVER_PATTERN" || true)

    if [[ -z "$manifest_tags" ]]; then
        fail "$manifest must pin AccessibilitySnapshotBH with exact: \"x.y.z\". Semver ranges can silently pull parser semantics that were not released with Button Heist."
    fi

    while IFS= read -r manifest_tag; do
        [[ -n "$manifest_tag" ]] || continue
        MANIFEST_TAGS+=("$manifest:$manifest_tag")
    done <<< "$manifest_tags"
done

CANONICAL_TAGS=$(printf '%s\n' "${MANIFEST_TAGS[@]}" | sed 's/^.*://' | sort -u)
CANONICAL_TAG_COUNT=$(printf '%s\n' "$CANONICAL_TAGS" | sed '/^$/d' | wc -l | tr -d '[:space:]')
if [[ "$CANONICAL_TAG_COUNT" != "1" ]]; then
    echo "::error::Tracked Package.swift files disagree on AccessibilitySnapshotBH exact tags:"
    printf '  %s\n' "${MANIFEST_TAGS[@]}"
    exit 1
fi

PACKAGE_TAG="$CANONICAL_TAGS"

SUBMODULE_SHA=$(git ls-tree HEAD "$SUBMODULE_PATH" | awk '{print $3}')
[[ -n "$SUBMODULE_SHA" ]] || fail "$SUBMODULE_PATH is not tracked as a submodule"

BRANCH_TIP=$(git ls-remote "$PARSER_REPO_URL" refs/heads/main | awk '{print $1}')
[[ -n "$BRANCH_TIP" ]] || fail "could not resolve AccessibilitySnapshotBH main branch"

TAG_SHA=$(git ls-remote "$PARSER_REPO_URL" "refs/tags/$PACKAGE_TAG^{}" | awk '{print $1}')
if [[ -z "$TAG_SHA" ]]; then
    TAG_SHA=$(git ls-remote "$PARSER_REPO_URL" "refs/tags/$PACKAGE_TAG" | awk '{print $1}')
fi

echo "AccessibilitySnapshotBH contract:"
echo "  Canonical exact tag:     $PACKAGE_TAG"
echo "  Tagged commit:           ${TAG_SHA:-<missing>}"
echo "  Submodule pin:           $SUBMODULE_SHA"
echo "  Main branch tip:         $BRANCH_TIP"
echo "  Package.swift files:     ${#MANIFEST_FILES[@]}"
echo "  Package.resolved files:  ${#LOCKFILES[@]}"

FAILED=0

if [[ -z "$TAG_SHA" ]]; then
    echo "::error::Tracked Package.swift files reference AccessibilitySnapshotBH tag $PACKAGE_TAG, but that tag does not exist."
    FAILED=1
elif [[ "$TAG_SHA" != "$SUBMODULE_SHA" ]]; then
    echo "::error::AccessibilitySnapshotBH tag $PACKAGE_TAG ($TAG_SHA) does not match submodule ($SUBMODULE_SHA). Run: ./scripts/bump-parser.sh"
    FAILED=1
fi

if [[ "$SUBMODULE_SHA" != "$BRANCH_TIP" ]]; then
    echo "::error::Submodule ($SUBMODULE_SHA) is behind AccessibilitySnapshotBH main ($BRANCH_TIP). Run: git submodule update --remote submodules/AccessibilitySnapshotBH && ./scripts/bump-parser.sh"
    FAILED=1
fi

for manifest_tag in "${MANIFEST_TAGS[@]}"; do
    manifest="${manifest_tag%%:*}"
    tag="${manifest_tag##*:}"
    if [[ "$tag" != "$PACKAGE_TAG" ]]; then
        echo "::error::$manifest pins AccessibilitySnapshotBH $tag, expected $PACKAGE_TAG"
        FAILED=1
    fi
done

if [[ "${#LOCKFILES[@]}" -gt 0 ]]; then
    LOCKFILE_PINS=$(PARSER_REPO_URL="$PARSER_REPO_URL" PARSER_IDENTITY="$PARSER_IDENTITY" python3 <<'PY'
import json
import os
import subprocess
import sys

parser_repo_url = os.environ["PARSER_REPO_URL"].rstrip("/")
parser_identity = os.environ["PARSER_IDENTITY"].lower()

result = subprocess.run(
    ["git", "ls-files", "--", "*Package.resolved"],
    check=True,
    stdout=subprocess.PIPE,
    text=True,
)

for path in result.stdout.splitlines():
    if not path:
        continue
    try:
        with open(path, encoding="utf-8") as file:
            package_resolved = json.load(file)
    except json.JSONDecodeError as error:
        print(f"::error::{path} is not valid JSON: {error}", file=sys.stderr)
        sys.exit(1)

    pins = package_resolved.get("pins")
    if pins is None and isinstance(package_resolved.get("object"), dict):
        pins = package_resolved["object"].get("pins")
    if not isinstance(pins, list):
        print(f"::error::{path} does not contain a pins array", file=sys.stderr)
        sys.exit(1)

    for pin in pins:
        if not isinstance(pin, dict):
            continue
        identity = str(pin.get("identity") or pin.get("package") or "").lower()
        location = str(pin.get("location") or "").rstrip("/")
        if identity != parser_identity and location != parser_repo_url:
            continue

        state = pin.get("state")
        if not isinstance(state, dict):
            state = {}
        version = state.get("version") or ""
        revision = state.get("revision") or ""
        print(f"{path}\t{version}\t{revision}")
PY
)

    while IFS=$'\t' read -r lockfile version revision; do
        [[ -n "$lockfile" ]] || continue
        if [[ "$version" != "$PACKAGE_TAG" ]]; then
            echo "::error::$lockfile pins AccessibilitySnapshotBH version ${version:-<none>}, expected $PACKAGE_TAG"
            FAILED=1
        fi
        if [[ -n "$TAG_SHA" && "$revision" != "$TAG_SHA" ]]; then
            echo "::error::$lockfile pins AccessibilitySnapshotBH revision ${revision:-<none>}, expected $TAG_SHA"
            FAILED=1
        fi
    done <<< "$LOCKFILE_PINS"
fi

if [[ "$FAILED" -ne 0 ]]; then
    exit "$FAILED"
fi

echo "Parser dependency contract verified for AccessibilitySnapshotBH $PACKAGE_TAG"
