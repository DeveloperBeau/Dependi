# Dependency sources

## Purpose

The `DependiWorkspaceState` module reads what Xcode resolved for a project. It implements `DependencySourceReading`. It reaches the disk only through `FileReading` and `DirectoryListing`.

## Parts

| Part | Job |
|---|---|
| `WorkspaceStateReader` | The one public type. Lists the resolved packages and the pinned revisions. |
| `WorkspaceStateDocument` | Decodes only the used fields of `workspace-state.json`. |
| `PackageResolvedDocument` | Decodes the pins of `Package.resolved` in version 1, 2 or 3. |
| `DecodingDescription` | Turns a decoding failure into one sentence that names the field. |

## Resolved packages

1. Read `workspace-state.json` in the `SourcePackages` folder. The real path is resolved first. The size cap is 8 MB.
2. Decode `object.dependencies`. Other fields, and newer version numbers, are ignored.
3. For each dependency, take the identity from the normalizer applied to `packageRef.location`. The `identity` field is used only when the location is empty.
4. Map the kind.

| Kind or state | Result |
|---|---|
| `remoteSourceControl` | `.remote`, folder `checkouts/<subpath>` |
| `fileSystem`, `localSourceControl` | `.local`, folder from `location` |
| state `edited` | `.local`, folder from `state.path` |
| anything else, such as `registry` | Error that names the kind |

A remote package needs `state.checkoutState`. Its version and revision come from there. A branch checkout has a revision and no version.

## Checkout folder rules

- A `subpath` that is empty, absolute or has a `..` component is an error.
- The real path of the checkout must start with the real path of `checkouts` plus a slash. This compares by component, so `checkouts-evil` does not match `checkouts`. A link to the `checkouts` folder itself fails too.
- A missing checkout folder gives `fileNotFound` with its path.

## Pinned revisions

The first file that exists wins, in this order.

1. `*.xcworkspace/xcshareddata/swiftpm/Package.resolved`
2. `*.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`
3. `Package.resolved` at the folder root

Only the top level of the folder is listed. With no file the result is empty. Version 1 reads `object.pins[]` with `repositoryURL`. Other versions read `pins[]` with `location`. Each pin needs a revision. The key is the normalizer identity of the location. Two pins with one identity give `identityConflict`.

## Errors

Every failure is a `DomainError`. A decoding failure is `fileUnreadable` with the file path and a reason that starts with `version N`. The reason names the missing or mistyped field.

## Tests

The tests load real and hand written fixtures into `InMemoryFileSystem`. Fixtures hold `$ROOT`, which the loader replaces with a fake root. The tests cover each file version, unknown fields, missing fields, traversal, containment, local packages, search order, identity and seeded fuzz.
