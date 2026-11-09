#!/bin/sh
# The full gate: lint, a fresh package dump, build, tests and a build of each module on its own.
set -eu
cd "$(dirname "$0")/.."
sh Scripts/lint.sh
# Regenerate the recorded package dump. A committed fixture that differs from the regenerated one fails the gate.
sh Scripts/refresh-package-dump.sh
git diff --exit-code -- Tests/ArchitectureTests/Fixtures
swift build --build-tests
swift test
sh Scripts/build-each-target.sh
