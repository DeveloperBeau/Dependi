# Test doubles

## A double must resolve links the way the real system does

- **Trap:** The double stored a link under the path it was given. When the test root was reached through a linked folder, as `/var` is on macOS, the link was filed under the wrong path and later reads failed.
- **Finding:** The same suite passed for the plain root and failed for the linked root.
- **Rule:** Every operation that creates a node resolves the parent folder first. The suite runs once with a linked root.

## Typed errors need a typed lock helper

- **Trap:** A lock helper that uses `rethrows` turns every typed error into `any Error`, so a double cannot throw `DomainError` from inside it.
- **Finding:** The first build of the file system double failed on every throwing method.
- **Rule:** The helper is generic over the error type of its closure.

## Protocol witnesses need their own summary

- **Trap:** The rule that every public declaration has a doc comment also covers the methods that implement a protocol.
- **Finding:** The architecture test flagged 23 witnesses on its first run over the doubles.
- **Rule:** Each witness gets a one-line summary. Tooling is the only reliable way to keep this up.

## Mutation results

| Mutation | Test that failed |
|---|---|
| The read returns `limit` bytes, not `limit + 1` | `doublePassesBehaviorSuite` |
| The link hop limit drops from 40 to 20 | `loopsAndChains` |
| The read-only check matches by string prefix | `readOnlyIsMatchedByComponent` |
