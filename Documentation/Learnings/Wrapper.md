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

## A mutation of the lock needs the second process to start early

- **Trap:** Two runs that start one after another cannot show a missing lock.
- **Finding:** The stub `xcrun` sleeps one second, so the second process arrives during the build.
- **Rule:** Count the `xcrun` calls. One build means the lock and the second check work.

## A version string alone does not pin a build

- **Trap:** The project copy was accepted when `VERSION` equalled the config version. A new pinned commit with the same version kept running the old binary.
- **Finding:** `init` now writes `<version>-<commit>` and the wrapper compares the same string.
- **Rule:** Compare every part of the pin, not a label that people can leave unchanged.

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
