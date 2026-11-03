#!/bin/sh
# Builds every module on its own, so a module that needs another module's private files fails here.
set -eu
cd "$(dirname "$0")/.."
for directory in Sources/*/; do
    [ -d "$directory" ] || continue
    name=$(basename "$directory")
    perl -e 'alarm 600; exec @ARGV' swift build --target "$name" --scratch-path ".build-modules/$name"
done
