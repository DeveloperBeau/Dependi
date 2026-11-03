import DependiDomain
import DependiEntities

/// Writes the acknowledgements for one build. It follows the generate flow in order and stops at the first problem.
public struct GenerateFeature: Sendable {
    private let environment: any EnvironmentReading
    private let files: any FileReading
    private let directories: any DirectoryListing
    private let dependencySource: any DependencySourceReading
    private let linkedProducts: any LinkedProductReading
    private let manifests: any PackageManifestReading
    private let writer: any AcknowledgementWriting
    private let output: any OutputWriting

    /// Creates the feature with every outside capability it needs.
    public init(
        environment: any EnvironmentReading,
        files: any FileReading,
        directories: any DirectoryListing,
        dependencySource: any DependencySourceReading,
        linkedProducts: any LinkedProductReading,
        manifests: any PackageManifestReading,
        writer: any AcknowledgementWriting,
        output: any OutputWriting
    ) {
        self.environment = environment
        self.files = files
        self.directories = directories
        self.dependencySource = dependencySource
        self.linkedProducts = linkedProducts
        self.manifests = manifests
        self.writer = writer
        self.output = output
    }

    /// Runs the flow. It fails with the first problem and names the package or file involved.
    public func run() throws(DomainError) -> GenerateOutcome {
        let context = BuildContextReader(environment: environment).read()
        let configuration = loadConfiguration(context)
        let decision = try ReleaseGate().decision(context: context, configuration: configuration)
        if case .skip(let reason) = decision {
            output.writeLine("Dependi: skipped. \(reason)")
            return .skipped(reason: reason)
        }
        if case .run(let reason) = decision { output.writeLine("Dependi: running. \(reason)") }
        let settings = try configuration.get()
        if context.isScriptSandboxEnabled == true { throw .scriptSandboxEnabled }
        let acknowledgements: [Acknowledgement]
        do {
            acknowledgements = try collect(context: context, settings: settings)
        } catch .fileUnreadable(let path, let reason)
            where reason.lowercased().contains("not permitted")
        {
            _ = path
            throw .scriptSandboxEnabled
        }
        let bundle = try OutputLocation(files: files).bundlePath(
            context: context, configuration: settings)
        try writer.write(acknowledgements, intoBundleAt: bundle)
        output.writeLine("Dependi: wrote \(acknowledgements.count) acknowledgements to \(bundle)")
        return .wrote(count: acknowledgements.count)
    }

    private func loadConfiguration(_ context: BuildContext) -> Result<
        ToolConfiguration, DomainError
    > {
        guard let directory = context.projectDirectory else {
            return .failure(.buildContextIncomplete(missing: ["PROJECT_DIR"]))
        }
        do {
            return .success(try ConfigurationLoader(files: files).load(projectDirectory: directory))
        } catch {
            return .failure(error)
        }
    }

    private func collect(context: BuildContext, settings: ToolConfiguration) throws(DomainError)
        -> [Acknowledgement]
    {
        var missing: [String] = []
        if context.projectFilePath == nil { missing.append("PROJECT_FILE_PATH") }
        if context.targetName == nil { missing.append("TARGET_NAME") }
        guard let projectDirectory = context.projectDirectory,
            let projectFile = context.projectFilePath,
            let targetName = context.targetName, missing.isEmpty
        else { throw .buildContextIncomplete(missing: missing) }

        let normalizer = PackageIdentityNormalizer()
        let sourcePackages = try SourcePackagesLocator().locate(
            buildDirectory: context.buildDirectory, configuredPath: settings.sourcePackagesPath)
        let resolved = try dependencySource.resolvedPackages(sourcePackagesPath: sourcePackages)
        let pinned = try dependencySource.pinnedRevisions(projectDirectory: projectDirectory)
        for package in resolved where package.kind == .remote {
            if let wanted = pinned[package.identity], let actual = package.revision,
                wanted != actual
            {
                throw .revisionMismatch(
                    package: package.identity.value, pinned: wanted, checkedOut: actual)
            }
        }
        let linked = try linkedProducts.linkedProducts(
            projectFilePath: projectFile, targetName: targetName)

        var locals = resolved.filter { $0.kind == .local }
        let knownPaths = Set(locals.map(\.checkoutPath))
        for path in linked.localPackagePaths where !knownPaths.contains(path) {
            locals.append(
                ResolvedPackage(
                    identity: normalizer.identity(forLocation: path), kind: .local,
                    normalizedLocation: normalizer.normalizedLocation(of: path), version: nil,
                    revision: nil,
                    checkoutPath: path))
        }
        let resolver = LinkedPackageResolver(manifests: manifests, normalizer: normalizer)
        let result = try resolver.resolve(
            linked: linked.products, remotePackages: resolved.filter { $0.kind == .remote },
            localPackages: locals, excludes: Set(settings.excludes),
            platformNames: PlatformNames.manifestNames(
                platformName: context.platformName, supportedPlatforms: linked.supportedPlatforms),
            includeBuildTools: settings.includeBuildTools)
        if !result.unreached.isEmpty && !settings.allowUnreached {
            throw .packagesUnreached(result.unreached.map(\.identity.value))
        }

        let validator = LicenseFileValidator(
            files: files, maximumBytes: LicenseFileValidator.standardMaximumBytes)
        let locator = LicenseLocator()
        var items: [Acknowledgement] = []
        for package in result.linked {
            let names = locator.licenseFileNames(
                among: try directories.topLevelNames(in: package.checkoutPath))
            var documents: [LicenseDocument] = []
            for name in names {
                documents.append(
                    try validator.document(
                        named: name, inFolder: package.checkoutPath, root: package.checkoutPath,
                        owner: package.identity.value))
            }
            items.append(
                Acknowledgement(
                    displayName: package.identity.value, identity: package.identity,
                    normalizedLocation: package.normalizedLocation, documents: documents))
        }
        for entry in settings.manualEntries {
            items.append(
                try manualAcknowledgement(
                    entry, projectDirectory: projectDirectory, validator: validator))
        }
        return try AcknowledgementAssembler(slugger: OutputNameSlugger()).assemble(items)
    }

    private func manualAcknowledgement(
        _ entry: ManualEntry, projectDirectory: String, validator: LicenseFileValidator
    ) throws(DomainError) -> Acknowledgement {
        let path = entry.licensePath
        let parts = path.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard !path.hasPrefix("/"), let name = parts.last, !name.isEmpty else {
            throw .manualEntryOutsideProject(name: entry.name, path: path)
        }
        let folder =
            parts.count > 1
            ? projectDirectory + "/" + parts.dropLast().joined(separator: "/") : projectDirectory
        let document: LicenseDocument
        do {
            document = try validator.document(
                named: name, inFolder: folder, root: projectDirectory, owner: entry.name)
        } catch .licenseOutsideCheckout {
            throw .manualEntryOutsideProject(name: entry.name, path: path)
        }
        let normalizer = PackageIdentityNormalizer()
        let identity = normalizer.identity(forLocation: entry.name)
        return Acknowledgement(
            displayName: entry.name, identity: identity,
            normalizedLocation: "manual/" + identity.value,
            documents: [document])
    }
}
