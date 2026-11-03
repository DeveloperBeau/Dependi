# Architecture checks

## A nested SwiftPM call inside a test can hang

- **Trap:** The architecture test needs the declared dependencies, and the obvious way is to run `swift package dump-package` from the test.
- **Finding:** `swift test` holds a lock on `.build`. A nested call on the same package waits on that lock. A trial with a separate scratch path finished in under a second.
- **Rule:** Tests never run SwiftPM on the package under test. The test reads a recorded dump. A script refreshes it with its own scratch path and a time limit.

## A recorded dump carries a machine path

- **Trap:** The dump holds the absolute path of the package root. Committing it breaks the no-path rule.
- **Finding:** The refresh script replaces the path with `$ROOT`. A test fails if a home path appears in the file.
- **Rule:** Scrub recorded tool output before it enters the repository.

## A name heuristic needs a false-positive test

- **Trap:** The check for a collaborator with a default value treats a type that ends in `ing` as a collaborator. `String` ends in `ing`.
- **Finding:** The test for plain defaults failed on the first run and exposed it.
- **Rule:** Value types are listed as exceptions. Each heuristic has a test with similar names that must not match.

## Mutation results

| Mutation | Test that failed |
|---|---|
| Features may depend on infrastructure | `a feature that depends on infrastructure is a ring edge violation` |
| Undeclared import check removed | `an import of an allowed but undeclared module is a violation` |
| `ExistentialAny` check removed | `a target without ExistentialAny is a violation, test targets included` |
