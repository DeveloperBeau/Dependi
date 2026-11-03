# Mutation register

This page is generated from `mutations.json` by `Scripts/mutate.swift --markdown`. Do not edit it.

| Id | Slice | File | Test |
|---|---|---|---|
| assembler-duplicate-identity | 2b | `Sources/DependiDomain/AcknowledgementAssembler.swift` | `duplicateIdentity` |
| assembler-missing-license | 2b | `Sources/DependiDomain/AcknowledgementAssembler.swift` | `missingLicense` |
| assembler-slug-collision | 2b | `Sources/DependiDomain/AcknowledgementAssembler.swift` | `slugCollision` |
| assembler-sort | 2b | `Sources/DependiDomain/AcknowledgementAssembler.swift` | `sortedWithoutCase` |
| config-commit-case | 1 | `Sources/DependiEntities/ToolConfiguration.swift` | `badCommitsFail` |
| config-default-gate | 1 | `Sources/DependiEntities/ToolConfiguration.swift` | `emptyObjectGivesDefaults` |
| config-mistyped-key | 1 | `Sources/DependiEntities/ToolConfiguration.swift` | `mistypedKeyFails` |
| config-unknown-key | 1 | `Sources/DependiEntities/ToolConfiguration.swift` | `unknownKeyFailsNamingTheKey` |
| config-version-pattern | 1 | `Sources/DependiEntities/ToolConfiguration.swift` | `badVersionsFail` |
| disk-exists-lstat | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `danglingLinkExists` |
| disk-limit-plus-one | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `readStopsAfterLimitPlusOne` |
| disk-loop-mapping | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `loopIsReported` |
| disk-move-replaces | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `moveReplacesDestination` |
| disk-nofollow | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `lastComponentLinkIsRefused` |
| disk-not-found-mapping | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `missingPathHasNoRealPath` |
| disk-regular-check | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `folderIsRefused` |
| disk-remove-link-only | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `removingLinkKeepsTarget` |
| disk-sorted-listing | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `listingIsSorted` |
| disk-write-atomic-rename | 3 | `Sources/DependiFileSystem/DiskFileSystem.swift` | `writeIsCleanAndReplaces` |
| double-limit-plus-one | 2a | `Sources/DependiTestSupport/InMemoryFileSystem.swift` | `doublePassesBehaviorSuite` |
| double-link-hop-limit | 2a | `Sources/DependiTestSupport/InMemoryFileSystem.swift` | `loopsAndChains` |
| double-readonly-component | 2a | `Sources/DependiTestSupport/InMemoryFileSystem.swift` | `readOnlyIsMatchedByComponent` |
| gate-archive-runs | 2b | `Sources/DependiDomain/ReleaseGate.swift` | `archiveRuns` |
| gate-case-sensitive | 2b | `Sources/DependiDomain/ReleaseGate.swift` | `otherConfigurationsSkip` |
| gate-config-error-archive | 2b | `Sources/DependiDomain/ReleaseGate.swift` | `unreadableConfigurationOnArchiveFails` |
| gate-config-error-build-skips | 2b | `Sources/DependiDomain/ReleaseGate.swift` | `unreadableConfigurationOnBuildSkips` |
| gate-debug-skips | 2b | `Sources/DependiDomain/ReleaseGate.swift` | `otherConfigurationsSkip` |
| gate-missing-action | 2b | `Sources/DependiDomain/ReleaseGate.swift` | `missingAction` |
| identity-git-strip | 2b | `Sources/DependiDomain/PackageIdentityNormalizer.swift` | `formsJoin` |
| identity-lowercase | 2b | `Sources/DependiDomain/PackageIdentityNormalizer.swift` | `formsJoin` |
| license-name-dot-names | 1 | `Sources/DependiEntities/LicenseDocument.swift` | `unsafeNamesAreRejected` |
| license-name-separator | 1 | `Sources/DependiEntities/LicenseDocument.swift` | `unsafeNamesAreRejected` |
| license-notice-pattern | 2b | `Sources/DependiDomain/LicenseLocator.swift` | `noticeNextToLicense` |
| license-order | 2b | `Sources/DependiDomain/LicenseLocator.swift` | `foundInFixedOrder` |
| loader-size-cap | 2b | `Sources/DependiDomain/ConfigurationLoader.swift` | `oversizeAndFolder` |
| locator-anchor-next | 2b | `Sources/DependiDomain/SourcePackagesLocator.swift` | `schemeNamedBuild` |
| locator-last-anchor | 2b | `Sources/DependiDomain/SourcePackagesLocator.swift` | `earlierBuildFolderIsIgnored` |
| resolver-ambiguous | 2b | `Sources/DependiDomain/LinkedPackageResolver.swift` | `localProductAmbiguous` |
| resolver-exclude-unmatched | 2b | `Sources/DependiDomain/LinkedPackageResolver.swift` | `excludeMatchesNothing` |
| resolver-identity-conflict | 2b | `Sources/DependiDomain/LinkedPackageResolver.swift` | `duplicateIdentity` |
| resolver-macro | 2b | `Sources/DependiDomain/LinkedPackageResolver.swift` | `macroDependencies` |
| resolver-platform | 2b | `Sources/DependiDomain/LinkedPackageResolver.swift` | `platformConditions` |
| resolver-recursion | 2b | `Sources/DependiDomain/LinkedPackageResolver.swift` | `transitive` |
| resolver-unmatched-product | 2b | `Sources/DependiDomain/LinkedPackageResolver.swift` | `unmatchedProduct` |
| slugger-hash-input | 2b | `Sources/DependiDomain/OutputNameSlugger.swift` | `slugMatchesHandComputedHash` |
| slugger-sanitize | 2b | `Sources/DependiDomain/OutputNameSlugger.swift` | `unsafeIdentityIsReduced` |
| validator-component | 2b | `Sources/DependiDomain/LicenseFileValidator.swift` | `similarSiblingRefused` |
| validator-containment | 2b | `Sources/DependiDomain/LicenseFileValidator.swift` | `outsideLinkRefused` |
| validator-control | 2b | `Sources/DependiDomain/LicenseFileValidator.swift` | `controlCharactersRefused` |
| validator-size | 2b | `Sources/DependiDomain/LicenseFileValidator.swift` | `sizeBoundary` |
