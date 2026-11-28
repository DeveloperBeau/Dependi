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

## Test-only packages are not unreached packages

- **Trap:** Test targets are skipped, so a package that only a test target links looked like a package nothing links. Every archive failed.
- **Finding:** The resolved list holds every package of the workspace, and the app's product list holds only the shipped ones.
- **Rule:** Collect the products of all other targets as well, and treat their packages as expected. A package that nothing links is still reported.

## An older project has no local package object

- **Trap:** Projects from older Xcode versions record a local package as a folder file reference. They have no `XCLocalSwiftPackageReference`. Their product dependencies have no `package` key. The reader found no local package, so the build failed with `No package provides the product`.
- **Finding:** A real project of this shape (13 local packages, 32 product dependencies) failed on the first product. `dependi init --dry-run` listed the products and gave no warning.
- **Rule:** A folder file reference of type `wrapper` or `folder` that holds a `Package.swift` is a local package. Resolve its path through the group chain and the source tree. A product that still has no package fails and names the product.

## A project file has no one layout

- **Trap:** Parsing the file and printing it again changes the order, the spacing and the comments that Xcode wrote. A search with a regular expression finds a key inside a comment or a string.
- **Finding:** Five real files differ in object version, quoting, synchronized folders and where the sandbox setting lives. A comment such as `/* "${SRCROOT}/.dependi/run.sh" */` looks like a finished phase to a text search.
- **Rule:** Ask the parsed model what the project means. Ask a scanner that skips comments and keeps strings whole where the text is. Edit bytes at those positions and leave the rest alone.

## A folder can leave a bundle out

- **Trap:** A synchronized folder copies the files inside it. A reference added on top would copy the bundle twice. A membership exception can also leave the bundle out of one target.
- **Finding:** One real project has a synchronized folder per target and a one-line `path = Fila;` group. The group has no list of files to read.
- **Rule:** Resolve the group path and test whether the bundle is inside it. Add no reference when it is. Refuse when an exception for this target names the bundle.

## Hand-made ids are valid ids

- **Trap:** An id maker that checks only the 24 digit ids of Xcode can make an id that already exists in a project with ids such as `FA3000000000000000000001`.
- **Finding:** One real project uses short, patterned ids. An id inside a comment is harmless, but a text search is cheaper than telling the two apart.
- **Rule:** Skip every id that appears anywhere in the text or was made earlier in the run.

## A key can be quoted

- **Trap:** Xcode quotes a key when it holds a character that is not plain. A file that was changed by hand or by another tool can quote `"ENABLE_USER_SCRIPT_SANDBOXING"` or the value `"NO"`.
- **Finding:** The same project, spelled five ways, must give the same answer. The scanner gives the text without quotes, so all spellings match.
- **Rule:** Compare the text of a key or a value without its quotes. Count `NO` and `"NO"` as done.

## A section can be missing

- **Trap:** An older project has no `PBXShellScriptBuildPhase` section at all. An insert into a section that is not there fails or lands in the wrong place.
- **Finding:** The oldest real file has no such section. Xcode orders sections by name and puts a blank line between them.
- **Rule:** Make the section between the two sections whose names sort around it. If none sorts after it, make it after the last one.

## A write can fail half way

- **Trap:** A backup that is written after the project file, or a project file that is written in place, can leave the user with a broken file and no copy.
- **Finding:** A recording writer shows the order of the writes. The backup comes first. The new text goes to a temporary file and a move replaces the project file.
- **Rule:** Write the backup, read it back, then replace the project file in one move. Write nothing when the project needs no change, so a re-run keeps the first backup.

## A check that reads the same text proves little

- **Trap:** A check that the edit "looks right" can pass when the scanner and the parser read the file in different ways.
- **Finding:** Planning again on the edited text must find nothing to do. A plan that drops one step fails that check, and a plan that changes another key fails the model comparison.
- **Rule:** Check the edited bytes with the parser, and plan again on them. Keep one test for each check, so each check has a test that fails when the check is gone.

## Mutation results


The 19 entries owned by this slice, and the 8 entries of the legacy local package change, are all killed. Each one names the test that fails. See `Documentation/Registers/mutations.md`.

The 59 entries of the editor slice each name the test that fails when the code is broken. A first run of the register by hand showed that seven entries survived. Their tests only checked that an error was thrown, so they now check the text of the error or the place of the edit. See `Documentation/Registers/mutations.md`.
