# Dependi

Dependi collects the licenses of the Swift packages that your iOS, iPadOS, Mac Catalyst or visionOS app links, and writes them into the app's `Settings.bundle` when you archive. It has no third-party dependencies.

It reads the packages that Xcode resolved, follows the products that your app target really links (direct, transitive, local, and those linked by embedded frameworks and extensions), picks the license files of each package and writes one pane for each package under an Acknowledgements pane. A single page layout that puts every license on one page is also available. See the [settings table](Documentation/Guides/Installing.md#settings-in-dependijson).

## Install

See [the install guide](Documentation/Guides/Installing.md). In short:

1. Clone this repository at the version you want.
2. Run `swift run -c release dependi init --project <path to your app>`.
3. Run init with `--edit-project` to let it add the Run Script phase, the bundle and the sandbox setting, or add them by hand. See [Set up Xcode by hand](#set-up-xcode-by-hand).

## Set up Xcode by hand

If you do not use `--edit-project`, make these three changes in Xcode:

1. Add `Settings.bundle` to the Copy Bundle Resources phase of the app target.
2. Add a Run Script build phase to the app target, after Copy Bundle Resources, with this text: `"${SRCROOT}/.dependi/run.sh" generate`. Add the input file list `$(SRCROOT)/.dependi/inputs.xcfilelist` and the output file `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Settings.bundle/Acknowledgements.plist`.
3. Set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` for that target.

## How it runs

The Run Script phase calls `.dependi/run.sh`. The script decides before it starts anything whether the build is an archive or a configuration you listed, and skips otherwise. If the program in `.dependi/bin` is not the pinned version, the script clones the pinned commit, builds it and caches it.

Debug builds skip. An archive always runs.

## What it checks

- A remote package that the app links and that has no license file in its checkout is skipped. Xcode shows a build warning that names the package, and the run summary counts the skips. Add a `manualEntries` item with its license, or set `requireLicenses` in `.dependi.json` to make this a failure.
- Each package title is `<name> (<version>)`. The name is the name in the package manifest. The version is the resolved version of a remote package. A package pinned by revision or branch shows the name only. A local package never shows a version. If the manifest name is missing, empty or has a control character, the title uses the package identity as the name. Before 0.3.0 the title was the lower-case identity. From 0.3.0 the title has the manifest name and the version.
- A dependency that a package ties to a SwiftPM trait is followed only when that trait is on. A package that the app links, or that is local, has the traits that the project picks for it in the Package Dependencies tab of Xcode. With no pick it has its default traits. An empty pick turns the defaults off, and a list of names turns on only those names. A package also has the traits that the packages which use it ask for. A trait that another trait enables is on too.
- Local packages, also the local packages that other local packages name with `.package(path:)`, are followed to find the remote packages that they use. A local package with no license file is left out of the output.
- By default the Acknowledgements pane has one child pane for each package. Set `singlePage` in `.dependi.json` to put every license on one page instead. See the [settings table](Documentation/Guides/Installing.md#settings-in-dependijson).
- Manual entries add a name and a license text file from the project for code that has no package.
- The Acknowledgements pane lists packages and manual entries in one list, sorted by title without case, then by identity. The order does not depend on the locale or on the order of the input.
- License files are regular files inside their package, within 1 MB, valid text and free of control characters.
- A checkout is at the revision that `Package.resolved` pins.
- Resolved packages that the app does not link fail the build unless you allow them.
- The output is written only inside the built product, and only files that Dependi made are ever removed.

## Command line

| Command | Meaning |
|---|---|
| `dependi generate [--single-page]` | Write the acknowledgements. Xcode runs it. `--single-page` puts every license on one page for that run. Without it, the `singlePage` key decides. |
| `dependi init --project <path> [--dry-run] [--edit-project]` | Set Dependi up in a project. `--edit-project` also edits the Xcode project: it adds the bundle, the Run Script phase and the sandbox setting, and saves a backup in `.dependi/project.pbxproj.bak`. Without it, init never changes the project file. |
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
| Full gate: lint, package dump check, build, tests, and the runner check when the runner changed | `sh Scripts/gate.sh` |
| Lint only | `sh Scripts/lint.sh` |
| Refresh the recorded package dump after a change to `Package.swift` | `sh Scripts/refresh-package-dump.sh` |
| Contract tests with the real toolchain and a real archive | `sh Scripts/contract.sh` |
| Mutation register | `swiftc Scripts/mutate.swift -o mutate && ./mutate --root .` |

Every rule has an entry in the [mutation register](Documentation/Registers/mutations.md). The runner breaks the code on purpose and requires a named test to fail.

## Requirements

Built and tested with Xcode 27.2 (Swift 6.4) on macOS 27. The package declares macOS 14 as its minimum. Other Xcode versions are not tested yet.

## License

Dependi is released under the [Apache License 2.0](LICENSE).
