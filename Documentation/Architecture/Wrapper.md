# Wrapper

## Purpose

`WrapperScript.text` in `DependiInit` is the POSIX `sh` script that the wizard writes to `.dependi/run.sh`. The Run Script phase calls it. It runs the pinned Dependi binary and builds that binary from source when it is missing.

## Steps

1. Find the project root. It is the parent of the folder that holds the script.
2. Pre-gate. With no `ACTION` and no `TARGET_BUILD_DIR` the script prints a skip line and exits 0. Otherwise it reads `gateConfigurations` from `.dependi.json` with `plutil`. The default is `["Release"]`. When `ACTION` is not `install` and `CONFIGURATION` is not in the list, it prints `Dependi: skipped. configuration X is not in the gate list` to stdout and exits 0. No `git`, `xcrun`, `swift` or network call has happened by then.
3. Validate. `version` must match `^[0-9]+\.[0-9]+\.[0-9]+$` and `commit` must match `^[0-9a-f]{40}$`. A value with a newline fails. A bad value prints `error: ...` to stderr and exits 1.
4. Project copy. If `.dependi/bin/dependi` is executable and the first line of `.dependi/bin/VERSION` equals `<version>-<commit>` from the config, the script runs it with `exec`. `init` writes that line from the commit of the checkout it was run from. A file with only the version, or with another commit, does not match. This uses shell built-ins only.
5. Cache. The cache root is `$HOME/Library/Caches/dependi`. `$DEPENDI_CACHE_ROOT` replaces it only with `DEPENDI_TESTING=1`. The script refuses a root that is a symlink, is not a folder, is not owned by the current user or can be written by the group or others. It makes a new root with mode 0700. The entry is `<version>-<commit>/bin`. It is used only when `dependi.sha256` equals the `shasum -a 256` of `dependi`.
6. Build. The lock is a symlink `<version>-<commit>.build-lock` in the cache root. Its target is the process id of the owner, so taking the lock and recording the owner is one step (`ln -s`). The script polls every 0.2 s for at most 300 s. A lock is stale when its target is not a number, when the owner process is gone (`kill -0` fails), or when the owner runs but the lock is older than 30 minutes. A stale lock is renamed to a name that holds the script's own process id, checked, and then removed. A lock that another process took in the meantime is put back. A dead owner is therefore reclaimed at once, before any waiter gives up. After it gets the lock the script checks the cache again. Then it:
   - makes a temp folder `build.XXXXXX` under the cache root,
   - runs `git clone --quiet --template=`, `git checkout --quiet <commit>` and requires `git rev-parse HEAD` to equal the pin. Each git call goes through `env -i` with `HOME` set to an empty folder in the temp folder, `PATH=/usr/bin:/bin`, `GIT_CONFIG_NOSYSTEM=1`, `GIT_CONFIG_GLOBAL=/dev/null`, `GIT_TERMINAL_PROMPT=0`, `TMPDIR` and, when set, `DEVELOPER_DIR`. It also passes `-c core.hooksPath=/dev/null`. An inherited `GIT_DIR` or a user config never reaches git,
   - builds under `env -i` with `HOME`, `PATH=/usr/bin:/bin`, `TMPDIR` and, when set, `DEVELOPER_DIR`,
   - copies `build/release/dependi` to `out/dependi`, writes `out/dependi.sha256`,
   - renames `out` to `<version>-<commit>/bin`.
7. Release the lock and the temp folder, then `exec` the cached binary with the script arguments.

## Fixed values

The script sets `PATH=/usr/bin:/bin` at the top. Every tool it calls resolves from there, and the caller's `PATH` is not used.

The repository URL and the build command are constants in the script. Nothing comes from `.dependi.json` except the version, the commit and the gate list. With `DEPENDI_TESTING=1` four test hooks work: `DEPENDI_REPO_URL` replaces the URL, `DEPENDI_XCRUN` replaces `/usr/bin/xcrun` `DEPENDI_CACHE_ROOT` replaces the cache folder and `DEPENDI_LOCK_WAIT_STEPS` sets the number of 0.2 s waits for the lock.

## Trust model

The cache is trusted when the folder is private to the user. `dependi.sha256` sits next to the binary, so it detects a damaged file and not a planted one. Anyone who can write the cache folder can replace both files. The ownership and mode checks keep other users out. The same user, or a process that runs as that user, is trusted. The project copy in `.dependi/bin` is trusted the same way, on its `VERSION` line. The script checks the digest and then runs the file in two steps, and a writer who owns the folder can swap the file between them. The wrapper does not defend against that.

## Edge cases

- A trap on `EXIT`, `HUP`, `INT` and `TERM` removes the temp folder and the lock. The lock is removed only when its target is still the script's own process id. The script releases both by hand before each `exec`, because `exec` skips the trap.
- A cache entry without a sha file, or with a wrong sha, is deleted and rebuilt. It is never run.
- A failed clone, checkout, commit check or build prints the last 20 lines of the log and exits 1. The temp folder is removed.
- A gate name is matched as a quoted string inside the JSON list. A name with a quote or a backslash never matches.
- A second process that waits for the lock finds the finished cache and does not build.

## Tests

`WrapperScriptTests` and `WrapperScriptFuzzTests` write the script into a temp project. Stub `git`, `xcrun` and `dependi` programs come first on `PATH` and log each call. The script runs git as `/usr/bin/git`. The tests reach the stub through the Xcode shim: `DEVELOPER_DIR` points at a folder whose `usr/bin/xcrun` hands `git` calls to the stub. The stub `git` records its arguments and its environment, then forwards to the real `git` against a bare repository made in the test. The stub `xcrun` can hold a build until a test creates a `proceed` file. A test starts the first script, waits for the `building` file, starts the second and waits until the second has a `sleep` child, which proves it is in the lock wait loop. Then it releases the build. The stub `xcrun` makes `<scratch>/release/dependi`, a small shell script that prints a marker.
