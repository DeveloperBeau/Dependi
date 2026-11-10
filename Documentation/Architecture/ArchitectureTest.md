# Architecture test

## Purpose

The architecture test fails when code breaks a ring rule or a source rule. A tool checks the rules so review does not have to.

## Parts

- `RingRules` holds the ring map and the table of which ring may use which.
- `PackageDump` reads a recorded copy of `swift package dump-package` output.
- `ImportScanner` finds imports in source text. `SwiftSourceLexer` removes comments and strings first.
- `SourceRules` holds the rules that read one file.
- `ArchitectureChecker` applies every rule and returns violations.

## Rules checked

1. Declared target dependencies respect the rings.
2. No target declares an external product.
3. Imports respect the rings, are declared, and are known.
4. Production code never imports `DependiTestSupport`.
5. Every module and source folder is in the ring map.
6. Every target uses Swift 6 mode and `ExistentialAny`.
7. A file declares one top-level public type. Indirect enums, public extensions and a second type on the same line count.
8. Every public declaration has a `///` doc comment. A block comment does not count.
9. No initializer or static function gives a parameter a default that builds an object. Allowed defaults are literals, `nil`, enumeration cases and a short list of value types.
10. A module has at most one error enumeration. The domain uses typed throws only.
11. Production source holds no sandbox bypass flag, shell call or fixed shell path.
12. Production source holds no hidden global state: no stored `static var`, no `nonisolated(unsafe)` and no global `var`.

Beside the source rules, a repository test checks that every `@Suite` in `Tests` and `Contract/Tests` declares a `.timeLimit`.

## Data flow

1. `Scripts/refresh-package-dump.sh` records the manifest into `Tests/ArchitectureTests/Fixtures/package-dump.json`. It replaces the machine path with `$ROOT` and stores a hash of `Package.swift` next to it.
2. The test compares that hash with `Package.swift`. A mismatch fails with the command to run. Both files are committed, so the test alone cannot catch a hand edit of both. The gate runs the refresh script again and fails on `git diff --exit-code` of the fixtures.
3. The test reads every Swift file under `Sources` and runs `ArchitectureChecker`.

## Why the dump is recorded

`swift test` holds a lock on `.build`. A nested `swift package` call on the same package can wait on that lock and hang. The recorded dump keeps the default test run fast, safe from the lock and free of real tool calls.

## Gate

`Scripts/gate.sh` runs lint, the package dump check, a build and the tests. It runs `Scripts/runner-check.sh` only when the mutation runner changed. Rule 3 finds a module that imports a sibling it does not declare. A shared build folder can hide that error from the compiler, so the gate does not build each module on its own.

## Tests

Every rule has a planted violation and a clean case. The undeclared import rule also has these cases: an import in a comment or a string, a `@testable` import, an import inside `#if canImport`, a module that imports itself and a sibling that the module declares only as a product. Import forms are fuzzed with a seeded generator. Decoys in comments and strings must never count as imports.
