# Installing Dependi in an app

Dependi writes the licenses of your Swift packages into your app's `Settings.bundle` during an archive build.

## Before you start

- The app is an iOS, iPadOS, Mac Catalyst or visionOS app in an `.xcodeproj`. macOS apps have no Settings bundle.
- You can build Swift packages on this machine. Dependi builds from source and needs no download.

## Install

1. Clone the Dependi repository at the version you want.
2. In the clone run `swift run -c release dependi init --project <path to your app folder>`.
3. Answer the questions. The wizard writes `.dependi.json`, adds the Acknowledgements pane to your `Root.plist` (a backup is saved in `.dependi/`), installs `.dependi/run.sh` and adds `.dependi/bin/` to `.gitignore`.
4. To let the wizard change the Xcode project too, add `--edit-project` to the command in step 2. Close the project in Xcode first. Then go to step 7. To change the project by hand, go to step 5.
5. In Xcode, add `Settings.bundle` to the Copy Bundle Resources phase of the app target. Then add a Run Script build phase to the app target, after Copy Bundle Resources, with the text the wizard printed:

   ```
   "${SRCROOT}/.dependi/run.sh" generate
   ```

   To put every license on one page for every run of this phase, use `generate --single-page` instead. The script passes its arguments on to the program. Without the flag, the `singlePage` key in `.dependi.json` decides.

6. In that phase add the input file list `$(SRCROOT)/.dependi/inputs.xcfilelist` and the output file `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Settings.bundle/Acknowledgements.plist`.
7. Set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` for the target, as the next section says. Commit `.dependi.json` and `.dependi/run.sh` (and `.dependi/inputs.xcfilelist`).

## What `--edit-project` does

With `--edit-project`, init makes these changes to `project.pbxproj` for one app target:

- It adds a `Settings.bundle` file reference and adds the bundle to the Copy Bundle Resources phase.
- It adds a Run Script phase named Dependi after Copy Bundle Resources. The phase has the script, the input file list and the output file from step 6.
- It sets `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` in every build configuration of the target.

Init prints one line for each change. It edits only the text that it must change. Other text in the file is not changed.

Init saves the original file in `.dependi/project.pbxproj.bak` before it writes the new file. A second run does not change the file and does not write the backup again. It prints that the project is already set up. A later run that makes a new change replaces the backup.

Init checks the edit before it writes any file. If it cannot edit the project safely, it stops and changes nothing. It refuses a project file that it cannot parse, a layout that it does not support, a target with no Resources phase and a `Settings.bundle` outside the project folder. The error names the project file and the reason. If you use `--dry-run` with `--edit-project`, init prints the changes that it would make and writes nothing.

If Xcode has the project open, close it and open it again after the run, so that Xcode reads the new file.

## The script sandbox

Xcode turns the user script sandbox on by default for new targets. The sandbox blocks the package checkouts, the network and the caches that Dependi uses. Set `ENABLE_USER_SCRIPT_SANDBOXING` to `NO` for the target that runs the phase. To keep the sandbox on for your app, put the Run Script in a separate script-only (aggregate) target that the app depends on, and turn the sandbox off only there.

Dependi tells you when the sandbox is on. The error names the setting.

## What runs when

- A Debug build skips. The script decides this before it starts anything.
- An archive always runs.
- Other configurations run if they are in `gateConfigurations` in `.dependi.json`.

## Migrating from LicensePlist

The wizard changes the LicensePlist pane in `Root.plist` to the Acknowledgements pane, and offers to remove the old LicensePlist files from the source bundle. The plist shape is the same. The file names differ.

## CI and Xcode Cloud

The program in `.dependi/bin` is not committed. The script builds the pinned commit into `~/Library/Caches/dependi` on the first run. A CI cache that keeps that folder makes later runs fast. On Xcode Cloud the folder does not persist, so build the program in `ci_scripts/ci_post_clone.sh`:

```
swift build -c release --package-path <Dependi clone> --product dependi
mkdir -p .dependi/bin && cp <Dependi clone>/.build/release/dependi .dependi/bin/dependi
echo <version>-<commit> > .dependi/bin/VERSION
```

Use the same `version` and `commit` values that `.dependi.json` holds. The script compares the `VERSION` file with `<version>-<commit>`. If the two are different, the script builds the program again.

## Upgrading

1. Check out the new Dependi tag in your clone.
2. Run `init` again. It keeps your `.dependi.json`.
3. Edit `version` and `commit` in `.dependi.json` to the new version and the commit of the tag (`git rev-parse HEAD` in the clone).
4. Commit the changed files.

## Settings in `.dependi.json`

| Key | Meaning |
|---|---|
| `excludes` | Package identities to leave out. An exclude that matches no package is an error. Local packages with no license file are skipped without an exclude. |
| `manualEntries` | Code that has no package, each with a `name` and a `licensePath` inside the project. |
| `gateConfigurations` | Configurations that run besides an archive. The default is `Release`. |
| `requireLicenses` | Fail when a remote package has no license file in its checkout. The default is off. Then the package is skipped and Xcode shows a build warning that names it. |
| `singlePage` | Put every license on one page instead of one child pane for each package. The default is off. `generate --single-page` turns it on for that run. |
| `allowUnreached` | Allow resolved packages that no target of your project links. |
| `includeBuildTools` | Include the dependencies of macro and plugin targets. |
| `sourcePackagesPath` | Where `SourcePackages` is, if it is not next to the build folder. |
| `outputPath` | A path inside the product to use instead of `Settings.bundle`. |
| `version`, `commit` | The version and full commit that the script builds. |

An unknown key is an error, so a typo cannot silently use a default.

## What the build log shows

A run that writes files ends with this line:

`Dependi: wrote <N> acknowledgements to <bundle>`

If remote packages had no license file in their checkout, the line ends with `, skipped <M> with no license file`. Each skipped package also has a warning like this one:

`warning: Dependi: skipped <identity>: no license file in its checkout. Add a manualEntries item with its license, or set requireLicenses to fail the build.`

Xcode shows the warning in the issue navigator. To keep the package, add a `manualEntries` item with its license. To fail the build, set `requireLicenses`. A local package with no license file is left out with no warning and is not counted.

## How titles are made

The title of a package is `<name> (<version>)`. The name is the name that the package gives itself in its manifest. The version is the resolved version of a remote package. A package pinned by revision or branch has no version, so its title is the name only. A local package never shows a version. If the manifest name is missing, empty or has a control character, the title uses the package identity as the name. Spaces around the name and the version are removed. A manual entry keeps its own name. The list is sorted by title without case.

Before 0.3.0 the title was the lower-case identity. From 0.3.0 the title has the manifest name and the version.

tvOS is not a listed platform. If you use Dependi on tvOS anyway, Settings shows at most five lines of each license in both layouts, so show the full text in the app instead.
