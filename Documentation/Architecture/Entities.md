# Entities

## Purpose

`DependiEntities` holds the plain data that every other module shares. It has no behavior beyond checking its own inputs. It imports Foundation only.

## Types

| Type | Holds |
|---|---|
| `PackageIdentity` | The key of a package: the last component of its location, in lowercase. |
| `PackageKind` | `remote` or `local`. |
| `ResolvedPackage` | Identity, kind, normalized location, version, revision and checkout path. |
| `ProductReference` | A product name and the package name that the project file gives, or `nil` for a local package. |
| `LicenseDocument` | A file name and the license text. The initializer rejects a name that is empty, `.`, `..`, or holds a separator or control character. |
| `Acknowledgement` | Display name, identity, normalized location and license documents. |
| `ManualEntry` | A name and a license path for code that Dependi cannot find. |
| `BuildContext` | The Xcode build settings. A missing setting is `nil`, because the release gate must tell absent from empty. |
| `ToolConfiguration` | The settings in `.dependi.json`. |
| `EntityError` | The one error enumeration of the module. |

## Configuration decoding

1. Decoding is strict. A key that is not known fails with `unknownConfigurationKey` and the name of the key. A typo cannot fall back to a default.
2. Absent keys use these defaults: no excludes, no manual entries, the gate list `["Release"]`, no paths, `includeBuildTools` and `allowUnreached` false, 60 seconds for a process and 300 seconds for a run. The loader checks the two limits. The process limit is the time for one child. The run limit is the time after which no new child starts.
3. `version` must be three numbers separated by dots. `commit` must be 40 lowercase hexadecimal characters. Both end up in shell paths and commands, so nothing else is accepted.

## Tests

Each type has equality and round trip tests. The configuration tests compare a full decode with a hand-written value, check the defaults, reject each mistyped key and reject each bad version and commit. Seeded fuzz checks that a version or a file name is accepted if and only if it follows the rule.
