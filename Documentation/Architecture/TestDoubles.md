# Test doubles

## Purpose

`DependiTestSupport` holds one double for each domain interface. Tests use doubles so that no test calls a real service. Production code never imports this module. The architecture test checks that.

## Doubles

| Double | Stands in for |
|---|---|
| `InMemoryFileSystem` | `FileReading`, `FileWriting`, `DirectoryListing` and `FileTreeArranging` |
| `FakeEnvironment` | `EnvironmentReading` |
| `FakeProcessRunner` | `ProcessRunning`. It returns scripted results in order and records every request. |
| `FakeConsole` | `Prompting` and `OutputWriting`. It gives scripted answers. |
| `StubDependencySource`, `StubLinkedProducts` | The two project readers. They return fixed results. |
| `StubManifestReader` | `PackageManifestReading`. It counts reads for each path. |
| `RecordingAcknowledgementWriter` | `AcknowledgementWriting` |

Doubles that keep state hold it in a `LockedBox`, a value guarded by a lock.

## The behavior suite

A double that is too forgiving makes every test that uses it wrong. `FileSystemBehavior.problems` is one list of rules for the file interfaces. It builds a tree through `FileTreeArranging`, runs the interfaces against it and returns one sentence for each rule that failed.

1. The double passes the suite in this slice.
2. The real file system passes the same suite in the slice that adds it.

The suite covers exact reads, the size limit, a link in the last component, folders, pipes, chains of links, a linked parent folder, loops, a missing path, dangling links, sorted top-level listing, writes, replacement, nested folders, moves and removal.

## Why the random generator is not here

`SeededGenerator` lives in `TestHelpers`, which has no dependency on the domain. Every test target can use it, and one place owns it.

## Tests

`InMemoryFileSystemTests` runs the suite, runs it again through a linked root folder and proves that the suite fails for a reader that ignores the limit and for a reader that follows a link. `DoubleBehaviorTests` covers the other doubles.
