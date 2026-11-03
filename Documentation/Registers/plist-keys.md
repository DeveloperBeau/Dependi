# Plist keys

Every key that Dependi writes into a plist. A change that adds a key adds a row.

| File | Key | Value |
|---|---|---|
| `Acknowledgements.plist` | `Title` | `Acknowledgements` |
| `Acknowledgements.plist` | `StringsTable` | `Acknowledgements` |
| `Acknowledgements.plist` | `PreferenceSpecifiers` | One entry for each package, in the given order. |
| index entry | `Type` | `PSChildPaneSpecifier` |
| index entry | `Title` | The display name of the package. |
| index entry | `File` | `Acknowledgements/<slug>`, with no extension. |
| `Acknowledgements/<slug>.plist` | `Title` | The display name of the package. |
| `Acknowledgements/<slug>.plist` | `StringsTable` | `Acknowledgements` |
| `Acknowledgements/<slug>.plist` | `PreferenceSpecifiers` | One entry for each license document. |
| child entry | `Type` | `PSGroupSpecifier` |
| child entry | `Title` | The file name of the license document. |
| child entry | `FooterText` | The license text, unchanged. |
