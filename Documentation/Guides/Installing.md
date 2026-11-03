# Installing Dependi in an app

Dependi writes the licenses of your Swift packages into your app's `Settings.bundle` during an archive build.

## Before you start

- The app is an iOS, iPadOS, Mac Catalyst or visionOS app in an `.xcodeproj`. macOS apps have no Settings bundle.
- You can build Swift packages on this machine. Dependi builds from source and needs no download.

## Install

1. Clone the Dependi repository at the version you want.
2. In the clone run `swift run -c release dependi init --project <path to your app folder>`.
3. Answer the questions. The wizard writes `.dependi.json`, adds the Acknowledgements pane to your `Root.plist` (a backup is saved in `.dependi/`), installs `.dependi/run.sh` and adds `.dependi/bin/` to `.gitignore`.
4. In Xcode, add a Run Script build phase to the app target, after Copy Bundle Resources, with the text the wizard printed:

   ```
   "${SRCROOT}/.dependi/run.sh" generate
   ```

5. In that phase add the input file list `$(SRCROOT)/.dependi/inputs.xcfilelist` and the output file `$(TARGET_BUILD_DIR)/$(UNLOCALIZED_RESOURCES_FOLDER_PATH)/Settings.bundle/Acknowledgements.plist`.
6. Commit `.dependi.json` and `.dependi/run.sh` (and `.dependi/inputs.xcfilelist`).

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
echo <version> > .dependi/bin/VERSION
```

## Upgrading

1. Check out the new Dependi tag in your clone.
2. Run `init` again. It keeps your `.dependi.json`.
3. Edit `version` and `commit` in `.dependi.json` to the new version and the commit of the tag (`git rev-parse HEAD` in the clone).
4. Commit the changed files.

## Settings in `.dependi.json`

| Key | Meaning |
|---|---|
| `excludes` | Package names to leave out. The wizard excludes your own local packages. |
| `manualEntries` | Code that has no package, each with a `name` and a `licensePath` inside the project. |
| `gateConfigurations` | Configurations that run besides an archive. The default is `Release`. |
| `allowUnreached` | Allow resolved packages that your app does not link. |
| `includeBuildTools` | Include the dependencies of macro and plugin targets. |
| `sourcePackagesPath` | Where `SourcePackages` is, if it is not next to the build folder. |
| `outputPath` | A path inside the product to use instead of `Settings.bundle`. |
| `version`, `commit` | The version and full commit that the script builds. |

An unknown key is an error, so a typo cannot silently use a default.
