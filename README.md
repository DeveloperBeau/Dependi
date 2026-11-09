# Dependi

Dependi collects the licenses of the Swift packages that your iOS, iPadOS, Mac Catalyst or visionOS app links, and writes them into the app's `Settings.bundle` when you archive. It has no third-party dependencies.

It reads the packages that Xcode resolved, follows the products that your app target really links (direct, transitive, local, and those linked by embedded frameworks and extensions), picks the license files of each package and writes one pane for each package under an Acknowledgements pane.

## Install

See [the install guide](Documentation/Guides/Installing.md). In short:

1. Clone this repository at the version you want.
2. Run `swift run -c release dependi init --project <path to your app>`.
3. Add the Run Script phase that the wizard prints, and turn the user script sandbox off for the target that runs it.

## How it runs

The Run Script phase calls `.dependi/run.sh`. The script decides before it starts anything whether the build is an archive or a configuration you listed, and skips otherwise. If the program in `.dependi/bin` is not the pinned version, the script clones the pinned commit, builds it and caches it.

Debug builds skip. An archive always runs.

## What it checks

- A remote package that the app links and that has no license file is skipped, and the build log names it. Set `requireLicenses` in `.dependi.json` to make this a failure.
- Local packages, also the local packages that other local packages name with `.package(path:)`, are followed to find the remote packages that they use. A local package with no license file is left out of the output.
- Manual entries add a name and a license text file from the project for code that has no package.
- The Acknowledgements pane lists packages and manual entries in one list, sorted by name without case, then by identity. The order does not depend on the locale or on the order of the input.
- License files are regular files inside their package, within 1 MB, valid text and free of control characters.
- A checkout is at the revision that `Package.resolved` pins.
- Resolved packages that the app does not link fail the build unless you allow them.
- The output is written only inside the built product, and only files that Dependi made are ever removed.

## Command line

| Command | Meaning |
|---|---|
| `dependi generate` | Write the acknowledgements. Xcode runs it. |
| `dependi init --project <path> [--dry-run]` | Set Dependi up in a project. |
| `dependi --version` | Print the version. |
| `dependi help` | Print the usage. |

## Layout of the code

Code lives in rings, and a test checks that a module depends only on a ring further in.

| Ring | Modules |
|---|---|
| Entities | `DependiEntities` |
| Domain | `DependiDomain` |
| Infrastructure | `DependiFileSystem`, `DependiEnvironment`, `DependiProcess`, `DependiConsole`, `DependiWorkspaceState`, `DependiProjectFile`, `DependiPackageGraph`, `DependiSettingsBundle` |
| Features | `DependiGenerate`, `DependiInit`, `DependiCommandLine` |
| Composition | `DependiComposition`, `dependi` |

Read [standards.md](standards.md) first. The pages in [Documentation/Architecture](Documentation/Architecture/README.md) describe each part. The pages in [Documentation/Learnings](Documentation/Learnings/README.md) record the traps that were found and the rules that follow.

## Working on Dependi

| Task | Command |
|---|---|
| Full gate: lint, build, tests, each module on its own | `sh Scripts/gate.sh` |
| Lint only | `sh Scripts/lint.sh` |
| Refresh the recorded package dump after a change to `Package.swift` | `sh Scripts/refresh-package-dump.sh` |
| Contract tests with the real toolchain and a real archive | `sh Scripts/contract.sh` |
| Mutation register | `swiftc Scripts/mutate.swift -o mutate && ./mutate --root .` |

Every rule has an entry in the [mutation register](Documentation/Registers/mutations.md). The runner breaks the code on purpose and requires a named test to fail.

## Requirements

Built and tested with Xcode 27.2 (Swift 6.4) on macOS 27. The package declares macOS 14 as its minimum. Other Xcode versions are not tested yet.

## License

Dependi is released under the [Apache License 2.0](LICENSE).
