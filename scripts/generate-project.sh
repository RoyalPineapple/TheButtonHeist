#!/usr/bin/env bash
# Canonical entry point for regenerating Xcode projects.
#
# Wraps `tuist install && tuist generate --no-open` and then auto-cleans the
# generated pbxproj files (see scripts/clean-pbxproj.py for what gets removed).
# Use this instead of calling tuist directly so dirty pbxproj patterns
# (hardcoded SRCROOT, duplicated header search paths) never reach a commit.

set -euo pipefail

cd "$(dirname "$0")/.."

tuist install

set +e
tuist generate --no-open
generate_status=$?
set -e

scripts/clean-generated-projects.sh

exit "$generate_status"
