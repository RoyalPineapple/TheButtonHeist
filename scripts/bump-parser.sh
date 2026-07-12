#!/usr/bin/env bash
# Align every AccessibilitySnapshotBH dependency projection with the checked-out submodule.
#
# The root Package.swift exact pin is canonical. This script updates the other
# manifests and tracked lockfiles as one working-tree transaction. The caller
# owns the commit so parser and Button Heist release changes cannot be pushed
# separately.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

PARSER_REPO_URL="https://github.com/RoyalPineapple/AccessibilitySnapshotBH"
PARSER_IDENTITY="accessibilitysnapshotbh"
SUBMODULE_DIR="submodules/AccessibilitySnapshotBH"
ROOT_MANIFEST="Package.swift"
SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'

DRY_RUN=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Error: unknown flag '$1'"; exit 1 ;;
    esac
done

fail() {
    echo "Error: $*" >&2
    exit 1
}

exact_parser_pin() {
    local manifest="$1"
    grep -F "$PARSER_REPO_URL" "$manifest" \
        | grep -oE 'exact:[[:space:]]*"[0-9]+\.[0-9]+\.[0-9]+"' \
        | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' || true
}

tracked_parser_files() {
    local pattern="$1"
    local file

    while IFS= read -r file; do
        [[ -f "$file" ]] || continue
        if grep -Fq "$PARSER_REPO_URL" "$file" || grep -Fqi "$PARSER_IDENTITY" "$file"; then
            printf '%s\n' "$file"
        fi
    done < <(git ls-files -- "$pattern")
}

[[ -d "$SUBMODULE_DIR/.git" || -f "$SUBMODULE_DIR/.git" ]] \
    || fail "submodule not initialized at $SUBMODULE_DIR; run git submodule update --init --recursive"

CURRENT_PIN=$(exact_parser_pin "$ROOT_MANIFEST")
CURRENT_PIN_COUNT=$(printf '%s\n' "$CURRENT_PIN" | sed '/^$/d' | wc -l | tr -d '[:space:]')
[[ "$CURRENT_PIN_COUNT" == "1" ]] \
    || fail "$ROOT_MANIFEST must contain exactly one AccessibilitySnapshotBH exact pin"
[[ "$CURRENT_PIN" =~ $SEMVER_REGEX ]] || fail "$ROOT_MANIFEST parser pin is not semver: $CURRENT_PIN"

MANIFEST_FILES=()
while IFS= read -r manifest; do
    [[ -n "$manifest" ]] || continue
    MANIFEST_FILES+=("$manifest")
    manifest_pin=$(exact_parser_pin "$manifest")
    manifest_pin_count=$(printf '%s\n' "$manifest_pin" | sed '/^$/d' | wc -l | tr -d '[:space:]')
    [[ "$manifest_pin_count" == "1" ]] \
        || fail "$manifest must contain exactly one AccessibilitySnapshotBH exact pin"
    [[ "$manifest_pin" == "$CURRENT_PIN" ]] \
        || fail "$manifest pins AccessibilitySnapshotBH $manifest_pin; root $ROOT_MANIFEST pins $CURRENT_PIN"
done < <(tracked_parser_files '*Package.swift')

LOCKFILES=()
while IFS= read -r lockfile; do
    [[ -n "$lockfile" ]] || continue
    LOCKFILES+=("$lockfile")
done < <(tracked_parser_files '*Package.resolved')

SUBMODULE_SHA=$(git -C "$SUBMODULE_DIR" rev-parse HEAD)
git -C "$SUBMODULE_DIR" fetch origin main --tags --quiet

TARGET_TAG=$(git -C "$SUBMODULE_DIR" tag -l --points-at "$SUBMODULE_SHA" --sort=-v:refname \
    | grep -E "$SEMVER_REGEX" \
    | head -1 || true)

if [[ -z "$TARGET_TAG" ]]; then
    BRANCH_TIP=$(git -C "$SUBMODULE_DIR" rev-parse origin/main)
    [[ "$SUBMODULE_SHA" == "$BRANCH_TIP" ]] || fail "AccessibilitySnapshotBH submodule ${SUBMODULE_SHA:0:8} is untagged and is not parser origin/main ${BRANCH_TIP:0:8}"

    LATEST_TAG=$(git -C "$SUBMODULE_DIR" tag -l --sort=-v:refname \
        | grep -E "$SEMVER_REGEX" \
        | head -1 || true)
    [[ -n "$LATEST_TAG" ]] || fail "no semver tags found on AccessibilitySnapshotBH"

    IFS='.' read -r MAJOR MINOR _ <<< "$LATEST_TAG"
    TARGET_TAG="${MAJOR}.$((MINOR + 1)).0"

    if [[ "$DRY_RUN" == false ]]; then
        git -C "$SUBMODULE_DIR" tag "$TARGET_TAG" "$SUBMODULE_SHA"
        git -C "$SUBMODULE_DIR" push origin "$TARGET_TAG"
        echo "Tagged AccessibilitySnapshotBH $TARGET_TAG on ${SUBMODULE_SHA:0:8}"
    fi
fi

echo "AccessibilitySnapshotBH: $CURRENT_PIN -> $TARGET_TAG (${SUBMODULE_SHA:0:8})"

if [[ "$DRY_RUN" == true ]]; then
    printf 'Would validate and align: %s\n' "${MANIFEST_FILES[*]} ${LOCKFILES[*]}"
    exit 0
fi

TMP_DIR=$(mktemp -d)
UPDATED=false
cleanup() {
    local status=$?
    if [[ "$status" -ne 0 && "$UPDATED" == true ]]; then
        for file in "${MANIFEST_FILES[@]}" "${LOCKFILES[@]}"; do
            cp "$TMP_DIR/original/$file" "$file"
        done
    fi
    rm -rf "$TMP_DIR"
    exit "$status"
}
trap cleanup EXIT

for file in "${MANIFEST_FILES[@]}" "${LOCKFILES[@]}"; do
    mkdir -p "$TMP_DIR/original/$(dirname "$file")" "$TMP_DIR/updated/$(dirname "$file")"
    cp "$file" "$TMP_DIR/original/$file"
    cp "$file" "$TMP_DIR/updated/$file"
done

for manifest in "${MANIFEST_FILES[@]}"; do
    awk -v repo="$PARSER_REPO_URL" -v old="$CURRENT_PIN" -v new="$TARGET_TAG" '
        index($0, repo) {
            needle = "exact: \"" old "\""
            replacement = "exact: \"" new "\""
            if (index($0, needle) > 0) {
                sub(needle, replacement)
                replacements += 1
            }
        }
        { print }
        END { if (replacements != 1) exit 42 }
    ' "$manifest" > "$TMP_DIR/updated/$manifest" \
        || fail "could not replace the single parser pin in $manifest"
done

LOCKFILE_PINS=$(LOCKFILES_JOINED="$(printf '%s\n' "${LOCKFILES[@]}")" \
    PARSER_REPO_URL="$PARSER_REPO_URL" PARSER_IDENTITY="$PARSER_IDENTITY" python3 <<'PY'
import json
import os
import sys

repo = os.environ["PARSER_REPO_URL"].rstrip("/")
identity = os.environ["PARSER_IDENTITY"].lower()

for path in os.environ["LOCKFILES_JOINED"].splitlines():
    if not path:
        continue
    with open(path, encoding="utf-8") as file:
        document = json.load(file)
    pins = document.get("pins")
    if pins is None and isinstance(document.get("object"), dict):
        pins = document["object"].get("pins")
    matches = []
    for pin in pins or []:
        pin_identity = str(pin.get("identity") or pin.get("package") or "").lower()
        location = str(pin.get("location") or pin.get("repositoryURL") or "").rstrip("/")
        if pin_identity == identity or location == repo:
            state = pin.get("state") or {}
            matches.append((state.get("version") or "", state.get("revision") or ""))
    if len(matches) != 1:
        print(f"Error: {path} must contain exactly one parser pin, found {len(matches)}", file=sys.stderr)
        sys.exit(1)
    version, revision = matches[0]
    print(f"{path}\t{version}\t{revision}")
PY
)

while IFS=$'\t' read -r lockfile old_version old_revision; do
    [[ -n "$lockfile" ]] || continue
    [[ "$old_version" == "$CURRENT_PIN" ]] \
        || fail "$lockfile pins parser version $old_version, expected root pin $CURRENT_PIN"
    [[ -n "$old_revision" ]] || fail "$lockfile parser pin has no revision"

    version_count=$(grep -Fc "\"version\" : \"$old_version\"" "$lockfile")
    revision_count=$(grep -Fc "\"revision\" : \"$old_revision\"" "$lockfile")
    [[ "$version_count" == "1" && "$revision_count" == "1" ]] \
        || fail "$lockfile parser version/revision is not uniquely replaceable"

    sed -e "s/\"version\" : \"$old_version\"/\"version\" : \"$TARGET_TAG\"/" \
        -e "s/\"revision\" : \"$old_revision\"/\"revision\" : \"$SUBMODULE_SHA\"/" \
        "$lockfile" > "$TMP_DIR/updated/$lockfile"
done <<< "$LOCKFILE_PINS"

UPDATED=true
for file in "${MANIFEST_FILES[@]}" "${LOCKFILES[@]}"; do
    cp "$TMP_DIR/updated/$file" "$file"
done

"$SCRIPT_DIR/check-parser-contract.sh"
echo "Updated parser dependency projections; commit them with the owning Button Heist change."
