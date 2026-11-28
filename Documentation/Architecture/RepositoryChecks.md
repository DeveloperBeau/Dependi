# Repository checks

## Purpose

These checks guard rules that review should not have to catch.

## Parts

- `Scripts/lint.sh` runs `swift format lint --strict` over `Sources` and `Tests`. The settings are in `.swift-format`. They enable the casing rules `AlwaysUseLowerCamelCase` and `TypeNamesShouldBeCapitalized`.
- `ForbiddenContentScanner` reads every file that git tracks or would track. It fails on a home directory path and on the git user name.
- The git user name may appear in one place only. That is a line of `NOTICE` that is exactly `Copyright <years> <name>`. The years are a four-digit year, or two four-digit years joined by a hyphen with the second not before the first. An example is `2024-2026`. The repository test names `NOTICE` as the copyright file. With no copyright file set, nothing is exempt.
- `TrackedBuildOutput` reads the git index. It fails when a tracked path has `.build` or `.build-modules` as a component. `.build` is the shared SwiftPM scratch folder. `.build-modules` is the per-target scratch folder the old gate script wrote.
- The checks run in `RepositoryChecksTests`.

## Data flow

1. The test finds the repository root from its own file path.
2. The forbidden-content check asks git for the files that are not ignored.
3. It scans each file, or runs the lint script.
4. The build-output check lists the git index with a NUL between paths. A path that was added despite the ignore rule is still listed. The check does not open the files.

## Edge cases

- A missing file is skipped.
- Words such as `Users guide` are not flagged. Only a path with slashes is.
- The git user name on another line of `NOTICE` fails, even when the copyright line is also there.
- The copyright line fails in any other file, such as `README.md`, `NOTICE.md` or `sub/NOTICE`.
- A copyright line with anything extra fails. That covers a leading space, a different case, a missing year, a `(c)` and text after the name.
- A name glued to the years fails. That covers no space, a hyphen and a tab between them.
- A malformed or reversed year range fails, such as `2026-26` or `2026-2025`.
- Every copyright line in `NOTICE` is judged on its own. Two valid lines pass. One broken line fails the file.
- Lines are split on any newline, so a `NOTICE` with CRLF line ends is read the same way.
- A home directory path is never exempt. Both home fragments fail in `NOTICE` too, even on the copyright line.
- Planted bad code is stored as `.swift.txt` so it is not compiled or linted.
- A name that only contains the scratch text is kept. `not.build` and `.build-modules-backup` are not scratch folders.
- When a path has more than one scratch folder, the check reports the first component.
- A newline listing quotes a name that contains a quote or a non-ASCII byte. The quoted text no longer has the scratch folder as its own component. The NUL list keeps the real path.

## Tests

Each check has a test that finds a planted violation and a test that accepts similar clean text. The build-output check also fuzzes paths with a seeded generator. The copyright exemption has tests for the accepted line, for the name on another line, for the line in another file, for a line with anything extra and for a home path in `NOTICE`. More tests cover the year rule, a holder made of digits, two valid lines and a broken line next to a valid one. Two seeded fuzz tests check that a valid copyright line is never flagged and that a broken one is always flagged. The repository itself is the last test.
