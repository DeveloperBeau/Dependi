# Wizard

## Purpose

`dependi init --project <path>` sets Dependi up in an app project. `--dry-run` reports the plan and changes nothing.

## Parts

- `InitFeature` runs the steps. It takes every outside capability, the running program, the Dependi source folder if there is one, the wrapper script text and the version.
- `ProjectLocator` finds the project from the path that was given.
- `RootPlistEditor` adds the Acknowledgements pane to a `Root.plist`.
- `ApplicationTargetListing` is a domain interface. `ProjectFileReader` implements it.
- `ExecutableMarking` is a domain interface. `DiskFileSystem` implements it with `chmod`.

## Steps

1. Find the project. The path may be a folder, an `.xcodeproj`, or an `.xcworkspace` with an `.xcodeproj` of the same name next to it. Two projects in a folder ask which one. A Swift package, an empty folder and the Dependi source folder are refused.
2. List the application targets. None is refused. Two or more ask which one.
3. Read the platforms of the target. A macOS-only app is refused, because it has no Settings bundle.
4. In a dry run, print the plan and stop.
5. Write `.dependi.json` if there is none. It holds the version, the pinned commit and the local packages under the project folder as excludes. An existing file is never changed.
6. Find a `Settings.bundle` in the project folder or one folder below it. Two ask which one. If there is none, create `Settings.bundle/Root.plist` and say that the bundle must be added to the target.
7. Edit `Root.plist`:
   - If a pane with `File` equal to `Acknowledgements` exists, change nothing.
   - If the old LicensePlist pane exists, change its `File` and keep its other keys and its place.
   - Otherwise append the pane.
   - Write the old file to `.dependi/Root.plist.bak` first. The backup stays outside the bundle, because everything inside `Settings.bundle` ships in the app. Keep the format, XML or binary.
8. If the source bundle holds `Acknowledgements`, or old LicensePlist files, name them and ask before removing each one. Without a yes nothing is removed.
9. Copy the running program to `.dependi/bin/dependi`, write `VERSION`, `run.sh` and `inputs.xcfilelist`, and mark the program and the script executable.
10. Add `.dependi/bin/` to `.gitignore` once.
11. Print the Run Script text and the settings to change.

## The pinned commit

The wizard asks git for the commit of the Dependi source folder. If there is no source folder or git fails, it leaves the commit out and says so. The wrapper cannot build from source without a commit, so the line must be added by hand.

## What the wizard does not do

It does not edit `project.pbxproj`. A round trip through a property list writer reorders keys and strips comments. It prints the Run Script instead.

## Tests

The tests use the in-memory file system and the scripted console. They cover a fresh install, a dry run, a second run, an existing configuration, each `Root.plist` case including binary format and a seeded fuzz, bundle search and clashes, the ignore file, every form of project path, targets and platforms.
