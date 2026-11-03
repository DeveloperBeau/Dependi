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
- **Finding:** The lock is a symlink whose target is the owner's process id. It is made in one step. Release checks the target. A stale lock is renamed away before it is removed. A dead owner is reclaimed at once.
- **Rule:** Record the owner in the lock itself, remove only your own lock, and reclaim by rename and check.

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
