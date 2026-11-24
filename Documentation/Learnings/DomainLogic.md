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

## A trait condition decides whether a dependency exists

- **Trap:** The resolver followed every product that a target names, so a dependency that SwiftPM leaves out was still followed. SQLite.swift 0.16 gates `CSQLite` and `SQLCipher` behind traits that are off on Apple platforms. Those packages are not in `Package.resolved`, so the build failed with `No package provides the product SQLiteSwiftCSQLite`.
- **Finding:** `swift package dump-package` writes the conditions as `traits` beside `platformNames`, writes the trait table with `enabledTraits`, and writes the traits that a package asks of each dependency. An empty `traits` list on a dependency is different from no list.
- **Rule:** Follow a conditional dependency only when one of its traits is on. Take the default traits, add what dependents ask for, and expand traits that enable traits. Repeat the walk until the requests stop growing, because a reached package can ask for a new trait.
- **Trap:** Starting every linked package on `default` missed the traits that the app picks. Since Xcode 26.4 the Package Dependencies tab can turn on `SQLiteSwiftCSQLite` for SQLite.swift, and then `CSQLite` ships but was not listed.
- **Finding:** Xcode writes the pick as `traits` on the package reference in `project.pbxproj`. No key means the defaults. An empty list turns the defaults off. A list holds exactly the names, with no implicit `default`.
- **Rule:** Read the key, keep a missing key apart from an empty list, and start a linked or local package from the pick. Join the picks of references to one package, and add `default` when one of them has no key.

## Mutation results

The 31 entries owned by this slice are all killed. Each one names the test that fails. See `Documentation/Registers/mutations.md`.

The 10 entries of the `swiftpm-traits` slice are all killed too. They cover the trait gate, the default traits, the conditional request, the missing trait list, the repeat of the walk, the trait expansion and the three reads of the trait data in the manifest reader. The entries added later for the traits that the project picks cover the seed, the empty pick, the implicit `default`, the reads of remote and local references, the join with a reference that has no key and the other projects. They have not been run yet.
