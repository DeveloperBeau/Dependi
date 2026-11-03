# Project file

## Foundation reads the project file format

- **Trap:** The project file is not JSON or XML. A hand-written parser would be large and wrong.
- **Finding:** `PropertyListSerialization` parses the OpenStep text of a file that Xcode wrote. Lists need commas between items, so a hand-written fixture without commas fails to parse.
- **Rule:** Parse with Foundation. Check every fixture with the same parser.

## Test products must not leak into the app

- **Trap:** An app that depends on a test target, or a test target that links Quick, adds a test only product to the license list.
- **Finding:** The product type of a test target ends in `unit-test` or `ui-testing`. The fixture makes the app depend on both kinds, so a walk that does not stop at them fails.
- **Rule:** The walk never enters a test target. Each kind has its own test.

## A local package product has no package field

- **Trap:** Xcode writes a local package product without `package`. Treating the missing field as an error rejects normal projects.
- **Finding:** The smoke file written by Xcode has three local products and no `package` field anywhere.
- **Rule:** No `package`, or a local one, gives a product with no package name. A remote reference without a URL still fails.

## One product name can belong to two packages

- **Trap:** De-duplicating by product name hides the second package.
- **Finding:** Two `Logging` products from different repositories stay apart because the key is the pair of names.
- **Rule:** A product is the pair of product name and package name. The set is sorted by that pair.

## A proxy can name the project itself

- **Trap:** A dependency proxy has a `containerPortal`. It is the project object for a target in the same project and a file reference for another project.
- **Finding:** Treating every portal as a file reference loses the same-project case.
- **Rule:** The portal that equals the project id stays in the model. Any other portal must resolve to a file reference or the dependency is skipped.

## An unreachable project is not an error

- **Trap:** A cross-project dependency may point to a project that was not checked out.
- **Finding:** Failing there would stop a build for a project the user cannot read.
- **Rule:** Load failures of other projects are skipped. A failure of the main file is never skipped.

## A mutant needs a fixture that is valid except for one property

- **Trap:** A test product with the same name as an app product hides the missing exclusion.
- **Finding:** The unit test and ui test targets link different products, so each exclusion has its own failing test.
- **Rule:** Give every excluded item a name that nothing else uses.

## Mutation results

The 19 entries owned by this slice are all killed. Each one names the test that fails. See `Documentation/Registers/mutations.md`.
