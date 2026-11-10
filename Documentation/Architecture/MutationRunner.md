# Mutation runner

## Purpose

The runner breaks the code on purpose and checks that a named test fails. A test that still passes is not connected to the rule.

## Parts

- `Documentation/Registers/mutations.json` lists the mutations. Each entry has an id, the slice that owns it, a file, the exact search text, the replacement text and a test id. Two optional fields exist. `expected` is `killed` (the default) or `timeout`. `lastRun` holds the date and the outcome of the latest run and the runner writes it.
- The file is under `Sources/`, or it is a checker file under `Tests/ArchitectureTests/`. A checker file is any Swift file there whose name does not end in `Tests.swift`. The architecture rules live in the test target, so their mutations must change files there. A test file is never mutated.
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
| `--changed-since` | Run only the entries whose file differs from the given git ref. A ref that is not a commit is an error with exit code 2. |
| `--workers` | The number of workers, from 1 to 64. The default is half the performance cores, and at least 1. The runner never starts more workers than files. |
| `--plan` | Pass `yes` to print the workers, the file groups and the baseline tests, and stop. It does not build. |
| `--record` | Pass `no` to leave the register file alone. The default records each outcome as `lastRun`. |
| `--markdown` | Write the register page to the given path and stop. |

## Flow

1. Refuse to start if the working tree is not clean.
2. Validate every entry. The file obeys the rule in Parts. The search text occurs exactly once. The replacement differs. The test id matches exactly one test in `swift test list`. A name that two suites share is ambiguous and is a register error. The id is unique. `expected` is `killed` or `timeout`. A problem is a register error and the exit code is 2.
3. Run each distinct named test once on clean code. `swift test list` in step 2 built the tests, so the baseline does not build. Every entry whose test fails is reported as BASELINE FAILED and does not run.
4. Group the entries by file. A worker takes one whole group at a time, so its builds stay in one module.
5. Apply the mutation and build the tests. A build failure is INVALID. This is the only build for the entry. The restore of the previous entry goes into the same build.
6. Run only the named test, selected with an anchored filter on its full listed id. A pass is SURVIVED. A failure with a test failure marker is KILLED. A time-out is KILLED (TIMEOUT).
7. Restore the file. With one worker, the runner mutates the package folder, restores with `git checkout -- <file>` and requires a clean tree. With more workers, each worker uses a copy of the tracked files in the temporary folder, with its own build folder. The runner writes the original text back into the copy and removes the copy at the end.
8. Print one row for each entry with its seconds, and the total. An outcome that differs from `expected` prints an UNEXPECTED line. A kill by time-out is a pass only when the entry expects `timeout`.
9. Write `lastRun` into each entry that ran, by editing the entry text in place. Other text in the file is not reformatted.

A survivor, an invalid mutant, an unexpected outcome or a baseline failure makes the exit code 1.

## Interrupts

SIGINT and SIGTERM stop every child process, restore the file that is mutated in the package folder, remove every worker copy and exit with 130. The first shutdown wins. After it starts, no worker starts a command or writes into a copy, so a removed copy does not come back. The runner lists the tracked files once, before the workers start. A worker never runs a command while it holds the copy lock, and a copy stops at once when the shutdown starts. A failed copy or any other failure removes every copy that exists.

## Processes

Each command runs in its own process group. On a time-out or an interrupt the runner kills the group and every descendant in the process table. The test helper that `swift test` starts leaves the group, so the group kill alone is not enough.

## Test ids

Use the test function name, for example `interruptRestoresFile`, when it is unique in the test target. When two suites share a name, write the suite and the function, for example `ReleaseGateTests/missingAction()`. A parameterized test lists its argument labels, for example `badOutputPath(path:)`. `swift test --filter` does not match display names. A bare `--filter name` matches every test whose id contains the name, so the runner never uses it.

## Tests

The tests use a small package in its own git repository under `.build/mutation-runner-fixture`. Each test resets the package to its fixture commit. The package keeps its build folder.

`MutationRunnerTests` runs the real runner with a `swift` double first on `PATH`. The double records each call and answers from rules that copy the fixture package: a test fails or hangs when a source file matches a pattern, and a build fails on a broken line. These tests check each outcome, each register error, a dirty tree, malformed registers, both interrupts, the plan, the workers, the calls for each entry, the baseline count, the changed-file filter and the generated page. They need no build and take seconds. The variable `MUTATE_COPY_DELAY_FOR_TESTS` holds each worker copy open for the given seconds, so a test can interrupt the runner during a copy. `SwiftDoubleFixtureTests` checks that each rule of the double matches the fixture only after the mutation that it models, and that the listing is the fixture's test list.

`MutationRunnerEndToEndTests` runs the real toolchain: one run in place with each outcome, one run with two workers, one interrupt during a real test and one real time-out. The default test run skips them. `Scripts/runner-check.sh` runs them. `Scripts/gate.sh` runs that script when `Scripts/mutate.swift`, `Scripts/runner-check.sh`, `Package.swift` or `Tests/MutationRunnerTests` differ from the merge base with `origin/main`, or when there is no merge base. Set `GATE_BASE` to use another base.
