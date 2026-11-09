# Domain logic

## A fuzz property finds a rule you did not know you had

- **Trap:** An identity that keeps a leading space is not stable when it is normalized again.
- **Finding:** The idempotence fuzz test failed on inputs like `https://host/ X`.
- **Rule:** The identity is trimmed. A property test for idempotence is part of every normalizer.

## A test that cannot fail on the mutant is not connected

- **Trap:** The oversize configuration test used a file that was invalid JSON once cut at the limit. It passed even with the size check removed.
- **Finding:** The register reported a survivor for `loader-size-cap`.
- **Rule:** Build the failing input so that it is valid except for the one property under test. The register is the check.

## Register search text breaks when the formatter rewraps code

- **Trap:** Four entries named lines that the formatter later split across lines.
- **Finding:** Validation reported each one as a register error before any mutation ran.
- **Rule:** Prefer short search text that sits on one line. Run the register after every format.

## Two locations can share an output name

- **Trap:** The output name keeps only twelve hex characters (48 bits) of a hash, so collisions exist.
- **Finding:** Two locations with equal 48-bit prefixes were found offline in about 60 million tries and written into a test as constants. A package author could do the same, so the name is a collision check and not a guarantee.
- **Rule:** The assembler checks for a collision before anything is written.

## A path prefix test must compare components

- **Trap:** `/checkouts/kit-evil` starts with `/checkouts/kit`.
- **Finding:** A link into the sibling folder passed the string prefix check in a mutant and failed the component check.
- **Rule:** Compare with a trailing slash. A test uses a sibling with a similar name.

## Mutation results

The 31 entries owned by this slice are all killed. Each one names the test that fails. See `Documentation/Registers/mutations.md`.
