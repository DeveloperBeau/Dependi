# Settings bundle output

## Purpose

`DependiSettingsBundle` writes the Acknowledgements panes into the `Settings.bundle` folder of a built product. It implements `AcknowledgementWriting`. It uses only the file interfaces of the domain, so it runs on `InMemoryFileSystem` in tests.

## Parts

| Part | Job |
|---|---|
| `SettingsBundleWriter` | Plans the panes, checks the folder, writes, verifies and cleans up. |
| `OutputNameSlugger` | Gives the file name of each child pane. The writer never uses a raw package name in a path. |

The caller passes the path of the `Settings.bundle` folder. The writer writes where it is told and nowhere else. The platform rules for that path (iOS, Mac Catalyst, visionOS) belong to the caller.

## Files written

| File | Content | Owner |
|---|---|---|
| `<bundle>/Acknowledgements.plist` | The index pane. One `PSChildPaneSpecifier` per package with `Title` and `File`. | Always Dependi. Overwritten. |
| `<bundle>/Acknowledgements/<slug>.plist` | A child pane. One `PSGroupSpecifier` per license document with `Title` and `FooterText`. | Dependi, listed in the manifest. |
| `<bundle>/Acknowledgements/.dependi-manifest` | Names of the child panes, sorted, one for each line. | Dependi. |

The index and each child pane have `Title` and `StringsTable`. The `File` value has no extension, as Settings requires.

## Data flow

1. Compute the slug of each acknowledgement. Two equal slugs fail.
2. Build every plist and encode it once. The bytes are kept and written later. Text that XML cannot hold, such as a NUL character, fails here.
3. If `Acknowledgements/` exists, it must resolve to `<real bundle>/Acknowledgements`. A link, even a dangling one, fails with `fileUnwritable`.
4. Read the previous manifest. Names that are not plain `.plist` file names are ignored.
5. List `Acknowledgements/`. A name that is neither in the previous manifest nor in the new set fails with `fileUnwritable`. Nothing has been written yet. Names that start with a dot, such as `.DS_Store`, are ignored. Temporary files from an interrupted write (`<name>.plist.tmp-<UUID>`) are removed after the folder is created.
6. Create the folder. Write the manifest with the old and new names together, so a stop in the middle loses no file.
7. Write each child pane, then the index. Each file is written only when its bytes differ. After a write the file is read back through `FileReading`, decoded and compared with the input.
8. Remove the files that are in the previous manifest and not in the new set.
9. Write the final manifest.

## Output form

Plists use `PropertyListSerialization` in XML form. Foundation writes dictionary keys in sorted order, so the bytes are stable. A golden file test checks this. Arrays keep the given order.

## Edge cases

- An empty list writes an index with no entries and removes the old child panes.
- A read-only bundle fails with `fileUnwritable`.
- A manifest line such as `../Root.plist` is ignored, so cleanup cannot leave the folder.
- A user-made `Acknowledgements.plist` is replaced.
- A file in the bundle root is never touched.

## Tests

`SettingsBundleWriterTests` covers the shape of each plist, text fidelity, odd names, order, repeat runs, changed and removed packages, the unknown-file refusal, ownership, read-only and read-back failures, platform path fixtures, the golden bytes and a seeded fuzz.
