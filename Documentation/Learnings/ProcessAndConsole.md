# Process and console

## A child inherits the signal state of its parent

- **Trap:** `posix_spawn` passes ignored signals and the signal mask to the child.
- **Finding:** A shell that ran `kill -15 $$` did not die in the test host, so the exit status was not 143.
- **Rule:** The runner resets all signal handlers and the signal mask in the child.

## Killing the group is not enough

- **Trap:** A helper that calls `setsid` leaves the process group and survives a group kill.
- **Finding:** A test with a `perl` helper left a sleeping shell behind until the runner also walked the process table.
- **Rule:** On time-out, list the descendants first, then kill the group and each descendant.

## A held pipe can outlive the child

- **Trap:** A child that exits while a background process keeps its output open never gives end of input.
- **Finding:** A wait for end of input hung until the grandchild ended.
- **Rule:** The wait for the readers shares the run deadline. The readers poll, so they can be told to stop.

## Descriptors leak into the child

- **Trap:** Without a close-on-exec default, the child holds the read ends of its own pipes and end of input never arrives.
- **Finding:** The spawn uses the close-everything-else flag and duplicates only the three standard descriptors.
- **Rule:** Close every pipe end in the parent on every path.

## Prompts must never loop

- **Trap:** A prompt that asks again until the answer is valid never ends on bad input.
- **Finding:** The bound test with three invalid lines and a valid fourth line fails when the bound grows. The two-invalid test fails when it shrinks.
- **Rule:** Each prompt reads at most three lines. A prompt reads one byte at a time under a lock, so no byte is lost between calls.

## A reaped process id is not yours

- **Trap:** The runner killed the group and the child after it had reaped the child. The id could belong to another process by then.
- **Finding:** Found by reading the order of calls, not by a failure.
- **Rule:** Look at the child with `waitid` and `WNOWAIT`. Kill while it is a zombie. Tell the tracker, then reap.

## A failed wait is not exit 0

- **Trap:** A `waitpid` error such as `ECHILD` ended the loop with status 0.
- **Finding:** A process id that is not a child of the test process fails with `ECHILD`, so a test can cause it.
- **Rule:** Report a failed wait as `processFailed`.

## Children do not get the signals of the parent

- **Trap:** Each child leads its own process group, so Ctrl-C or a cancelled build never reaches `swift package dump-package`. It ran on for up to the time limit.
- **Finding:** The tool had no signal handling.
- **Rule:** The runner reports each child to a registry. The executable kills the registry on SIGINT, SIGTERM and SIGHUP and exits with 128 plus the signal.

## Mutation results

The nine entries owned by this slice are all killed. See `Documentation/Registers/mutations.md`.

| Mutation | Test that failed |
|---|---|
| The readers never read | `bigOutputOnBothStreamsArrivesWithExactBytesAndChecksum` |
| Only the child is killed | `aGrandchildHoldingStandardOutputIsKilledOnTimeout` |
| No descendants are killed | `aDescendantThatLeftTheProcessGroupIsKilledOnTimeout` |
| The inherited environment is passed | `theChildEnvironmentIsExactlyTheRequestEnvironment` |
| The cap is multiplied by 1000 | `outputOverTheCapFailsAndNamesTheLimit` |
| The cap check uses `>=` | `outputExactlyAtTheCapIsKept` |
| The time-out check never fires | `aSlowChildIsTimedOutQuickly` |
| The attempt bound is 4 | `threeInvalidLinesFailEvenWhenAValidLineFollows` |
| The attempt bound is 2 | `twoInvalidLinesThenAValidOneStillSucceeds` |
