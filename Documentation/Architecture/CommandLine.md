# Command line

## Purpose

`DependiCommandLine` turns the program arguments into one `Command`. It is a pure function. It reads no files, no environment and no `CommandLine` global. The caller passes the arguments without the program name.

## Parts

| Type | Role |
|---|---|
| `Command` | The result: `generate`, `initialize(projectPath:isDryRun:)`, `version`, `help`. |
| `CommandLineParser` | `parse(_:)` with typed throws of `CommandLineError`. |
| `CommandLineError` | The one error enum of the module. Each case has a message. |
| `UsageText` | The help text with every command and flag. |

## Command table

| Command | Flags |
|---|---|
| `generate` | none |
| `init` | `--project <path>` (required), `--dry-run` (switch) |
| `--version`, `version` | none |
| `help`, `--help`, `-h` | none |

## Data flow

1. The first argument names the command. No arguments gives `noCommand`. An unmatched name gives `unknownCommand`.
2. A command without flags refuses any further argument with `unexpectedArgument`.
3. `init` reads the rest left to right. `--project` takes the next token as its value. `--dry-run` takes none.
4. After the loop, a missing `--project` gives `missingRequiredFlag`.

## Edge cases

- Command names match exactly. `Generate`, `gen` and `generate ` are unknown.
- `--project=path` is an unknown flag. Only the two-token form is accepted.
- A value that is empty or starts with `--` gives `missingValue`. A value that starts with one dash is kept.
- A repeated flag gives `duplicateFlag`, also when the first use is complete.
- A token that starts with a dash and is not a flag gives `unknownFlag`. Any other stray token gives `unexpectedArgument`.
- Paths keep spaces, unicode and relative parts as written.

## Tests

`CommandLineParserTests` checks the table, every error and the usage text by hand-written values. `CommandLineFuzzTests` uses the seeded generator for random token lists, valid templates in both flag orders, stray tokens and random unicode.
