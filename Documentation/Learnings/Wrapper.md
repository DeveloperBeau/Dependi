# Wrapper

## `set -e` also applies inside command substitution

- **Trap:** `value=$(plutil ...; printf x)` stops inside the substitution when `plutil` fails. The script then exited 1 with no message.
- **Finding:** A test with a missing `.dependi.json` and a Release build saw an empty stderr.
- **Rule:** Put `|| true` on every command in a substitution whose failure is expected.

## A substitution drops trailing newlines

- **Trap:** A version of `1.0.0` followed by a newline matches the pattern after the substitution strips the newline.
- **Finding:** The script adds a sentinel character inside the substitution and removes it afterwards. It also rejects any value that holds a newline.
- **Rule:** Check for a newline before a pattern test. A line-based `grep` cannot see it.

## `case` patterns need quotes to match plain text

- **Trap:** An unquoted variable in a `case` pattern acts as a glob, so `Rel.*` or `[Z]` would match other names.
- **Finding:** The gate name goes into a variable first and is quoted in the pattern. `plutil` also writes `/` as `\/`, so the script undoes that.
- **Rule:** Quote the variable in the pattern. Test names that hold `*`, `[` and `/`.

## The Xcode shim reads `DEVELOPER_DIR`

- **Trap:** A test passed a fake `DEVELOPER_DIR` to the script, and the real `git` shim failed.
- **Finding:** The stub `git` unsets `DEVELOPER_DIR` and `SDKROOT` before it calls the real `git`.
- **Rule:** Only the build step gets the allowed variables. Other tools run with what the caller gave.

## A lock test needs a handshake, not a delay

- **Trap:** A stub that slept one second let the test pass when the second script started late, even with the lock removed.
- **Finding:** The stub now holds the build until the test creates a file. The test proves the second script is in the wait loop by finding its `sleep` child, then releases the build.
- **Rule:** Count the `xcrun` calls. One build means the lock and the second check work. Order the events with files, never with sleeps.

## A bare directory lock cannot name its owner

- **Trap:** A lock folder removed after ten minutes lets two waiters both reclaim it, and a slow build then removes a lock that another run took.
- **Finding:** The lock is a symlink whose target is the owner's process id. It is made in one step. Release checks the target. A stale lock is removed by the one script that holds a reclaim claim. A dead owner is reclaimed at once.
- **Rule:** Record the owner in the lock itself, remove only your own lock, and reclaim under a claim (see the next entry).

## A stale reading goes out of date before the script acts on it

- **Trap:** The first reclaim moved the stale lock aside, checked what it had moved, and put it back if it was not the stale one. Script B read a stale lock. Script C reclaimed it and took the lock. B moved C's live lock aside. Script A then took the free lock. B put C's lock back over the lock of A, and two scripts built at once.
- **Finding:** A shim on `readlink` plays C at the exact read, and a shim on `rm` plays A at the exact removal. That forces the order every time. The put-back is the fault, because any move opens a gap in which a third script can act. The reclaim now takes a claim, a symlink next to the lock, reads the lock again under the claim and removes it only if it is a stale symlink. Nothing is moved and nothing is put back. A test that makes a lock vanish under the claim showed a second fault. A check that treats an absent lock as stale removes a live lock that was taken a moment before. The claimant now tests the lock with `[ -L ]` first. A stop signal between `ln` and the line that records the claim left the claim in place. The script now records the claim before `ln`, and the trap removes it only if it still names the script. A claim left by a killed script is cleared when its process is gone, when its target is not a number, when it names this script, or when it is older than a minute.
- **Rule:** One claimant decides under the claim, and nothing is moved back. A reading taken before the claim is a hint and is checked again under it. A step that must not run on a missing file tests that the file exists.

## A failed take with no lock in place is not a broken folder

- **Trap:** The lock loop treated a failed `ln -s` followed by a missing lock as a cache folder that cannot take a link. An owner that released its lock between those two steps made a waiting script fail with `could not create the build lock`. A concurrent lock test failed this way twice in full runs and then passed 56 reruns.
- **Finding:** An `ln` shim first on the script's pinned `PATH` removes the lock right after the failed take. That forces the interleaving every time. A probe link with a name that only this process uses now tells a released lock from a folder that cannot take a link.
- **Rule:** One failed check against a shared file says what was true a moment ago. Before a wait loop gives up, confirm the cause with a step that no other process can change.

## A version string alone does not pin a build

- **Trap:** The project copy was accepted when `VERSION` equalled the config version. A new pinned commit with the same version kept running the old binary.
- **Finding:** `init` now writes `<version>-<commit>` and the wrapper compares the same string.
- **Rule:** Compare every part of the pin, not a label that people can leave unchanged.

## A digest next to the file proves nothing about who wrote it

- **Trap:** `dependi.sha256` is in the same folder as the binary. A writer plants both.
- **Finding:** Only folder ownership and mode keep a planted pair out. The override of the cache folder was open in production, so any caller could point the script at a folder it controlled.
- **Rule:** Treat the cache folder as the trust boundary. Make it private, refuse a folder that is not, and keep test overrides behind the test flag.

## Git reads the caller's environment and the user's config

- **Trap:** An inherited `GIT_DIR` from a git hook makes `git checkout` act on another repository. `insteadOf`, `core.hooksPath` and `init.templateDir` in the user config change a clone.
- **Finding:** A test with a hostile `GIT_DIR`, a `.gitconfig` that redirects the origin and a decoy `shasum` first on `PATH` shows each effect.
- **Rule:** Run git under `env -i` with a fixed `PATH`, an empty `HOME`, no system or global config, no hooks and no template. Fix `PATH` for the whole script.

## Mutation results

| Mutation | Test that failed |
|---|---|
| The pre-gate condition is inverted | `debugBuildSkipsBeforeAnyCall` |
| The version check accepts anything | `badVersionsAreRejected` |
| The commit check accepts anything | `badCommitsAreRejected` |
| The VERSION comparison always passes | `versionMismatchUsesCache` |
| The sha comparison always passes | `cacheWithWrongShaIsRebuilt` |
| The commit check after the clone is dropped | `movedCommitFailsClean` |
| The lock is never held | `concurrentRunsBuildOnce` |
| The repository override works without the test flag | `repoOverrideNeedsTestingFlag` |
| The build runs without `env -i` | `buildEnvironmentIsClean` |
| A missing lock after a failed take fails at once again | `lockReleasedAfterFailedTakeIsTaken` |
| The lock probe never fails | `unwritableCacheFolderFailsAtOnce` |
| The exit trap keeps the lock probe | `stoppedScriptRemovesLockProbe` |
| A probe left from an earlier run with the same process id is kept, so the probe fails | `leftoverProbeWithSameProcessIdIsReplaced` |
| The probe stays in the cache folder while the script waits and builds | `lockProbeIsGoneDuringBuild` |
| A claim is ignored, so a stale lock is removed while a running script holds the claim | `freshLiveClaimIsRespected` |
| The lock is not read again under the claim | `staleReadingThatGoesOutOfDateNeverMovesANewerLock` |
| A lock that is absent under the claim is removed | `absentLockIsNeverRemovedByAClaimant` |
| The claim stays after a reclaim | `concurrentRunsOnDeadLockBuildOnce` |
| The exit trap keeps the claim | `stoppedScriptRemovesItsClaim` |
| The script does not record that it holds the claim | `stoppedScriptRemovesItsClaim` |
| The exit trap removes a claim that another script holds | `stoppedScriptKeepsAnotherScriptsClaim` |
| A claim of a running process is always cleared | `freshLiveClaimIsRespected` |
| A claim of a process that is gone is kept | `deadOrMalformedClaimIsCleared` |
| The age of a claim is ignored | `oldClaimWithRunningProcessIsCleared` |
| A claim whose target is not a number goes to the process check | `deadOrMalformedClaimIsCleared` |
| A claim that names the script itself is kept | `claimWithOwnProcessIdIsCleared` |

Two branches of the claim check have no mutation. The empty target only skips a claim that was just released, so removing the branch changes only one retry. The sleep after a refused claim, against a retry at once, changes timing and no result that a test can see.
