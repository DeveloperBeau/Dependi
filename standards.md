# Standards

Every contributor reads this file first. When a rule and the code disagree, that is a defect in one of them. Say which.

## Architecture

Code lives in rings. A module depends only on a ring further in. A test checks this rule.

| Ring | Holds | May know |
|---|---|---|
| Entities | Plain data types | Nothing |
| Domain | Interfaces for each capability, and the logic that uses them | Entities |
| Infrastructure | Code that touches the file system, a process, the environment or the console. One module for each concern. | Entities and the domain interfaces it implements |
| Features | One module for each command | Entities and domain |
| Composition | The only place that builds concrete objects | Everything |

This tool has no UI ring and no server ring.

Placement questions, in order:

1. Does more than one module need it? Put it in the innermost ring both can reach.
2. Is it a product rule? Put it in the domain. It must be testable with no file system or process.
3. Does it touch an outside system? Make it infrastructure, behind an interface that the domain owns.

Rules that hold everywhere:

- One public type in each file.
- Each module declares every module it uses, and builds and tests alone.
- No hidden global state.
- Required dependencies are constructor arguments. They have no default values.
- The file system, process runner, console and environment are reached only through interfaces. Tests use doubles. No test calls a real service in the default test run.
- When the same decision is written in two places, move it to one owner.
- No third-party dependency.
- Every target uses Swift 6 language mode and `ExistentialAny`.
- Domain operations use typed throws. Each module has one error enum.

## API design

Follow the Swift API Design Guidelines.

- Clarity at the call site is the first goal. Judge a name by reading the call.
- Name each thing by its role. Do not repeat the type in the name.
- A method with side effects reads as an imperative verb phrase. A method without side effects reads as a noun phrase.
- A boolean reads as an assertion, such as `isEmpty`.
- A protocol for a capability ends in `ing` or `able`. A protocol for what something is reads as a noun.
- Do not give a required collaborator a default value.
- Document every public declaration with a one-sentence summary.
- Use the smallest public surface.
- Types use UpperCamelCase. Everything else uses lowerCamelCase. An acronym is all upper case or all lower case.
- The formatter decides layout. See `.swift-format`. `Scripts/lint.sh` runs it.

Where a framework forces another form, follow that form and list it here with the reason. There are none yet.

## Testing

- Every module has its own tests. The whole suite is the gate.
- Cover success, misuse and adversarial input. Each has a false-positive check and a false-negative check.
- Fuzz tests use a seeded generator. A failure prints the seed.
- Follow each value that crosses a module boundary with an end-to-end test. The expected value is written by hand. A test never asserts on a value that the code under test produced.
- Coverage is a floor. A test that cannot fail proves nothing.
- Verify each rule by mutation. Break the code on purpose, confirm that a named test fails, restore it, and record the result. Mutation proves a test is connected.
- Waits are bounded. A hang fails with a name.
- A flaky test is a defect. Find the cause. Do not rerun or skip it.
- A test name says what the test proves.

## Documentation

- `Documentation/Architecture/` has one page for each subsystem. It describes the code as it is.
- `Documentation/Learnings/` has one page for each area. Each entry has the trap, the finding that proved it, and the rule that follows.
- A register holds each list that grows. A change that adds an item adds its row.
- Plans and specs are not stored in this repository.
- No file holds an absolute path, a user name or a computer name. A test checks this.
- Write short, plain sentences. One topic in each paragraph. Use the same word for the same thing. Do not use a semicolon.
- Comments say why or what. They do not say what changed.

## Pull requests

- Every pull request targets `main`, or the branch of the slice it builds on.
- One concern in each pull request. The build and the full test run are green.
- The owner merges. Nobody merges their own pull request or bypasses branch protection.
- Write the title and description as the engineer who made the change. Describe what changed and why.
