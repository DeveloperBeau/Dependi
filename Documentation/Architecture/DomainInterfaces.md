# Domain interfaces

## Purpose

`DependiDomain` owns the interfaces for every outside capability. Infrastructure modules implement them. Features and domain logic use them. Nothing in the domain touches the file system, a process, the environment or the console.

## Interfaces

| Interface | Capability |
|---|---|
| `FileReading` | Resolve real paths, read a regular file up to a limit, test for existence. |
| `FileWriting` | Write, create a folder, remove and move. |
| `DirectoryListing` | List the top level of one folder. |
| `EnvironmentReading` | Read one variable. |
| `ProcessRunning` | Run a `ProcessRequest` and return a `ProcessOutput`. |
| `Prompting` | Ask a choice or a yes or no question. |
| `OutputWriting` | Write a line to the normal or the error output. |
| `DependencySourceReading` | Resolved packages and pinned revisions. |
| `LinkedProductReading` | The products a target links, with local package paths and platforms. |
| `PackageManifestReading` | The products and targets of one package. |
| `AcknowledgementWriting` | Write panes into a settings bundle. |

All interfaces are `Sendable`. All operations that can fail use typed throws with `DomainError`, the one error enumeration of the module.

## Rules built into the interfaces

1. `readRegularFile` takes a path that is already resolved. It refuses a link, a folder, a pipe and a device. It returns at most one byte more than the limit, so a caller can see that a file is too long.
2. `ProcessRequest` carries a complete environment, a time limit and an output limit. A runner never inherits the environment of its parent.
3. Prompts fail with `inputEnded` at the end of the input. They never loop.
4. Data types that belong to one interface, such as `ManifestTarget`, live in this module.

## Tests

The interfaces have no logic, so their tests are the behavior suites. See "Test doubles".
