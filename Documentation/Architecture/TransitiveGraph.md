# Transitive graph

## Purpose

`DependiPackageGraph` reads the manifest of one package: its products, its targets, the dependencies of each target and the packages it declares. The domain resolver uses that to follow the graph.

## Parts

- `PackageGraphReader` implements `PackageManifestReading`. It receives the process runner and the file interfaces through its initializer. It does not import the process module.
- `PackageGraphSettings` holds the `swift` path, the toolchain version, the child environment, the folders and the limits.
- `ManifestJSONParser` reads the JSON of `swift package dump-package`.
- `ManifestCacheEntry` is one cached output with its key.

## Data flow

1. Resolve the package path to a real path.
2. List the top level of the package. Hash every `Package.swift` and every `Package@swift-X.Y.swift`.
3. Build the cache key from the toolchain version, the hash of the child environment, the exact arguments and those file hashes.
4. Look for `<key>.json` in the cache folder. A package inside the checkouts folder uses the remote cache folder, which outlives the build folder. Any other package uses the local cache folder.
5. A hit must hold the same key and a dump that parses. Anything else is a miss.
6. On a miss run `swift package --package-path <real> --scratch-path <scratch>/<hash> dump-package`. The scratch folder is outside the package and different for each package.
7. Parse the output. Remove temporary files in the cache folder that are older than one day (`<key>.json.tmp-<UUID>`). Write the cache entry. A failed cache write is ignored, because it only costs time on the next run. There is no other eviction.

## Edge cases

- SwiftPM prefers a versioned manifest over `Package.swift`, so versioned files are part of the key.
- A manifest can read the environment, so the environment hash is part of the key.
- A damaged cache entry is a miss and is recomputed. It is never read as an empty graph.
- A non-zero exit names the package and the first 300 bytes of error text. Control characters except newline and tab become spaces, so child output cannot inject escape sequences into the build log.
- Output that is not a manifest fails and names the package.
- A dependency of an unknown shape is skipped. The rest is kept.
- Platform conditions are lowercase names such as `ios` and `macos`.

## Tests

Recorded real output from five real packages and two small generated ones is parsed against hand-written expectations. The request is checked argument by argument. The cache is checked for hits, both tiers, each reason to invalidate and each way an entry can be damaged. Truncated and corrupted output is fuzzed.
