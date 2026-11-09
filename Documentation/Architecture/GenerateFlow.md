# Generate flow

## Purpose

`DependiGenerate` runs once for a build. It turns the Xcode build settings and the project files into acknowledgements and hands them to the writer. It uses domain interfaces only, so it runs with doubles.

## Parts

- `GenerateFeature` holds the flow. Its initializer takes every outside capability.
- `GenerateOutcome` says whether the run wrote or skipped.
- `BuildContextReader` turns environment variables into a `BuildContext`. A variable that is not set or is empty is `nil`.
- `PlatformNames` maps an Xcode platform name to the platform names that manifests use. A Catalyst-enabled macOS build uses `maccatalyst` and `ios`.
- `OutputLocation` works out the settings bundle path and checks it.

## Flow

1. Read the build context.
2. Load the configuration. Without `PROJECT_DIR` the load fails.
3. Ask the gate. A skip logs one line, writes nothing and returns.
4. Fail if the user script sandbox is on. This comes after the gate, so a Debug build with the sandbox on still skips. The wrapper's cheap pre-gate also exits before the tool starts.
5. Fail if `PROJECT_FILE_PATH` or `TARGET_NAME` is missing.
6. Find `SourcePackages`.
7. Read the resolved packages and the pinned revisions. A checkout at another revision than the pin fails.
8. Read the linked products of the target.
9. Add the local packages that the project file lists to the local packages from the workspace state.
10. Resolve the linked packages. Excludes apply. A resolved package that nothing reaches fails unless `allowUnreached` is set. A package that a test target or another target of the project links, directly or through its dependencies, is expected and is not reported. So is a package that only a build tool product reaches. A package that nothing in the project links is still reported. A package that only another project of the workspace links is reported too, so set `allowUnreached` for such a workspace.
11. For each linked package list the top level of its folder, pick the license files and validate each.
12. Add the manual entries. Each license path must be relative and stay inside the project folder.
13. Assemble. A package without a license, a duplicate identity and an output name clash fail here.
14. Work out the bundle path and write.
15. Log the number written.

## Where the bundle goes

The bundle is `TARGET_BUILD_DIR/UNLOCALIZED_RESOURCES_FOLDER_PATH/Settings.bundle`. For an iOS product that is `App.app/Settings.bundle`. For Mac Catalyst it is `App.app/Contents/Resources/Settings.bundle`. A configured `outputPath` replaces `Settings.bundle`. Every part must be relative and must not contain `..`. `TARGET_BUILD_DIR` must be absolute. Every existing part of the product folder and of the bundle path must resolve to itself. A link, even a dangling one, is refused with `invalidOutputLocation`, because it would send the writes elsewhere. The check runs before any write.

## Errors

A permission error while reading packages is reported as the script sandbox being on, because that is its usual cause.

## Tests

The unit tests use doubles for every collaborator. They cover the archive path, the Debug skip with no package read, each failure, each output path case, a Catalyst product, local packages, platform conditions and a repeated run.
