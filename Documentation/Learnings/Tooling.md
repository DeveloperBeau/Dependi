# Tooling

## A lint check must be tested against bad input

- **Trap:** A lint script that passes on clean code does not prove it can fail.
- **Finding:** Mutation runs showed three ways the checks could go blind. Turning off both casing rules, dropping the Linux home path fragment, and removing `--strict` each made a named test fail.
- **Rule:** Every check has a test with a planted violation and a test with similar clean input.

## Mutation results for the repository checks

| Mutation | Test that failed |
|---|---|
| Both casing rules set to false | `the formatter configuration enables both casing rules` and `a lowercase type name and an underscore name fail the strict lint` |
| Linux home path fragment removed | `a planted linux home path is found` |
| `--strict` removed from the lint script | `the lint script covers Sources and Tests recursively and ignores nothing` |
