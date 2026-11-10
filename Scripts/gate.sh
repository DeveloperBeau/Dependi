#!/bin/sh
# The full gate: lint, a fresh package dump, build and tests.
set -eu
cd "$(dirname "$0")/.."
sh Scripts/lint.sh
# Regenerate the recorded package dump. A committed fixture that differs from the regenerated one fails the gate.
sh Scripts/refresh-package-dump.sh
git diff --exit-code -- Tests/ArchitectureTests/Fixtures
swift build --build-tests
swift test
