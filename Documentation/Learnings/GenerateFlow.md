# Generate flow

## The sandbox check belongs after the gate

- **Trap:** The design put the sandbox check first. Every Debug build with the sandbox on would then fail, even though Dependi does nothing in Debug.
- **Finding:** A test with a Debug build and the sandbox on expects a skip.
- **Rule:** The gate decides first. The sandbox check applies only to a build that will run.

## A permission error usually means the sandbox

- **Trap:** With the sandbox on, reads of `SourcePackages` fail with "Operation not permitted" and the message gives no hint.
- **Finding:** The flow maps that reason to a named error whose message says what to change.
- **Rule:** Name the likely cause of a common failure in the error.

## Validate output locations before writing

- **Trap:** A relative `TARGET_BUILD_DIR` or a `..` in the resources path would write into the source tree.
- **Finding:** Seven bad locations are refused and no write is attempted.
- **Rule:** Check every part of an output path before the first write.

## Mutation results

Fourteen entries owned by this slice are all killed. One entry first came back INVALID because the mutant removed a binding that its body used. Keep a binding when a mutation changes an `if case`.
