# Settings bundle output

## Purpose

`DependiSettingsBundle` writes the Acknowledgements panes into the `Settings.bundle` folder of a built product. It implements `AcknowledgementWriting`. It uses only the file interfaces of the domain, so it runs on `InMemoryFileSystem` in tests.

## Parts

| Part | Job |
|---|---|
| `SettingsBundleWriter` | Plans the panes, checks the folder, writes, verifies and cleans up. |
| `OutputNameSlugger` | Gives the file name of each child pane. The writer never uses a raw package name in a path. |

The caller passes the path of the `Settings.bundle` folder. The writer writes where it is told and nowhere else. The platform rules for that path (iOS, Mac Catalyst, visionOS) belong to the caller.

## Layouts

The writer takes an `AcknowledgementLayout` when it is created. The composition passes `panePerPackage`. Nothing in the tool passes `singlePage` yet.

| Layout | Output |
|---|---|
| `panePerPackage` | An index pane with one child pane for each package. The sections below describe it. |
| `singlePage` | Every license on the index pane itself. There are no child panes. |

### Single page

The single page layout writes `<bundle>/Acknowledgements.plist` with `Title` and `StringsTable`. Its `PreferenceSpecifiers` hold one `PSGroupSpecifier` for each license document, in the given package order and then in document order. The group `Title` is the display name when the package has one document. With two or more documents it is `<display name> (<file name>)`. `FooterText` is the license text. A package with no documents gives one group with only a `Title`, so no package is dropped. Two packages with the same display name both appear. No slugs are used.

The single page layout never creates `Acknowledgements/`. If the folder does not exist, the index is the only file written.

If the folder exists, the run does this:

1. Encode the index. Text that XML cannot hold fails here with `fileUnwritable`, before any write.
2. Refuse a link where the folder belongs, as in the other layout.
3. Read the previous manifest. List the temporary leftovers in the folder.
4. Write the index.
5. Remove each name in the previous manifest that exists in the folder. Then remove the temporary leftovers.
6. Write the manifest with no bytes.

Nothing else is written into the folder. A file that Dependi did not write stays where it is and does not fail the run. The index is written before any removal, so a stop in the middle never leaves the index pointing at a removed pane. The manifest is written last, so it still names any pane that was not removed yet. Each file is written only when its bytes differ, and is read back and checked. A second run with the same input writes nothing.

### Switching layouts

A switch from `panePerPackage` to `singlePage` removes the child panes that the manifest names and leaves an empty manifest. A switch back finds only the empty manifest in the folder. The manifest is tolerated, so the child panes are written again.

## Files written

These are the files of the `panePerPackage` layout.

| File | Content | Owner |
|---|---|---|
| `<bundle>/Acknowledgements.plist` | The index pane. One `PSChildPaneSpecifier` per package with `Title` and `File`. | Always Dependi. Overwritten. |
| `<bundle>/Acknowledgements/<slug>.plist` | A child pane. One `PSGroupSpecifier` per license document with `Title` and `FooterText`. | Dependi, listed in the manifest. |
| `<bundle>/Acknowledgements/.dependi-manifest` | Names of the child panes, sorted, one for each line. | Dependi. |

The index and each child pane have `Title` and `StringsTable`. The `File` value has no extension, as Settings requires.

## Data flow

This is the flow of the `panePerPackage` layout.

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

`SinglePageLayoutTests` covers the single page shape, the titles, a package with no documents, equal display names, both switches between layouts, temporary leftovers, the write order, repeat runs, the link refusal, a NUL in a text, read-only and read-back failures, the golden bytes and a seeded fuzz.
