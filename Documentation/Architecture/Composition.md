# Composition

## Purpose

`DependiComposition` is the only module that builds concrete objects and wires them together. The `dependi` executable is a few lines that call it.

## Parts

- `DependiApplication` parses the arguments, runs one command and returns the exit code. It takes the process runner and the console handles from outside.
- `LazyManifestReader` creates the package graph reader when the first manifest is needed. A build that is skipped therefore starts no process.
- `DependiVersion` holds the version text.
- `main.swift` builds a `SystemProcessRunner` and calls the application with the real arguments and environment. It is the only place that touches the process arguments.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | The command succeeded, or the build was skipped. |
| 1 | A domain error. The message names the package or file. |
| 64 | The command line is not valid. The usage text is printed. |
| 70 | The command is not available in this build. |

## The toolchain

When the first manifest is needed the reader:

1. Runs `/usr/bin/xcrun --find swift` with a clean environment.
2. Takes the toolchain version from `XCODE_PRODUCT_BUILD_VERSION`, or from `swift --version` outside Xcode.
3. Builds the child environment: `PATH=/usr/bin:/bin`, `TMPDIR`, `HOME` and `DEVELOPER_DIR` when set. It never passes `SDKROOT`.
4. Puts the scratch folder and the local manifest cache under `BUILD_DIR/dependi`, and the remote cache under `HOME/Library/Caches/dependi`.

## Tests

The end-to-end tests use the real file system, the real readers and the real writer on a project in a temporary folder. Only the process runner is recorded. They cover an archive with a direct and a transitive package, the clean process requests, an identical second run, a dropped dependency, a Mac Catalyst product, a custom configuration, a Debug skip with no process, each failure, the macro rule, a local package, two targets and the command line.
