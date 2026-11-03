# Domain logic

## Purpose

The domain logic turns raw project data into the list of acknowledgements to write. It uses the interfaces only. It runs with doubles and needs no file system, process or build.

## Types

| Type | Job |
|---|---|
| `PackageIdentityNormalizer` | Turns a URL or path into an identity and a normalized location. |
| `SourcePackagesLocator` | Finds `SourcePackages` from the build directory. |
| `ConfigurationLoader` | Reads `.dependi.json` and maps failures to errors. |
| `ReleaseGate` | Decides whether a build runs. |
| `LinkedPackageResolver` | Joins products to packages and follows the product graph. |
| `LicenseLocator` | Picks license file names from a folder listing. |
| `LicenseFileValidator` | Checks containment, size, file kind and text of one license file. |
| `OutputNameSlugger` | Makes a safe output file name. |
| `AcknowledgementAssembler` | Checks for missing licenses and name clashes, then sorts. |

## Identity

1. The normalized location is lowercase and has no scheme, user, host, trailing slash or `.git`.
2. The identity is the last component of that location, as SwiftPM does.
3. Two owners with one repository name give one identity and two locations. The resolver and the assembler refuse them and name both.

## Finding SourcePackages

The folder sits next to the last `Build` folder that is followed by `Products` or `Intermediates.noindex`. That covers a normal build and an archive. A `Build` folder in the user path and a scheme named `Build` do not cut early. A configured path wins.

## The gate

| Condition | Result |
|---|---|
| Action `install` | Run |
| Configuration in the gate list | Run |
| Anything else | Skip |
| No action inside Xcode | Fail |
| Configuration unreadable, action `install` | Fail with that error |
| Configuration unreadable, any other action | Skip |

Names are compared exactly. An empty list means archive only.

## The resolver

1. Remote and local packages are joined into one table. Two with the same identity fail.
2. Excludes are matched by identity, so their case does not matter and a location names its package. Every exclude must match a package or the package name of a linked product.
3. A product with a package name maps to that package. A product without one is searched in the local packages first and then in the remote ones. More than one match fails and lists them.
4. The walk goes from product to targets to dependencies and keeps a visited set, so a cycle ends.
5. A dependency for platforms that do not apply is ignored.
6. A macro or plugin target is visited but its dependencies are not followed, unless build tools are included.
7. A `byName` dependency is a target of the same package first, then a product of a declared dependency.
8. Each manifest is read once for a run.
9. The result lists the linked packages and the resolved packages that nothing reached.

## Finding license files

The locator reads the top-level names of a package folder. A name matches when it is a stem (`license`, `licence`, `copying`, `unlicense`, `notice` or `copyright`), then any number of tokens, then an optional text extension. A token follows a dash or a dot. It is `mit`, `apache`, `bsd`, `isc`, `zlib`, `gpl`, `lgpl`, `agpl`, `mpl`, `cc0` or a version such as `2.0`. The extensions are `txt`, `md`, `markdown`, `rst` and `rtf`. Case does not matter. `LICENSE.MIT`, `LICENSE-2.0.txt` and `LICENSE.rtf` match. `LICENSE-NOTES`, `license.swift` and `LICENSE.pdf` do not.

A name is also tried as a folder. A folder named `LICENSES` (the REUSE layout) gives the files inside it that have a text extension or none, sorted by name. Hidden files and subfolders are left out. Any other folder that matches, such as a `LICENSE` folder, is skipped. An RTF file is read as text, so its markup is part of the pane.

## License file checks

1. The real path must be inside the real path of the package folder, compared by component.
2. The file must be a regular file. The read stops one byte past the limit.
3. A file over the limit fails. The limit itself passes.
4. Text is UTF-8, or UTF-16 with a byte order mark.
5. Control characters other than tab, line feed, form feed and carriage return fail. The property list writer keeps a form feed, and a test reads it back.

## Tests

Every type has success, failure and fuzz tests. The resolver fuzz builds random graphs with cycles and compares the linked set with a breadth-first search written in the test.
