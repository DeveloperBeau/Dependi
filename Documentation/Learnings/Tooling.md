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

The check lives in the test target, so the mutation runner does not cover it. Both mutations below were run by hand. The listing change does not touch the folder set, and removing `.build-modules` from that set still made `a planted scratch path is build output` fail.

## A quoted index line hides the folder

- **Trap:** `git ls-files` without `-z` quotes a path that contains a quote, a backslash or a non-ASCII byte when `core.quotePath` is on. The line starts with a quote, so the first component is not the scratch folder.
- **Finding:** A temporary index held `.build/a"b.o` and `.build/ü.o`. With quoting on, the newline listing was `".build/a\"b.o"` and `".build/\303\274.o"`. Splitting that listing on newlines reported no scratch folder. `git ls-files -z` split on NUL returned the real paths, and the check reported both. Removing `-z` made `a scratch file with a quote or a non-ascii name is build output` fail.
- **Rule:** Read the index with `git ls-files -z` and split on NUL.

| Mutation | Test that failed |
|---|---|
| `.build-modules` removed from the scratch folder set | `a planted scratch path is build output` |
| `-z` removed from the index listing | `a scratch file with a quote or a non-ascii name is build output` |

## A test repository still reads the developer's git config

- **Trap:** `git add -f` gets past an excludes file, and `git ls-files -z` does not quote names. A global attributes file can still attach a required clean filter, and that filter runs during add.
- **Finding:** These global settings left the `add -f` and `ls-files -z` paths unchanged: `core.excludesFile`, `core.quotePath`, `core.ignoreCase`, `core.sparseCheckout`, `index.sparse`, `init.defaultBranch`, `core.hooksPath`, `safe.directory`, `user.useConfigOnly`, `core.precomposeUnicode`, `core.protectNTFS`, `core.protectHFS`, `core.fsmonitor`, `alias.add`, `alias.ls-files`, `core.worktree`, `core.autocrlf`, `i18n.logOutputEncoding` and `core.bare`. A required clean filter on every file made `git add -f` exit 1. Clearing global and system config made that add exit 0. Removing the clearing assignments made `a global clean filter does not hide scratch paths` fail.
- **Rule:** The temporary index forces the add and clears global and system config. `-f` and `-z` do not cover a clean filter.
