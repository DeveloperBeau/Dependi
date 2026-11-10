#!/bin/sh
# Runs the end-to-end tests of the mutation runner. They build a small package with the real
# toolchain, so the default test run skips them. The gate runs this script when the runner or
# its tests change.
set -eu
cd "$(dirname "$0")/.."
DEPENDI_RUNNER_CHECK=1 exec swift test --filter MutationRunnerEndToEndTests
