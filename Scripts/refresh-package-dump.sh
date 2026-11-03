#!/bin/sh
# Records the package manifest as JSON for the architecture test.
# The run uses its own scratch folder so it never waits on a build lock, and it stops after 120 seconds.
set -eu
cd "$(dirname "$0")/.."
scratch=$(mktemp -d)
trap 'rm -rf "$scratch"' EXIT
root=$(pwd)
fixtures=Tests/ArchitectureTests/Fixtures
perl -e 'alarm 120; exec @ARGV' swift package --scratch-path "$scratch" dump-package |
    sed "s|$root|\$ROOT|g" >"$fixtures/package-dump.json"
shasum -a 256 Package.swift | cut -d' ' -f1 >"$fixtures/package-dump.sha256"
