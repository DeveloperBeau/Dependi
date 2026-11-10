#!/bin/sh
# The full gate: lint, a fresh package dump, build and tests. The end-to-end runner check runs
# only when the runner or its tests differ from the base branch, because it builds a package.
set -eu
cd "$(dirname "$0")/.."
sh Scripts/lint.sh
# Regenerate the recorded package dump. A committed fixture that differs from the regenerated one fails the gate.
sh Scripts/refresh-package-dump.sh
git diff --exit-code -- Tests/ArchitectureTests/Fixtures
swift build --build-tests
swift test
# Without a base branch the gate cannot see what changed, so it runs the check.
base=$(git merge-base HEAD "${GATE_BASE:-origin/main}" 2>/dev/null || true)
if [ -z "$base" ] ||
    [ -n "$(git diff --name-only "$base" -- Scripts/mutate.swift Tests/MutationRunnerTests)" ]; then
    sh Scripts/runner-check.sh
fi
