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
tuist generate --no-open

find . \
    -name 'project.pbxproj' \
    -not -path './Tuist/.build/*' \
    -not -path './submodules/*' \
    -not -path './.context/*' \
    -print0 \
    | xargs -0 python3 scripts/clean-pbxproj.py
