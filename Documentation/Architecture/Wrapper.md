# Wrapper

## Purpose

`WrapperScript.text` in `DependiInit` is the POSIX `sh` script that the wizard writes to `.dependi/run.sh`. The Run Script phase calls it. It runs the pinned Dependi binary and builds that binary from source when it is missing.

## Steps

1. Find the project root. It is the parent of the folder that holds the script.
2. Pre-gate. With no `ACTION` and no `TARGET_BUILD_DIR` the script prints a skip line and exits 0. Otherwise it reads `gateConfigurations` from `.dependi.json` with `plutil`. The default is `["Release"]`. When `ACTION` is not `install` and `CONFIGURATION` is not in the list, it prints `Dependi: skipped. configuration X is not in the gate list` to stdout and exits 0. No `git`, `xcrun`, `swift` or network call has happened by then.
3. Validate. `version` must match `^[0-9]+\.[0-9]+\.[0-9]+$` and `commit` must match `^[0-9a-f]{40}$`. A value with a newline fails. A bad value prints `error: ...` to stderr and exits 1.
4. Project copy. If `.dependi/bin/dependi` is executable and the first line of `.dependi/bin/VERSION` equals `<version>-<commit>` from the config, the script runs it with `exec`. `init` writes that line from the commit of the checkout it was run from. A file with only the version, or with another commit, does not match. This uses shell built-ins only.
5. Cache. The cache root is `$DEPENDI_CACHE_ROOT` or `$HOME/Library/Caches/dependi`. The entry is `<version>-<commit>/bin`. It is used only when `dependi.sha256` equals the `shasum -a 256` of `dependi`.
6. Build. The script takes the lock `<version>-<commit>.lock` with `mkdir`, polls every 0.2 s for at most 300 s and removes a lock older than 10 minutes. After it gets the lock it checks the cache again. Then it:
   - makes a temp folder `build.XXXXXX` under the cache root,
   - runs `git clone --quiet`, `git checkout --quiet <commit>` and requires `git rev-parse HEAD` to equal the pin,
   - builds under `env -i` with `HOME`, `PATH=/usr/bin:/bin`, `TMPDIR` and, when set, `DEVELOPER_DIR`,
   - copies `build/release/dependi` to `out/dependi`, writes `out/dependi.sha256`,
   - renames `out` to `<version>-<commit>/bin`.
7. Release the lock and the temp folder, then `exec` the cached binary with the script arguments.

## Fixed values

The repository URL and the build command are constants in the script. Nothing comes from `.dependi.json` except the version, the commit and the gate list. With `DEPENDI_TESTING=1` two test hooks work: `DEPENDI_REPO_URL` replaces the URL and `DEPENDI_XCRUN` replaces `/usr/bin/xcrun`.

## Edge cases

- A trap on `EXIT`, `HUP`, `INT` and `TERM` removes the temp folder and the lock. The script releases both by hand before each `exec`, because `exec` skips the trap.
- A cache entry without a sha file, or with a wrong sha, is deleted and rebuilt. It is never run.
- A failed clone, checkout, commit check or build prints the last 20 lines of the log and exits 1. The temp folder is removed.
- A gate name is matched as a quoted string inside the JSON list. A name with a quote or a backslash never matches.
- A second process that waits for the lock finds the finished cache and does not build.

## Tests

`WrapperScriptTests` and `WrapperScriptFuzzTests` write the script into a temp project. Stub `git`, `xcrun` and `dependi` programs come first on `PATH` and log each call. The stub `git` forwards to the real `git` against a bare repository made in the test. The stub `xcrun` makes `<scratch>/release/dependi`, a small shell script that prints a marker.
