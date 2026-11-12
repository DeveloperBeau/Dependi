# Tooling

## A lint check must be tested against bad input

- **Trap:** A lint script that passes on clean code does not prove it can fail.
- **Finding:** Mutation runs showed three ways the checks could go blind. Turning off both casing rules, dropping the Linux home path fragment, and removing `--strict` each made a named test fail.
- **Rule:** Every check has a test with a planted violation and a test with similar clean input.

## Mutation results for the repository checks

| Mutation | Test that failed |
|---|---|
| Both casing rules set to false | `the formatter configuration enables both casing rules` and `a lowercase type name and an underscore name fail the strict lint` |
| Linux home path fragment removed | `a planted linux home path is found` |
| `--strict` removed from the lint script | `the lint script covers Sources and Tests recursively and ignores nothing` |

## A scratch folder is build output

- **Trap:** A per-target build writes a scratch folder. Deleting the script makes the ignore line look unused.
- **Finding:** `Scripts/build-each-target.sh` ran `swift build --scratch-path .build-modules/<target>` for each module. The speed work deleted that script and the `.build-modules/` ignore line. The folder stayed on disk. The next commit tracked 28763 files from it while it updated a fixture. Nothing in Scripts, Package.swift, Sources or Documentation reads the folder. Each target directory is a SwiftPM scratch tree. Its cache tag names Swift Package Manager, and the files are module caches, object files and SDK stat caches.
- **Rule:** Git ignores `.build` and `.build-modules`. The repository check fails when the index tracks a path with either name as a component.

The check lives in the test target, so the mutation runner does not cover it. Removing `.build-modules` from the scratch folder set was run by hand. `a planted scratch path is build output` failed.

| Mutation | Test that failed |
|---|---|
| `.build-modules` removed from the scratch folder set | `a planted scratch path is build output` |
