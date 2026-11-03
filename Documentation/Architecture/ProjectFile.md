# Project file

## Purpose

The project file reader answers one question. Which package products does an app target link, and which platforms does it support? It reads `project.pbxproj` through `FileReading` and implements `LinkedProductReading`. The module is `DependiProjectFile`. It knows only Foundation, the entities and the domain.

## Parts

| Part | Job |
|---|---|
| `ProjectFileReader` | The public type. Finds the target, runs the walk and builds the result. |
| `ProjectFileLoader` | Resolves the path, reads at most 64 MB and parses. |
| `ProjectModel` | The parsed objects table with checked accessors. All structure errors come from here. |
| `ProductCollector` | Walks targets and gathers products. |
| `SupportedPlatformDeriver` | Reads the build settings and returns SDK names. |
| `ProjectPathMath` | Joins and standardizes paths as text. It never touches the file system. |

## Data flow

1. The path may name the `.xcodeproj` folder or its `project.pbxproj`. The loader resolves links through `realPath`, then reads the bytes.
2. `PropertyListSerialization` parses the OpenStep text. Foundation on macOS accepts it. The model checks the root, the objects table and the project object.
3. The reader looks up the named `PBXNativeTarget` among the targets of the project.
4. The collector visits the target. For each visited target it takes the `packageProductDependencies`, then follows `dependencies`, then follows embed phases.
5. The reader removes duplicates, sorts by product name and package name, and adds the local package paths and the platforms.

## What the walk follows

- A `PBXTargetDependency` with a `target`.
- A `PBXTargetDependency` with a `targetProxy`. The proxy names the target in `remoteGlobalIDString`. A `containerPortal` that is the project itself stays in the model. Another portal must be a `PBXFileReference`. Its path is resolved against the folder that holds the `.xcodeproj`. The other project is loaded through the same file interface. When it cannot be loaded, the dependency is skipped and nothing fails.
- A `PBXCopyFilesBuildPhase` whose build files point to the product of another native target. That covers frameworks, app extensions, watch apps and app clips.
- Test targets are never visited. A product type that ends in `unit-test` or `ui-testing` is a test target.
- Each target is visited once, so a cycle ends.

## Products

A product with a remote package gets the identity of the repository URL from `PackageIdentityNormalizer`. A product with no `package` field, or with a local package reference, has no package name. Two products with one name from two packages stay apart because their package names differ.

## Local package paths

Every `XCLocalSwiftPackageReference` listed in the project `packageReferences` gives one path. The `relativePath` is resolved against the folder that holds the `.xcodeproj`, standardized and sorted.

## Platforms

The settings of all configurations of the target are read. When the target has no value for a setting, the project value is used. The result holds `SDKROOT` unless it is `auto`, all words of `SUPPORTED_PLATFORMS`, `maccatalyst` when `SUPPORTS_MACCATALYST` is `YES`, and `xros` when `SUPPORTS_XR_DESIGNED_FOR_VISIONOS` is `YES`. Values that start with `$(` are ignored. The names are lowercase and sorted. A macOS target gives `["macosx"]`.

## Edge cases

- An unknown target fails with `fileUnreadable` and lists the target names.
- Any malformed structure fails with `fileUnreadable` and a reason. A missing file gives `fileNotFound`.
- A package reference that points to nothing fails. A dependency that points to a missing object is skipped.
- A file longer than 64 MB fails and names the limit.

## Tests

The fixtures are small hand-written project files in `Tests/DependiProjectFileTests/Fixtures`. One file comes from Xcode as a smoke test. Each test loads fixtures into `InMemoryFileSystem`. Expected values are written by hand. Fuzz tests use `SeededGenerator` and check that every cut or random input fails with `fileUnreadable` and that flipped bytes never give another error.
