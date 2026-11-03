# Build integration

## Only a real archive found two bugs

- **Trap:** The unit and end-to-end tests used recorded tool output and a fake process runner. Everything passed.
- **Finding:** The first real `xcodebuild archive` failed twice. One local package arrived as `/tmp/...` from the project file and as `/private/tmp/...` from the workspace state, and the tool counted it as two packages. The wizard's backup file `Root.plist.bak` sat inside `Settings.bundle` and shipped in the app.
- **Rule:** Keep a contract test that archives a real app. Compare paths by their real path. Never write a backup into a folder that Xcode copies.

## The archive build directory has the shape the review predicted

- **Trap:** A fixed `../..` from `BUILD_DIR` does not reach `SourcePackages` in an archive.
- **Finding:** The archive's `BUILD_DIR` is `Build/Intermediates.noindex/ArchiveIntermediates/<scheme>/BuildProductsPath`. The anchor rule in the locator handled it.
- **Rule:** Find `SourcePackages` from the `Build` folder that is followed by `Products` or `Intermediates.noindex`.

## An inherited iOS SDK breaks manifest builds

- **Trap:** A Run Script phase exports an iOS `SDKROOT`.
- **Finding:** `swift package dump-package` exits with an error when it inherits it. The contract test shows that the clean environment works.
- **Rule:** Child processes get an explicit environment.

## A fresh machine needs no installed program

- **Trap:** The installed program is ignored by git, so a clone has none.
- **Finding:** The contract test deletes `.dependi/bin` after `init`. The wrapper clones the pinned commit, builds it and runs it, and the archive succeeds.
- **Rule:** Test the path that a new teammate or a CI job takes.

## Mutation results

| Mutation | Test that failed |
|---|---|
| Local package paths compared without their real path | `localPackageWithTwoPaths` |
| The backup is not written | `paneAppended` |
| The backup is written inside the bundle | `paneAppended` |
