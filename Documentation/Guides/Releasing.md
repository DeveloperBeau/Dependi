# Releasing

A release is a tag on the default branch. Apps pin the tag's version and full commit in `.dependi.json`, and the wrapper script builds that commit.

## Steps

1. Run `sh Scripts/gate.sh`. It must pass.
2. Run `sh Scripts/contract.sh` with the Xcode version you support. It must pass.
3. Run the full mutation register. No entry may survive. Do not use `--changed-since` for a release.
4. Set `DependiVersion.current` in `Sources/DependiComposition/DependiVersion.swift` to the new version.
5. Merge the change through a pull request.
6. Tag the merge commit with the version, for example `0.1.0`, and push the tag.
7. Record the full commit with `git rev-parse <tag>^{commit}`. Users put it in `.dependi.json`.

## Rules

- A tag is never moved. The wrapper script checks the commit after cloning, so a moved tag fails the build.
- A new version that changes a `.dependi.json` key says so in the release notes.
- During work on a branch, run the register with `--changed-since` and the base branch, for example `--changed-since origin/main`. This runs only the entries whose file changed. It does not run an entry when only its test changed, so it never replaces the full run.
- The signed and notarized binary is not part of version 0.1.
