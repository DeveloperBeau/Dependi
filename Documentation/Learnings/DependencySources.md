# Dependency sources

## The file identity is not the package identity

- **Trap:** `workspace-state.json` and `Package.resolved` carry an `identity` field. SwiftPM may change how it builds that field.
- **Finding:** Every other part of the tool uses the last component of the normalized location. A test gives a pin an identity field that differs from its location.
- **Rule:** Take the identity from the location with the shared normalizer. Use the field only when the location is empty.

## A subpath is input, not a trusted name

- **Trap:** A bad `subpath` such as `../..` points the license search outside the checkouts.
- **Finding:** The syntax check and the real path check each catch cases that the other misses. A link inside `checkouts` can lead to `checkouts-evil`.
- **Rule:** Check the text of the subpath, then compare real paths by component with a trailing slash.

## A redundant check hides in a mutant

- **Trap:** A second length check on the containment test looked useful.
- **Finding:** The mutant that removed it survived. The trailing slash already makes the root itself fail.
- **Rule:** Remove a check that no input can reach. The register finds it.

## Decode only what you use

- **Trap:** Versions 5 to 7 of the state file add and rename fields. A strict decoder breaks on each new Xcode.
- **Finding:** The real version 7 files hold `prebuilts`, `basedOn` and an empty `kind` object. A hand written version 9 file with extra fields still reads.
- **Rule:** Declare the fields in use as optional where the format varies. Fail with the field name when a needed one is missing.

## Registry packages are not guessed

- **Trap:** Registry packages are stored in a different folder from source control checkouts.
- **Finding:** No real file with a registry package was available on the machine that built this module.
- **Rule:** Fail with the kind in the message. Do not guess a path.

## Mutation results

The 9 entries owned by this slice are all killed. Each one names the test that fails. See `Documentation/Registers/mutations.md`.
