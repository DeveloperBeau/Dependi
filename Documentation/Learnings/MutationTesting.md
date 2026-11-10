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

## A filter by substring can pick the wrong test

- **Trap:** `swift test --filter name` matches every test whose id contains the name. Seven register entries named a function that two or three suites declare, and one name was also the start of a longer one. The kill could come from a test that the entry did not name.
- **Finding:** `swift test list` showed several ids for each of those names.
- **Rule:** The runner finds the one listed id for the entry and filters on that full id. A name with more than one match is a register error. Write the suite and the function when a bare name is shared.

## A hang is not a kill

- **Trap:** A mutant that only made a test loop was counted as killed, so a test that never failed looked connected.
- **Finding:** The pass rule counted every outcome except survived and invalid.
- **Rule:** A kill by time-out passes only when the entry says `"expected": "timeout"`. Any other outcome that differs from the expectation fails the run.

## Two builds for each entry made the register slow

- **Trap:** The runner ran the baseline of each entry on clean code and then built the mutant. The baseline rebuilt the file that the previous entry restored. Each entry paid for two builds and two test runs, one entry at a time.
- **Finding:** A register of 276 entries took more than 80 minutes. The tests themselves ran in seconds.
- **Rule:** The runner runs each distinct baseline once before the first mutation. Each entry has one build. Workers in their own copies run file groups at the same time.

## A cold fixture package made the runner tests slow

- **Trap:** Each runner test made a new package in a new folder, so each test built the package from nothing.
- **Finding:** The runner suite took about 13 minutes of a gate on a busy machine. Most of that time was cold builds of a package with one file.
- **Rule:** The runner tests share one fixture package that keeps its build folder. Each test resets the package to its fixture commit first.

## Mutation results for the runner

| Mutation | Test that failed |
|---|---|
| A build failure counts as killed | `mixedRegisterReportsEachOutcome` |
| The interrupt handler does not restore | `interruptRestoresFile` |
| A time-out kills the group only | `timeoutLeavesNoProcessBehind` |
| A bare name is used as a substring filter | `qualifiedTestRunsOnlyThatTest`, `prefixOfAnotherNameDoesNotMatch` |
| A time-out counts as a pass | `undeclaredTimeoutFails` |
| An expectation is not compared | `killWhereTimeoutExpectedFails` |
