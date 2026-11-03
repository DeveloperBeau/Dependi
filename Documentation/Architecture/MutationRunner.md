# Mutation runner

## Purpose

The runner breaks the code on purpose and checks that a named test fails. A test that still passes is not connected to the rule.

## Parts

- `Documentation/Registers/mutations.json` lists the mutations. Each entry has an id, the slice that owns it, a file under `Sources/`, the exact search text, the replacement text and a test id.
- `Scripts/mutate.swift` is the runner. Compile it with `swiftc Scripts/mutate.swift -o mutate`.
- `Documentation/Registers/mutations.md` is generated from the JSON with `--markdown`. A test fails if it is stale.

## Flags

| Flag | Meaning |
|---|---|
| `--root` | The package folder. The default is the current folder. |
| `--register` | The register file. |
| `--timeout` | The time limit in seconds for the named test of one mutant. A mutant that runs longer is killed by time-out. |
| `--build-timeout` | The time limit in seconds for a build and for the baseline run. The default is 900. A build that runs longer is INVALID, never a kill. |
| `--only` | Run one entry. |
| `--markdown` | Write the register page to the given path and stop. |

## Flow

1. Refuse to start if the working tree is not clean.
2. Validate every entry. The file is a relative path under `Sources/`. The search text occurs exactly once. The replacement differs. The test id appears in `swift test list`. The id is unique. A problem is a register error and the exit code is 2.
3. For each entry, run the named test on clean code. A failure is reported as BASELINE FAILED.
4. Apply the mutation and build the tests. A build failure is INVALID.
5. Run only the named test. A pass is SURVIVED. A failure with a test failure marker is KILLED. A time-out is KILLED (TIMEOUT).
6. Restore the file with `git checkout -- <file>` and require a clean tree.
7. Print one row for each entry with its seconds, and the total.

A survivor, an invalid mutant or a baseline failure makes the exit code 1.

## Interrupts

SIGINT and SIGTERM restore the file that is being mutated and exit with 130.

## Processes

Each command runs in its own process group. On a time-out or an interrupt the runner kills the group and every descendant in the process table. The test helper that `swift test` starts leaves the group, so the group kill alone is not enough.

## Test ids

Use the test function name, for example `interruptRestoresFile`. `swift test --filter` does not match display names.

## Tests

`MutationRunnerTests` builds a small package in a temporary git repository. It runs the real runner and checks each outcome, each register error, a dirty tree, malformed registers, an interrupt and the generated page.
