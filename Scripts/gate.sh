#!/bin/sh
# The full gate: lint, build, tests and a build of each module on its own.
set -eu
cd "$(dirname "$0")/.."
sh Scripts/lint.sh
swift build --build-tests
swift test
sh Scripts/build-each-target.sh
