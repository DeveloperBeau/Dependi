#!/bin/sh
# Lints every Swift file under Sources and Tests with the repository formatter settings.
set -eu
cd "$(dirname "$0")/.."
exec swift format lint --strict --recursive --configuration .swift-format Sources Tests Scripts
