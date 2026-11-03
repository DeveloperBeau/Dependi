# Command line

## A flag value that looks like a flag hides a mistake

- **Trap:** `init --project --dry-run` would take `--dry-run` as the path and the user would get a project named like a flag.
- **Finding:** Taking the next token without a look accepts it.
- **Rule:** A value that starts with `--` or is empty gives `missingValue`.

## The equals form is a second grammar

- **Trap:** `--project=x` looks valid and users type it.
- **Finding:** Accepting it adds a second way to write each flag and doubles the cases to test.
- **Rule:** One form only. `--project=x` gives `unknownFlag`.

## A repeated flag hides the first value

- **Trap:** `--project a --project b` would silently keep `b`.
- **Finding:** Last wins is a choice the user did not make.
- **Rule:** A repeated flag gives `duplicateFlag`.

## Mutation results

| Mutation | Test that failed |
|---|---|
| The required flag check is removed | `missingRequired` |
| The duplicate check is removed | `duplicates` |
| `--project=` is accepted | `unknownFlags` |
| The dry run flag is ignored | `tableRowsAreAccepted` |
| The value dash check is removed | `missingValues` |
| The `-h` alias is removed | `tableRowsAreAccepted` |
