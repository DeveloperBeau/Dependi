# Repository checks

## Purpose

These checks guard rules that review should not have to catch.

## Parts

- `Scripts/lint.sh` runs `swift format lint --strict` over `Sources` and `Tests`. The settings are in `.swift-format`. They enable the casing rules `AlwaysUseLowerCamelCase` and `TypeNamesShouldBeCapitalized`.
- `ForbiddenContentScanner` reads every file that git tracks or would track. It fails on a home directory path and on the git user name.
- Both checks run in `RepositoryChecksTests`.

## Data flow

1. The test finds the repository root from its own file path.
2. It asks git for the list of files that are not ignored.
3. It scans each file, or runs the lint script.

## Edge cases

- A missing file is skipped.
- Words such as `Users guide` are not flagged. Only a path with slashes is.
- Planted bad code is stored as `.swift.txt` so it is not compiled or linted.

## Tests

Each check has a test that finds a planted violation and a test that accepts similar clean text. The repository itself is the last test.
