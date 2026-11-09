# Settings bundle output

## A manifest line is input too

- **Trap:** Cleanup deletes what the manifest lists. A manifest line such as `../Root.plist` would leave the folder.
- **Finding:** The in-memory file system resolves `..`, so the planted line removed a file in the bundle root.
- **Rule:** Accept only plain `.plist` names from the manifest. A test plants an escaping line.

## Check everything before the first write

- **Trap:** A file that Dependi did not write was found after the new panes were written. The build failed with half an output.
- **Finding:** A counting writer showed writes before the failure.
- **Rule:** Encode every plist and check the folder first. A failing run writes nothing.

## XML cannot hold a NUL character

- **Trap:** A name with a NUL character cannot round trip through an XML plist.
- **Finding:** The read-back comparison failed after the files were written.
- **Rule:** Encode and decode in the planning step. The run fails with `fileUnwritable` before any write.

## Write the manifest twice

- **Trap:** A stop between writing panes and writing the manifest leaves panes that no manifest lists. The next run refuses them as unknown files.
- **Finding:** Found by reading the data flow, not by a failure.
- **Rule:** Write a manifest with old and new names first. Write the final manifest last. A repeat run writes neither, because the bytes match.

## Foundation keeps carriage returns in XML plists

- **Trap:** XML parsers turn a raw carriage return into a line feed.
- **Finding:** Foundation writes the raw character and reads it back unchanged. The golden file holds one, and the text tests compare bytes.
- **Rule:** Compare the text through the same decoder that the system uses. Keep the CRLF case in the tests.

## Mutation results

The 7 entries owned by this slice are listed in `Documentation/Registers/mutations.md`. See the table there for the result of each.
