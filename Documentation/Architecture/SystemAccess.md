# System access

## Purpose

Two infrastructure modules reach the operating system for the domain. `DependiFileSystem` implements the three file interfaces. `DependiEnvironment` implements the environment interface. Both import only Foundation, the domain and, for the file system, Darwin.

## Parts

| Part | Role |
|---|---|
| `DiskFileSystem` | Implements `FileReading`, `FileWriting` and `DirectoryListing` with POSIX calls. It has no stored state. |
| `ProcessEnvironment` | Implements `EnvironmentReading` over a dictionary. `current()` copies the environment of the running process. |

## Data flow

### Reading

1. `realPath(of:)` calls `realpath`. A missing path or a path through a file gives `fileNotFound`. A loop of links gives `symlinkLoop`. Anything else gives `fileUnreadable` with the system text.
2. `readRegularFile(at:upToBytes:)` opens the path with `O_RDONLY`, `O_NOFOLLOW` and `O_NONBLOCK`. The last flag stops a named pipe from blocking the open.
3. It calls `fstat` on the open descriptor and requires a regular file. The check runs on the descriptor, so the file cannot change between the check and the read.
4. It reads in a loop and stops after `limit + 1` bytes. The caller learns that a file is too long without the whole file in memory.
5. The descriptor is closed on every path.

### Writing

1. `write` creates a temporary file next to the target with `O_EXCL`, writes all bytes, calls `fsync`, and renames the file over the target. A reader sees the old file or the new file, never a half file.
2. A failure removes the temporary file.
3. `createDirectory` makes each missing parent. An existing folder is success. A file in the way is an error.
4. `removeItem` uses `lstat`, so a link is removed and its target is kept. A folder is emptied and then removed.
5. `moveItem` tries `rename`. If a destination of another kind or a folder with content is in the way, it removes the destination and renames again. The destination parent must exist.

### Listing

`topLevelNames(in:)` reads the entries with `opendir` and `readdir`, drops `.` and `..`, and sorts the names. It does not look inside subfolders.

## Edge cases

- A link in the last component makes `open` fail with `ELOOP` or `ENOTDIR`. Both give `notRegularFile`.
- A dangling link exists, because `exists` uses `lstat`.
- A read with a negative limit returns at most one byte.
- Every failure message carries the `strerror` text and the name of the call.
- No error is swallowed. Cleanup after a failure never hides the first error.

## Tests

- `DiskBehaviorTests` runs the shared behavior suite twice. The second run uses a root that is reached through a link.
- `LicenseOnDiskTests` runs the license validator on a real tree: a linked root, an escaping link, a link to a large file, a loop, an escaping parent link, a named pipe, a folder, and the exact limit.
- `DiskOperationTests` and `DiskFailureTests` cover each rule and each failure, including a sparse one gigabyte file for the read bound.
- `DiskFuzzTests` writes random names with unicode and spaces. The listing must equal the sorted set that was written.
- `ProcessEnvironmentTests` covers set, missing and empty values, `current()` and random dictionaries.
