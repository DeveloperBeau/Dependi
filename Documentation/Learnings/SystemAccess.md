# System access

## The size of a link is not the size of its target

- **Trap:** `lstat` on a link returns the length of the link text. A size check built on it accepts a link to a huge file.
- **Finding:** The domain resolves the real path first, and the reader reads the resolved file with a bound. A test links a three byte name to a file above the limit and expects `licenseTooLarge`.
- **Rule:** Measure the file that is read, never the link. Bound the read itself.

## A named pipe can hang an open

- **Trap:** Opening a named pipe for reading blocks until a writer appears.
- **Finding:** With `O_NONBLOCK` the open returns at once. `fstat` on the descriptor then shows that the file is not regular.
- **Rule:** Open with `O_NONBLOCK`, check the type on the descriptor, then read.

## O_NOFOLLOW reports a link in two ways

- **Trap:** A link in the last component fails with `ELOOP` on some paths and `ENOTDIR` on others.
- **Finding:** The behavior suite showed both. A test that only expected one would pass by luck.
- **Rule:** Map both to `notRegularFile`.

## Temporary folders on macOS are already behind a link

- **Trap:** `/var` is a link to `/private/var`. A test root from the temporary directory passes through a link, so the plain run already tests link handling by accident.
- **Finding:** `realpath` of the root differs from the root. The linked run builds its own link and asserts that the resolved path differs.
- **Rule:** Compute expected real paths with the C library in the test, not with the code under test. Foundation's `resolvingSymlinksInPath` turns `/private/var` back into `/var`.

## Case and form of names on the disk

- **Trap:** A default APFS volume ignores case and treats two forms of one accented letter as the same name.
- **Finding:** A fuzz test with mixed case would report a false collision.
- **Rule:** Fuzz names use lower case letters and precomposed characters only.

## A macro argument can hide a closure problem

- **Trap:** Two `#expect(caught { ... } == value)` calls in one test gave the first call's result for the second one.
- **Finding:** Moving each call into a `let` before the expectation fixed it.
- **Rule:** Run the call first and compare the stored result.

## Mutation results

| Mutation | Test that failed |
|---|---|
| `O_NOFOLLOW` removed | `lastComponentLinkIsRefused` |
| Regular file check removed | `folderIsRefused` |
| Read bound `limit + 1` becomes `limit` | `readStopsAfterLimitPlusOne` |
| `ENOENT` no longer gives `fileNotFound` | `missingPathHasNoRealPath` |
| `ELOOP` no longer gives `symlinkLoop` | `loopIsReported` |
| `exists` uses `stat` | `danglingLinkExists` |
| Listing is not sorted | `listingIsSorted` |
| Move does not replace a destination | `moveReplacesDestination` |
| `removeItem` follows a link | `removingLinkKeepsTarget` |
| Rename target changed | `writeIsCleanAndReplaces` |
