# Composition

## A skipped build must start no process

- **Trap:** Looking up the toolchain when the application starts would run `xcrun` on every Debug build.
- **Finding:** The end-to-end test for a Debug skip asserts that the recorded runner saw no request.
- **Rule:** Anything that needs a process is created on first use.

## The executable belongs to the composition ring and uses its library

- **Trap:** The ring table forbade a module to depend on its own ring, so the executable could not use the composition library.
- **Finding:** The architecture test failed on the first build of the executable.
- **Rule:** Only the composition ring may use itself. A test shows that other rings still may not.

## Error messages are part of the interface

- **Trap:** Printing a Swift enum case shows `licenseMissing(package: "kit")`, which a developer must decode.
- **Finding:** Each case now has a plain sentence, and a test checks that every payload text appears in it.
- **Rule:** Every error that reaches a user has a sentence that names the package or file and, where there is one, the fix.

## Time limits that nothing read

- **Trap:** `processTimeoutSeconds` and `runTimeoutSeconds` were decoded and never used. The reader had a hard-coded 60 seconds, and a cold cache with a hung toolchain could stall an archive for many packages times 60 seconds.
- **Finding:** A search for the field names found no reader.
- **Rule:** Every setting that is documented has a test that shows it reaches the process request. The run limit is checked before each spawn and also shortens the limit of the child.

## Mutation results

| Mutation | Test that failed |
|---|---|
| The usage exit code constant becomes 1 | `commandLineErrors` |
| The unavailable exit code becomes 0 | `initNotAvailable` |
| The version text drops the number | `versionAndHelp` |
| The child environment passes `SDKROOT` | `processRequestsAreClean` |
| The toolchain lookup asks for the wrong program | `processRequestsAreClean` |
| The sandbox message drops the setting name | `sandboxMessageNamesTheFix` |
| The license message drops the package | `messagesNamePayloads` |
