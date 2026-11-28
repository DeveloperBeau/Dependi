# Wizard

## A wizard must be safe to run twice

- **Trap:** A second run could add a second pane, a second ignore line or overwrite the configuration.
- **Finding:** Each step checks what is already there. A test runs the wizard twice and compares bytes.
- **Rule:** Every step is idempotent. A step that edits a user file writes a backup first.

## Never delete without a yes

- **Trap:** Files that clash with Dependi's output can look like leftovers, but a hand-written pane is the user's work.
- **Finding:** The wizard names each clashing file and asks. At the end of the input it stops with nothing removed.
- **Rule:** Removal needs a confirmation for each file.

## Nothing next to Root.plist may be a backup

- **Trap:** The first version wrote `Root.plist.bak` inside `Settings.bundle`. A real archive showed it in the shipped app.
- **Finding:** Xcode copies the whole bundle into the product.
- **Rule:** Backups go to `.dependi/`. A test checks that the bundle holds no backup file.

## Match the exact old name

- **Trap:** A loose match for the old LicensePlist pane could rewrite a pane the user wrote.
- **Finding:** A pane named `com.mono0926.LicensePlist2` is left alone by a test.
- **Rule:** Rewrite only an exact match.

## Check the project before the first write

- **Trap:** If init writes its own files first and the project edit is refused after that, the user has half a setup.
- **Finding:** A double that refuses the dry run leaves the in-memory file system with no `.dependi.json`.
- **Rule:** Call the editor with a dry run before any write. Do the real edit last, after the other steps.

## A re-run must not replace the first backup

- **Trap:** A backup that init writes on every run holds the edited file after the second run, and the original is lost.
- **Finding:** The editor returns no lines for a project that is set up, and it writes nothing then. An end-to-end test compares the backup with the original bytes after two runs.
- **Rule:** Init writes no backup of its own for the project file. Only the editor writes it, only when it changes the file and only when no backup exists. A later edit keeps the backup and says so.

## Mutation results

Fourteen entries owned by this slice are all killed. Two first came back INVALID because the mutant ignored a closure argument. Use `$0.hasPrefix("")` rather than `true` inside a closure that takes an argument.
