# Project file

## Purpose

The project file reader answers one question. Which package products does an app target link, and which platforms does it support? It reads `project.pbxproj` through `FileReading` and implements `LinkedProductReading`. The module is `DependiProjectFile`. It knows only Foundation, CryptoKit, the entities and the domain.

The module also holds an editor. `ProjectFileEditor` changes one app target so that it runs the Dependi build step. `InitFeature` calls it through the `ProjectBuildConfiguring` interface when the user gives `--edit-project`.

## Parts

| Part | Job |
|---|---|
| `ProjectFileReader` | The public type. Finds the target, runs the walk and builds the result. |
| `ProjectFileLoader` | Resolves the path, reads at most 64 MB and parses. |
| `ProjectModel` | The parsed objects table with checked accessors. All structure errors come from here. |
| `ProductCollector` | Walks targets and gathers products. It keeps the other projects that it loads. |
| `LegacyLocalPackages` | Finds local packages that an older Xcode wrote as folder file references. |
| `ReferencePathResolver` | Resolves the path of a group member from its source tree and its group chain. `LegacyLocalPackages` and the editor both use it. |
| `ProjectFileEditor` | The public editing type. Plans, checks and writes the edit. |
| `BuildSetupPlanner` | Works out the text edits for one target. |
| `BuildSetupPlan` | Holds the edits, the report lines and the ids that the edits touch. It also checks the result. |
| `PBXTextScanner` | Splits the project text into spans with byte positions. |
| `PBXTextSpan` | One word, string or mark of punctuation with its byte range. |
| `PBXTextEdit` | One change to the bytes: an offset, a count of bytes to remove and the text to insert. |
| `ProjectObjectIDMaker` | Makes the ids of new objects. |
| `PackageTraitCollector` | Gathers the traits that the package references pick. |
| `SupportedPlatformDeriver` | Reads the build settings and returns SDK names. |
| `ProjectPathMath` | Joins and standardizes paths as text. It never touches the file system. |

## Data flow

1. The path may name the `.xcodeproj` folder or its `project.pbxproj`. The loader resolves links through `realPath`, then reads the bytes.
2. `PropertyListSerialization` parses the OpenStep text. Foundation on macOS accepts it. The model checks the root, the objects table and the project object.
3. The reader looks up the named `PBXNativeTarget` among the targets of the project.
4. The collector visits the target. For each visited target it takes the `packageProductDependencies`, then follows `dependencies`, then follows embed phases.
5. A second walk visits every native target of the project, test targets included. Its products, minus the app's own, are the other products. A target of that walk that cannot be read is ignored.
6. The reader removes duplicates, sorts by product name and package name, and adds the local package paths, the platforms and the package traits.

## What the walk follows

- A `PBXTargetDependency` with a `target`.
- A `PBXTargetDependency` with a `targetProxy`. The proxy names the target in `remoteGlobalIDString`. A `containerPortal` that is the project itself stays in the model. Another portal must be a `PBXFileReference`. Its path is resolved against the folder that holds the `.xcodeproj`. The other project is loaded through the same file interface. When it cannot be loaded, the dependency is skipped and nothing fails.
- A `PBXCopyFilesBuildPhase` whose build files point to the product of another native target. That covers frameworks, app extensions, watch apps and app clips.
- Test targets are never visited for the app's own products. A product type that ends in `unit-test` or `ui-testing` is a test target.
- Each target is visited once, so a cycle ends.

## Products

A product with a remote package gets the identity of the repository URL from `PackageIdentityNormalizer`. A product with no `package` field, or with a local package reference, has no package name. Two products with one name from two packages stay apart because their package names differ.

## Local package paths

Every `XCLocalSwiftPackageReference` listed in the project `packageReferences` gives one path. The `relativePath` is resolved against the folder that holds the `.xcodeproj`, standardized and sorted.

Older Xcode versions wrote a local package as a `PBXFileReference` folder. Its `lastKnownFileType` or `explicitFileType` is `wrapper` or `folder`. `LegacyLocalPackages` treats such a reference as a local package when its folder holds a `Package.swift`. It joins the `path` of the reference with the `path` of each group above it. The `sourceTree` decides the start of the join. `<group>` goes up to the main group, which stands for the project folder. `SOURCE_ROOT` starts at the project folder. `<absolute>` starts at the root. Any other tree, such as `SDKROOT`, is not a package. A group cycle ends the search for that reference. The paths join the paths of the local references, and a folder that appears twice is listed once.

The product dependencies of such a package have no `package` key. The collector gives them no package name. The resolver then matches them to a local package by product name. A product that no local package provides fails with `productUnmatched` and names the product.

## Package traits

Since Xcode 26.4 an app can pick the traits of each package. Xcode writes them as `traits` on the `XCRemoteSwiftPackageReference` and `XCLocalSwiftPackageReference` objects. The reader reads the `packageReferences` of the project and of every other project that the walk of the app loaded. `packageTraits` holds the result, keyed by the repository URL as written or by the resolved local path.

- No `traits` key gives `["default"]` under the location of that reference.
- `traits = ( );` gives an empty entry, which turns the defaults off.
- A list gives exactly those names. It does not add `default`.
- The reader does not match references to one package. Two references with the same location join their names. References with different spellings of one package keep separate entries. The resolver joins the picks of the locations that name one package, so a package with a reference that has no key also gets `default`.
- A `traits` value that is not a list of names fails with `fileUnreadable` and names the reference. So does a remote reference that has `traits` but no `repositoryURL`. A remote reference with neither is skipped.

## Platforms

The settings of all configurations of the target are read. When the target has no value for a setting, the project value is used. The result holds `SDKROOT` unless it is `auto`, all words of `SUPPORTED_PLATFORMS`, `maccatalyst` when `SUPPORTS_MACCATALYST` is `YES`, and `xros` when `SUPPORTS_XR_DESIGNED_FOR_VISIONOS` is `YES`. Values that start with `$(` are ignored. The names are lowercase and sorted. A macOS target gives `["macosx"]`.

## Edge cases

- An unknown target fails with `fileUnreadable` and lists the target names.
- Any malformed structure fails with `fileUnreadable` and a reason. A missing file gives `fileNotFound`.
- A package reference that points to nothing fails. A dependency that points to a missing object is skipped.
- A file longer than 64 MB fails and names the limit.

## Editing the build setup

`ProjectFileEditor.configureBuild` makes three changes to one app target. It adds `Settings.bundle` to Copy Bundle Resources. It adds a Run Script phase named Dependi after that phase. It sets `ENABLE_USER_SCRIPT_SANDBOXING = NO` in every build configuration of the target. It returns one line for each change. An empty list means that the project needed no change.

The editor changes the text of `project.pbxproj` and nothing else. It does not parse and print the file again, because that would change the layout that Xcode wrote. Each edit inserts whole lines, or replaces one value. All other bytes stay as they were.

### Data flow of an edit

1. `ProjectFileLoader` loads the file and `ProjectModel` parses it. The model gives the meaning: the target, its phases, its configurations and the file references.
2. The editor refuses text that it cannot lay out. See Refusals.
3. `PBXTextScanner` splits the text into spans. It skips comments, so a name inside a comment never counts. A quoted string is one span, so a name inside a string never counts either.
4. `BuildSetupPlanner` asks the model what is missing. It asks the scanner where each piece of text goes. It gives a `BuildSetupPlan`.
5. If the plan has no edits, the editor returns the warning lines only and writes nothing.
6. `BuildSetupPlan.apply` applies the edits from the last offset to the first, so earlier offsets stay valid.
7. The editor parses the new bytes and calls `BuildSetupPlan.verify`. It then plans again on the new text. A correct edit leaves nothing to do. If a check fails, nothing is written.
8. In a dry run the editor returns the lines here. Otherwise it writes the backup and then replaces the project file.

### Supported layout

The layout is the one that Xcode writes. Each object line is indented with tabs. `PBXBuildFile` and `PBXFileReference` entries have their own `/* Begin X section */` and `/* End X section */` lines. Lists and build settings have one entry on each line.

- A new `PBXBuildFile` or `PBXFileReference` line goes before the first line whose id sorts after the new id. If no id sorts after it, the line goes before the End marker.
- A missing `PBXShellScriptBuildPhase` section is created between the sections whose names sort before and after it. Xcode orders sections by name.
- A new list item goes after the last item. The Dependi phase goes right after the Copy Bundle Resources phase.
- A missing build setting goes before the first key that sorts after it in byte order. A setting with another value is replaced at its value only. The key, the spacing and the semicolon stay.
- The file reference goes in the main group. It has `sourceTree = SOURCE_ROOT` and a path that is relative to the folder that holds the `.xcodeproj`. The reference has `name = Settings.bundle` only when the path has a folder, as Xcode does. The path is quoted when it holds more than letters, digits, `_`, `.` and `/`.
- The value `NO` and the value `"NO"` both count as done.
- A build setting at project level or in a configuration file is not changed. The setting in the target wins over both. When the editor adds the setting to a configuration that has a configuration file, it adds a line that says so.

Cases that the editor handles on purpose:

| Case | Result |
|---|---|
| The target already copies the bundle | No resource edit. |
| A file reference to the bundle exists, but this target does not copy it | The reference is reused. Only the build file and the list item are added. |
| A build file has no `fileRef`, such as `(null) in Resources` | It is ignored. |
| A folder reference holds the bundle inside | It does not count. Xcode copies it under the folder name, and iOS reads `Settings.bundle` only at the top of the app. |
| A synchronized folder of the target holds the bundle | No reference is added, because Xcode already copies it. |
| A Dependi phase exists before Copy Bundle Resources | The phase stays. The editor reports a warning and does not move it. |
| The project file is a link | The editor changes the real file and backs up its bytes. |

### Refusals

The editor refuses with `DomainError` and writes nothing when:

- the file does not parse, is cut, or has a comment or string that is not closed
- the lines end with CR LF, or a line is indented with spaces
- a section marker, a list or a build settings dictionary that it needs is missing, or is not laid out in lines
- the target name is unknown. The message lists the targets.
- the bundle path is not inside the project folder, or its last part is not `Settings.bundle`
- the target has no Copy Bundle Resources phase. Dependi does not create one.
- the target copies another `Settings.bundle`, because two bundles with one name collide in the product
- a synchronized folder leaves the bundle out of the target through a membership exception

### Object ids

A new id is 24 upper case hex digits. They are the first 12 bytes of a SHA-256 digest of a fixed prefix, the target id, a role and a counter. The roles are `fileReference`, `buildFile` and `scriptPhase`. The same input always gives the same id, so a test can write the expected text by hand. An id that appears anywhere in the project text, even in a comment, is skipped. So is an id that the run made before. This also covers projects with hand-made ids.

### Backup and write

The editor writes the original bytes to the backup path before it writes the project file. It reads the backup back and compares the bytes. It writes only when the project changes, so a re-run never replaces a good backup with edited bytes. The new text goes to a file next to the project file. A move then replaces the project file. If the write fails, the editor removes the temporary file. The caller gives the backup path. Before the backup, the editor creates the folder of the backup path, and only when it writes.

### Verify

`BuildSetupPlan.verify` compares the model before and after the edit.

- The number of objects is the old number plus the added ids.
- Every object that is not planned is equal to the old one.
- An edited object differs only in `files`, `children`, `buildPhases` or `buildSettings`. A list keeps its old items in the old order. `buildSettings` differs only in the sandbox setting.

The planner then runs again on the new text. It must find nothing to do. This proves that the scanner and the parser agree about the new file.

## Tests

The fixtures are small hand-written project files in `Tests/DependiProjectFileTests/Fixtures`. One file comes from Xcode as a smoke test. Each test loads fixtures into `InMemoryFileSystem`. Expected values are written by hand. Fuzz tests use `SeededGenerator` and check that every cut or random input fails with `fileUnreadable` and that flipped bytes never give another error.

The editor tests use five real project files. `Tests/DependiProjectFileTests/Fixtures/SOURCES.md` names the source and the licence of each one. A damaged file is made in the test from a real file, so no damaged file is stored. The tests check hand-written lines of the report and the new text, a re-run that is byte identical with no write, a line diff that shows only added lines, the order of the writes, and the refusals. Fuzz tests are seeded and print the seed. They check damaged bytes, names in comments and strings that are not real, and other spellings of a finished project.
