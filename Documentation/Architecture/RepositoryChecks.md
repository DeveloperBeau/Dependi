# Repository checks

## Purpose

These checks guard rules that review should not have to catch.

## Parts

- `Scripts/lint.sh` runs `swift format lint --strict` over `Sources` and `Tests`. The settings are in `.swift-format`. They enable the casing rules `AlwaysUseLowerCamelCase` and `TypeNamesShouldBeCapitalized`.
- `ForbiddenContentScanner` reads every file that git tracks or would track. It fails on a home directory path and on the git user name.
- `TrackedBuildOutput` reads the git index. It fails when a tracked path has `.build` or `.build-modules` as a component. `.build` is the shared SwiftPM scratch folder. `.build-modules` is the per-target scratch folder the old gate script wrote.
- The checks run in `RepositoryChecksTests`.

## Data flow

1. The test finds the repository root from its own file path.
2. The forbidden-content check asks git for the files that are not ignored.
3. It scans each file, or runs the lint script.
4. The build-output check lists the git index. A path that was added despite the ignore rule is still listed. The check does not open the files.

## Edge cases

- A missing file is skipped.
- Words such as `Users guide` are not flagged. Only a path with slashes is.
- Planted bad code is stored as `.swift.txt` so it is not compiled or linted.
- A name that only contains the scratch text is kept. `not.build` and `.build-modules-backup` are not scratch folders.
- When a path has more than one scratch folder, the check reports the first component.

## Tests

Each check has a test that finds a planted violation and a test that accepts similar clean text. The build-output check also fuzzes paths with a seeded generator. The repository itself is the last test.
