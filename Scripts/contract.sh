#!/bin/sh
# Runs the contract tests against the real toolchain. They take several minutes because one test
# builds Dependi from source through the wrapper script.
set -eu
cd "$(dirname "$0")/.."
exec swift test --package-path Contract
