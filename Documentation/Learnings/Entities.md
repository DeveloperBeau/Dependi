# Entities

## A typo in a configuration key must not fall back to a default

- **Trap:** A misspelled key such as `gatelist` is ignored and the default applies. A custom shipping configuration then skips silently.
- **Finding:** Decoding with a plain `Decodable` accepts unknown keys. A container with dynamic keys can list them.
- **Rule:** Decoding fails on any key that is not known and names the key. A test covers ten mistyped keys.

## A pinned value that reaches a shell must be validated where it enters

- **Trap:** The version and commit in `.dependi.json` become folder names and git arguments in the wrapper script.
- **Finding:** Values such as `../../..`, `1.0;rm -rf ~` and `$(id)` are valid strings.
- **Rule:** The decoder accepts only three dotted numbers and 40 lowercase hex characters. Fuzz tests check the rule in both directions.

## An invalid mutant is a useful signal

- **Trap:** Two register entries compiled to nothing: a closure that ignored its argument and an empty literal with no type.
- **Finding:** The runner reported them INVALID instead of KILLED, so the register was fixed before it claimed a connection.
- **Rule:** Run every new register entry once and read the INVALID rows.

## Mutation results

| Mutation | Test that failed |
|---|---|
| The unknown key error is dropped | `unknownKeyFailsNamingTheKey` |
| The known key filter never matches | `mistypedKeyFails` |
| The version pattern accepts any dotted digits | `badVersionsFail` |
| The commit pattern accepts upper case | `badCommitsFail` |
| The default gate list is empty | `emptyObjectGivesDefaults` |
| The separator check is removed | `unsafeNamesAreRejected` |
| The dot name check is removed | `unsafeNamesAreRejected` |
