# Plist keys

Every key that Dependi writes into a plist. A change that adds a key adds a row.

| File | Key | Value |
|---|---|---|
| `Acknowledgements.plist` | `Title` | `Acknowledgements` |
| `Acknowledgements.plist` | `StringsTable` | `Acknowledgements` |
| `Acknowledgements.plist` | `PreferenceSpecifiers` | One entry for each package, in the given order. |
| `Acknowledgements.plist` (single page) | `PreferenceSpecifiers` | One single page entry for each license document, in package order and then document order. A package with no documents has one entry. |
| single page entry | `Type` | `PSGroupSpecifier` |
| single page entry | `Title` | The display name of the package when it has one document or none. `<display name> (<file name>)` when it has two or more. |
| single page entry | `FooterText` | The license text, unchanged. Absent for a package with no documents. |
| index entry | `Type` | `PSChildPaneSpecifier` |
| index entry | `Title` | The display name of the package. |
| index entry | `File` | `Acknowledgements/<slug>`, with no extension. |
| `Acknowledgements/<slug>.plist` | `Title` | The display name of the package. |
| `Acknowledgements/<slug>.plist` | `StringsTable` | `Acknowledgements` |
| `Acknowledgements/<slug>.plist` | `PreferenceSpecifiers` | One entry for each license document. |
| child entry | `Type` | `PSGroupSpecifier` |
| child entry | `Title` | The file name of the license document. |
| child entry | `FooterText` | The license text, unchanged. |

## The display name

The display name of a package is its title, `<name> (<version>)`. The name is the manifest name. The version is the resolved version of a remote package. The title is `<name>` with no brackets when the package has no version, such as a package pinned by revision, and for every local package. If the manifest name is missing, empty or has a control character, the name is the package identity. Spaces around the name and the version are removed. A manual entry keeps its own name. From 0.3.0 the title has this form. Before it was the lower-case identity.
