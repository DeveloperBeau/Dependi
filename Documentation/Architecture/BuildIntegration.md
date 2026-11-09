# Build integration

## Purpose

This page describes how Dependi runs inside an Xcode build, and how the contract tests prove it with the real toolchain.

## The Run Script phase

The phase runs `"${SRCROOT}/.dependi/run.sh" generate` after Copy Bundle Resources.

- The script is committed. It reads `.dependi.json`, decides in the shell whether the build is an archive or a listed configuration, and only then looks for the program.
- The program in `.dependi/bin` is ignored by git. A fresh clone or a CI machine builds the pinned commit into a cache and runs it.
- The input file list is `.dependi/inputs.xcfilelist`. The output is `Settings.bundle/Acknowledgements.plist` in the product.
- The user script sandbox must be off for the target that runs the phase. See the install guide.

## The build directory

For a normal build `BUILD_DIR` is `DerivedData/<name>/Build/Products`. For an archive it is `DerivedData/<name>/Build/Intermediates.noindex/ArchiveIntermediates/<scheme>/BuildProductsPath`. In both cases `SourcePackages` sits next to the `Build` folder. This was checked on a real archive.

## Contract tests

The `Contract` package runs the real tools. It is not part of the default test run. Run it with `sh Scripts/contract.sh`.

| Test | What it proves |
|---|---|
| Reading a package leaves the folder identical | `dump-package` with its own scratch folder writes nothing into a checkout. |
| An inherited iOS SDK breaks the manifest build | The clean child environment is needed. |
| A manifest cannot write outside its folder | SwiftPM's manifest sandbox is in force. |
| A package with four hundred targets | Large output parses. |
| The cache with the real tool | A second read starts no process. |
| A real run of generate | The whole chain works with the real `xcrun`, `swift` and file system. |
| The wrapper builds from source | A clean cache, a local origin and the real build give a working program. |
| A real archive and a Debug build | An Xcode archive contains the panes, no backup file, and a Debug build skips. |

## Run it before an upgrade

Run the contract package before each Xcode or toolchain upgrade. A failure points at the part of the tool that depends on a format or a behavior of the toolchain.
