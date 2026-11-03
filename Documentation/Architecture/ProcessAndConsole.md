# Process and console

## Purpose

`DependiProcess` runs child processes. `DependiConsole` talks to the user. Each implements domain interfaces and imports nothing else from the package. `DependiProcess` is the only module that may import Dispatch and Darwin together.

## Parts

| Part | Role |
|---|---|
| `SystemProcessRunner` | `ProcessRunning` over `posix_spawn` and its own pipes. |
| `StreamCollector` | Reads one pipe and keeps at most `maximumOutputBytes`. Internal. |
| `RunSignals` | Overflow and stop flags that the readers and the waiting thread share. Internal. |
| `ProcessTree` | Finds descendants in the process table and kills them. Internal. |
| `StandardConsole` | `Prompting` and `OutputWriting` over three `FileHandle` values. |

## Data flow of a run

1. Two pipes are created. The child gets `/dev/null` as input and the pipe ends as output and error.
2. The child starts with `posix_spawn`. It leads its own process group, closes every other descriptor, starts with default signal handling and an empty signal mask. The working directory comes from `posix_spawn_file_actions_addchdir_np`.
3. The child environment is exactly `request.environment`. Arguments are an array. No shell runs.
4. Two reader tasks drain the pipes at the same time. A reader polls with a short wait, so a pipe that stays open cannot block it forever.
5. The caller waits for the child with a short sleep loop. It checks the time limit and the overflow flag at each step.
6. After the child exits, the caller waits for both readers until the same deadline.
7. The result is the exit status and both byte buffers. A signal death gives 128 plus the signal number.

## Edge cases

- Output over the cap kills the tree and fails with the limit in the message. Output exactly at the cap is kept.
- A time-out kills the process group and every descendant found in the process table. It then reaps the child. The message reads `timed out after N seconds`.
- A descendant that left the group with `setsid` is found through the process table.
- A background child that holds the pipe open after the parent exits is a time-out, not a hang.
- A missing executable, a relative executable and a missing working directory fail with `processFailed`. The runner never searches `PATH`.
- Both pipe ends are closed on every path.

## Console behavior

- `askChoice` prints the question and numbered options. It accepts a number from 1 to the option count and returns a zero-based index.
- `askConfirmation` accepts `y`, `yes`, `n` and `no` in any case.
- Both read at most three lines. Three invalid lines, or the end of input, fail with `inputEnded`.
- Input is read one byte at a time under a lock, so no byte read ahead is lost between prompts.

## Tests

`SystemProcessRunnerTests` covers exact bytes of more than 1 MB on both streams, exit codes, signal death, spawn failures, the working directory, the exact environment, caps, time-outs with grandchildren and escaped descendants, descriptor counts and a seeded round-trip fuzz. `StandardConsoleTests` uses pipes with scripted input.
