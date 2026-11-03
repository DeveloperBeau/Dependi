# Mutation testing

## A non-zero exit is not a kill

- **Trap:** A mutation can stop the code from compiling. Counting that as a kill reports a connection that does not exist.
- **Finding:** The runner builds the mutant first. A build failure is INVALID. A kill needs a test failure marker in the output.
- **Rule:** Only a named test that ran and failed kills a mutant.

## A mutant can loop forever

- **Trap:** Removing a guard from a loop makes the test hang. A hang is a defect in the test run.
- **Finding:** Each run has a time limit. The runner kills the whole process group, because the build tool leaves child processes behind.
- **Rule:** A time-out counts as KILLED (TIMEOUT) and is shown as such.

## A killed process group can leave the test helper running

- **Trap:** Killing the process group of `swift test` on a time-out does not stop the test helper that it started. A looping mutant kept a CPU core busy long after the run, and later builds slowed down.
- **Finding:** The helper leaves the group. A test that looked for processes with the package path in their command line found it.
- **Rule:** On a time-out or an interrupt the runner kills the group and every descendant it finds in the process table.

## A slow build must not look like a looping mutant

- **Trap:** One time limit covered the build and the test. On a busy machine a build took longer than the limit and the runner tests failed without a clear reason.
- **Finding:** An agent saw the runner tests fail once while several gates ran at the same time.
- **Rule:** The build and the baseline have their own, longer limit. Only the named test can be killed by time-out.

## An interrupt can leave broken code in the tree

- **Trap:** Ctrl-C between the edit and the restore leaves a mutated source file that a later commit could include.
- **Finding:** The runner traps SIGINT and SIGTERM and restores the file. A test sends the signal during a mutant run.
- **Rule:** The runner restores on every exit path and requires a clean tree after each entry.

## Test filters match function names

- **Trap:** `swift test --filter` with a display name matched nothing and the run reported success.
- **Finding:** The output said `No matching test cases were run` and the first mutation check proved nothing.
- **Rule:** A register test id is a function name and must resolve in `swift test list`. A mutation check that shows no test result is not a result.

## Mutation results for the runner

| Mutation | Test that failed |
|---|---|
| A build failure counts as killed | `mixedRegisterReportsEachOutcome` |
| The interrupt handler does not restore | `interruptRestoresFile` |
| A time-out kills the group only | `timeoutLeavesNoProcessBehind` |
