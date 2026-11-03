# Transitive graph

## A cache test needs an entry that is wrong in one way only

- **Trap:** A test wrote an entry with a wrong key and an invalid dump. The entry was rejected because of the dump, so removing the key check changed nothing.
- **Finding:** A dedicated test with a valid dump and a wrong key was needed to connect the key check.
- **Rule:** Build the damaged input so that exactly one property is wrong.

## Package names in dependencies are not identities

- **Trap:** A product dependency names its package as the manifest author wrote it, for example `OpenAPIKit` for the identity `openapikit`.
- **Finding:** Real output from `swift-openapi-generator` shows the mixed case. Declared dependencies use the lowercase identity.
- **Rule:** The reader keeps the written name. The domain resolver normalizes it.

## Dump the tool's output once and keep it

- **Trap:** Tests that run the real tool are slow and depend on the machine.
- **Finding:** `dump-package` writes nothing into a checkout when it has its own scratch folder. The recorded output of seven packages covers plugins, binaries, platform conditions, product packages and a 60 KB manifest.
- **Rule:** Unit tests use recorded output with `$ROOT` in place of machine paths. Contract tests run the real tool.

## Mutation results

| Mutation | Test that failed |
|---|---|
| Versioned manifests left out of the key | `versionedManifestInvalidates` |
| Environment left out of the key | `toolchainAndEnvironmentInvalidate` |
| Toolchain left out of the key | `toolchainAndEnvironmentInvalidate` |
| The stored key is not checked | `wrongKeyValidDumpIsAMiss` |
| Every package uses the local cache | `cacheTiers` |
| The exit status is not checked | `nonZeroExit` |
| The scratch path argument is dropped | `requestShape` |
| The error text is dropped | `nonZeroExit` |
| The condition is read from the wrong position | `syntheticPackage` |
| Declared identities are not lowercased | `unknownDependencyShapeIgnored` |
