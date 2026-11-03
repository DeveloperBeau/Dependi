/// The committed wrapper script that the wizard installs as `.dependi/run.sh`.
///
/// The script runs the pinned Dependi binary. It prefers the project copy, then the
/// user cache, and builds the pinned commit from source as the last step.
///
/// Test hooks work only when `DEPENDI_TESTING=1` is set:
/// - `DEPENDI_REPO_URL` replaces the repository URL.
/// - `DEPENDI_XCRUN` replaces the `xcrun` tool.
/// - `DEPENDI_CACHE_ROOT` replaces the cache folder.
/// - `DEPENDI_LOCK_WAIT_STEPS` sets how many 0.2 second waits the lock allows.
///
/// Cache layout under `$HOME/Library/Caches/dependi`. The script makes the folder private to the
/// user and refuses a folder that another user owns or can write:
/// - `<version>-<commit>/bin/dependi` and `dependi.sha256`: a finished build.
/// - `<version>-<commit>.build-lock`: the build lock, a symlink whose target is the owner's process id.
/// - `build.XXXXXX`: a temporary build folder with `src`, `build`, `out` and `build.log`.
///   The product is read from `build/release/dependi`. `out` is renamed to `bin`.
public enum WrapperScript {
    /// The account that owns the repository, built from parts.
    private static let owner = "Developer" + "Beau"

    /// The full text of the POSIX `sh` script.
    public static let text: String = #"""
        #!/bin/sh
        # Dependi wrapper. Runs the pinned Dependi binary and builds it when needed.
        # The repository URL and the build command are fixed here and never come from config.
        set -eu

        # Every tool below resolves from a fixed path, never from the caller's PATH.
        PATH=/usr/bin:/bin
        export PATH

        repo_url='https://github.com/\#(owner)/Dependi.git'
        nl='
        '

        testing() {
            [ "${DEPENDI_TESTING:-}" = 1 ]
        }

        here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
        root=$(dirname -- "$here")
        config="$root/.dependi.json"

        # Step 1: the cheap pre-gate. It runs before any git, xcrun, swift or network call.
        if [ -z "${ACTION:-}" ] && [ -z "${TARGET_BUILD_DIR:-}" ]; then
            echo 'Dependi: skipped. not running inside Xcode and no ACTION is set'
            exit 0
        fi

        gates=$(plutil -extract gateConfigurations json -o - -- "$config" 2>/dev/null) || gates='["Release"]'
        gates=$(printf '%s' "$gates" | sed 's#\\/#/#g')

        in_gate() {
            case "${CONFIGURATION:-}" in
            "" | *'"'* | *'\'*) return 1 ;;
            esac
            needle="\"${CONFIGURATION}\""
            case "$gates" in
            *"$needle"*) return 0 ;;
            esac
            return 1
        }

        if [ "${ACTION:-}" != install ] && ! in_gate; then
            printf 'Dependi: skipped. configuration %s is not in the gate list\n' "${CONFIGURATION:-}"
            exit 0
        fi

        # Step 2: read and validate the pin before anything touches the file system.
        read_key() {
            value=$({ plutil -extract "$1" raw -o - -- "$config" 2>/dev/null || true; printf x; })
            value=${value%x}
            value=${value%"$nl"}
            printf '%s' "$value"
        }

        valid() {
            case "$1" in
            *"$nl"*) return 1 ;;
            esac
            printf '%s\n' "$1" | LC_ALL=C grep -Eq "$2"
        }

        version=$(read_key version; printf x)
        version=${version%x}
        commit=$(read_key commit; printf x)
        commit=${commit%x}

        if ! valid "$version" '^[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo 'error: Dependi: the version in .dependi.json must look like 1.2.3' >&2
            exit 1
        fi
        if ! valid "$commit" '^[0-9a-f]{40}$'; then
            echo 'error: Dependi: the commit in .dependi.json must be 40 lowercase hex characters' >&2
            exit 1
        fi

        # Step 3: the project copy.
        bin_dir="$here/bin"
        if [ -f "$bin_dir/dependi" ] && [ -x "$bin_dir/dependi" ] && [ -f "$bin_dir/VERSION" ]; then
            installed=
            read -r installed <"$bin_dir/VERSION" || true
            if [ "$installed" = "$version-$commit" ]; then
                exec "$bin_dir/dependi" "$@"
            fi
        fi

        # Step 4: the user cache.
        home=${HOME:-}
        cache_root=$home/Library/Caches/dependi
        if testing && [ -n "${DEPENDI_CACHE_ROOT:-}" ]; then
            cache_root=$DEPENDI_CACHE_ROOT
        fi
        if [ -z "$cache_root" ] || [ "$cache_root" = /Library/Caches/dependi ]; then
            echo 'error: Dependi: HOME is not set and no cache folder is given' >&2
            exit 1
        fi
        if [ -e "$cache_root" ]; then
            if [ -L "$cache_root" ] || [ ! -d "$cache_root" ] || [ ! -O "$cache_root" ]; then
                echo 'error: Dependi: the cache folder is not a folder that you own' >&2
                exit 1
            fi
            if [ -n "$(find "$cache_root" -maxdepth 0 \( -perm -020 -o -perm -002 \) 2>/dev/null)" ]; then
                echo 'error: Dependi: the cache folder can be written by other users' >&2
                exit 1
            fi
        fi
        key="$version-$commit"
        cached="$cache_root/$key/bin"
        lock="$cache_root/$key.build-lock"
        token=$$

        cache_valid() {
            [ -f "$cached/dependi" ] && [ -x "$cached/dependi" ] && [ -f "$cached/dependi.sha256" ] || return 1
            actual=$(shasum -a 256 "$cached/dependi" | cut -d' ' -f1)
            recorded=
            read -r recorded <"$cached/dependi.sha256" || true
            [ -n "$actual" ] && [ "$actual" = "$recorded" ]
        }

        if cache_valid; then
            exec "$cached/dependi" "$@"
        fi

        # Step 5: build under a lock. The trap removes the lock and the temp folder on every exit.
        have_lock=0
        tmp=

        release() {
            if [ -n "$tmp" ]; then
                rm -rf "$tmp"
                tmp=
            fi
            if [ "$have_lock" = 1 ]; then
                owner=$(readlink "$lock" 2>/dev/null || true)
                if [ "$owner" = "$token" ]; then
                    rm -f "$lock"
                fi
                have_lock=0
            fi
        }

        on_exit() {
            status=$?
            trap - EXIT
            release
            exit "$status"
        }
        trap on_exit EXIT
        trap 'exit 1' HUP INT TERM

        fail() {
            echo "error: Dependi: $1" >&2
            if [ -n "$tmp" ] && [ -f "$tmp/build.log" ]; then
                tail -n 20 "$tmp/build.log" >&2
            fi
            exit 1
        }

        (umask 077 && mkdir -p "$cache_root")

        # The lock is a symlink named for the build. Its target is the owner process id,
        # so taking the lock and recording the owner is one atomic step.
        max_steps=1500
        if testing && [ -n "${DEPENDI_LOCK_WAIT_STEPS:-}" ]; then
            max_steps=$DEPENDI_LOCK_WAIT_STEPS
        fi

        # A lock is stale when its owner process is gone or its target is not a process id.
        # A lock whose owner is still running is stale only after 30 minutes.
        lock_is_stale() {
            holder=$(readlink "$lock" 2>/dev/null || true)
            case "$holder" in
            "" | *[!0-9]*) return 0 ;;
            esac
            kill -0 "$holder" 2>/dev/null || return 0
            [ -n "$(find "$lock" -maxdepth 0 -mmin +30 2>/dev/null)" ]
        }

        # Move the stale lock aside under a name no one else uses, then check what was moved.
        # A lock that another process took in the meantime goes back.
        reclaim_lock() {
            grave="$lock.stale.$$"
            rm -rf "$grave"
            mv "$lock" "$grave" 2>/dev/null || return 0
            moved=$(readlink "$grave" 2>/dev/null || true)
            if [ "$moved" = "$holder" ]; then
                rm -rf "$grave"
            else
                mv "$grave" "$lock" 2>/dev/null || rm -rf "$grave"
            fi
        }

        steps=0
        while ! ln -s "$token" "$lock" 2>/dev/null; do
            if [ ! -L "$lock" ] && [ ! -e "$lock" ]; then
                fail 'could not create the build lock in the cache folder'
            fi
            if lock_is_stale; then
                reclaim_lock
                continue
            fi
            steps=$((steps + 1))
            if [ "$steps" -ge "$max_steps" ]; then
                fail 'waited for another build to finish'
            fi
            sleep 0.2
        done
        have_lock=1

        if cache_valid; then
            release
            exec "$cached/dependi" "$@"
        fi

        if testing && [ -n "${DEPENDI_REPO_URL:-}" ]; then
            repo_url=$DEPENDI_REPO_URL
        fi
        xcrun=/usr/bin/xcrun
        if testing && [ -n "${DEPENDI_XCRUN:-}" ]; then
            xcrun=$DEPENDI_XCRUN
        fi

        tmp=$(mktemp -d "$cache_root/build.XXXXXX")
        log="$tmp/build.log"
        : >"$log"
        mkdir "$tmp/githome"

        # Git runs with a clean environment: no inherited GIT_DIR, no user or system config,
        # no hooks and no template folder.
        run_git() {
            env -i HOME="$tmp/githome" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0 ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} /usr/bin/git -c core.hooksPath=/dev/null "$@"
        }

        if ! run_git clone --quiet --template= "$repo_url" "$tmp/src" >>"$log" 2>&1; then
            fail 'git clone failed'
        fi
        if ! run_git -C "$tmp/src" checkout --quiet "$commit" >>"$log" 2>&1; then
            fail "git checkout of $commit failed"
        fi
        head=$(run_git -C "$tmp/src" rev-parse HEAD 2>>"$log") || head=
        if [ "$head" != "$commit" ]; then
            fail "the checked out commit is not the pinned commit $commit"
        fi

        if ! env -i HOME="$home" PATH=/usr/bin:/bin TMPDIR="${TMPDIR:-/tmp}" ${DEVELOPER_DIR:+DEVELOPER_DIR="$DEVELOPER_DIR"} "$xcrun" swift build -c release --package-path "$tmp/src" --scratch-path "$tmp/build" --product dependi >>"$log" 2>&1; then
            fail 'swift build failed'
        fi
        if [ ! -f "$tmp/build/release/dependi" ]; then
            fail 'swift build made no dependi product'
        fi

        mkdir "$tmp/out"
        cp "$tmp/build/release/dependi" "$tmp/out/dependi"
        chmod 755 "$tmp/out/dependi"
        sum=$(shasum -a 256 "$tmp/out/dependi" | cut -d' ' -f1)
        printf '%s\n' "$sum" >"$tmp/out/dependi.sha256"

        mkdir -p "$cache_root/$key"
        rm -rf "$cached"
        mv "$tmp/out" "$cached"

        release
        exec "$cached/dependi" "$@"
        """#
}
