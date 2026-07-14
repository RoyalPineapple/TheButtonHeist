#!/usr/bin/env bash
# Update release-version mirrors from the canonical TheScore version declaration.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$REPO_ROOT"

# shellcheck source=scripts/release-contract.sh
source "$SCRIPT_DIR/release-contract.sh"

SEMVER_REGEX='^[0-9]+\.[0-9]+\.[0-9]+$'

[[ $# -eq 1 ]] || { echo "Usage: $0 <version>" >&2; exit 1; }
NEW_VERSION="$1"
[[ "$NEW_VERSION" =~ $SEMVER_REGEX ]] \
    || { echo "Error: '$NEW_VERSION' is not MAJOR.MINOR.PATCH" >&2; exit 1; }

CURRENT_VERSION=$(buttonheist_code_version)
[[ "$CURRENT_VERSION" =~ $SEMVER_REGEX ]] \
    || { echo "Error: canonical version '$CURRENT_VERSION' is not MAJOR.MINOR.PATCH" >&2; exit 1; }

RELEASE_MIRROR=$(tr -d '[:space:]' < "$BUTTONHEIST_RELEASE_VERSION_FILE")
FORMULA_MIRROR=$(grep -E '^[[:space:]]*version "[^"]+"' "$BUTTONHEIST_FORMULA_TEMPLATE" \
    | sed -E 's/.*"([^"]+)".*/\1/')
FORMULA_MIRROR_COUNT=$(printf '%s\n' "$FORMULA_MIRROR" | sed '/^$/d' | wc -l | tr -d '[:space:]')
[[ "$FORMULA_MIRROR_COUNT" == "1" ]] \
    || { echo "Error: $BUTTONHEIST_FORMULA_TEMPLATE must contain exactly one version mirror" >&2; exit 1; }
[[ "$RELEASE_MIRROR" == "$CURRENT_VERSION" ]] \
    || { echo "Error: $BUTTONHEIST_RELEASE_VERSION_FILE ($RELEASE_MIRROR) != canonical version $CURRENT_VERSION" >&2; exit 1; }
[[ "$FORMULA_MIRROR" == "$CURRENT_VERSION" ]] \
    || { echo "Error: $BUTTONHEIST_FORMULA_TEMPLATE ($FORMULA_MIRROR) != canonical version $CURRENT_VERSION" >&2; exit 1; }

TMP_DIR=$(mktemp -d)
FILES=(
    "$BUTTONHEIST_CODE_VERSION_FILE"
    "$BUTTONHEIST_RELEASE_VERSION_FILE"
    "$BUTTONHEIST_FORMULA_TEMPLATE"
)
UPDATED=false
cleanup() {
    local status=$?
    if [[ "$status" -ne 0 && "$UPDATED" == true ]]; then
        for file in "${FILES[@]}"; do
            cp "$TMP_DIR/original/$file" "$file"
        done
    fi
    rm -rf "$TMP_DIR"
    exit "$status"
}
trap cleanup EXIT

for file in "${FILES[@]}"; do
    mkdir -p "$TMP_DIR/original/$(dirname "$file")" "$TMP_DIR/updated/$(dirname "$file")"
    cp "$file" "$TMP_DIR/original/$file"
done

CURRENT_PATTERN=${CURRENT_VERSION//./\\.}
sed "s/buttonHeistVersion = \"$CURRENT_PATTERN\"/buttonHeistVersion = \"$NEW_VERSION\"/" \
    "$BUTTONHEIST_CODE_VERSION_FILE" > "$TMP_DIR/updated/$BUTTONHEIST_CODE_VERSION_FILE"
printf '%s\n' "$NEW_VERSION" > "$TMP_DIR/updated/$BUTTONHEIST_RELEASE_VERSION_FILE"
sed "s/version \"$CURRENT_PATTERN\"/version \"$NEW_VERSION\"/" \
    "$BUTTONHEIST_FORMULA_TEMPLATE" > "$TMP_DIR/updated/$BUTTONHEIST_FORMULA_TEMPLATE"

UPDATED=true
for file in "${FILES[@]}"; do
    cp "$TMP_DIR/updated/$file" "$file"
done

"$SCRIPT_DIR/validate-release-contract.sh"
echo "Version: $CURRENT_VERSION -> $NEW_VERSION"
