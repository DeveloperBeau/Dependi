/// The ways that a domain operation can fail. Each message names the package, file or command involved.
public enum DomainError: Error, Equatable, Sendable {
    /// A file or folder does not exist.
    case fileNotFound(path: String)
    /// A file or folder could not be read.
    case fileUnreadable(path: String, reason: String)
    /// A path is not a regular file where one is required.
    case notRegularFile(path: String)
    /// A file or folder could not be written, moved or removed.
    case fileUnwritable(path: String, reason: String)
    /// Symbolic links form a loop.
    case symlinkLoop(path: String)
    /// A child process could not run, ran too long, or wrote too much.
    case processFailed(command: String, reason: String)
    /// A prompt found the end of the input.
    case inputEnded
    /// The configuration file exists but cannot be decoded.
    case configurationCorrupt(path: String, reason: String)
    /// The `SourcePackages` folder cannot be found from the build directory.
    case sourcePackagesNotFound(tried: String)
    /// Xcode did not provide build settings that are needed.
    case buildContextIncomplete(missing: [String])
    /// Two packages have the same identity.
    case identityConflict(first: String, second: String)
    /// Two packages would write to the same output name.
    case slugCollision(first: String, second: String)
    /// A linked product matches no package.
    case productUnmatched(product: String)
    /// A linked product matches more than one package.
    case productAmbiguous(product: String, candidates: [String])
    /// An exclude names a package that does not exist.
    case unmatchedExclude(String)
    /// A package has no license file and no manual entry.
    case licenseMissing(package: String)
    /// A license file resolves to a place outside its package.
    case licenseOutsideCheckout(package: String, path: String)
    /// A license file is longer than the limit.
    case licenseTooLarge(package: String, file: String)
    /// A license file is not valid text.
    case licenseEncoding(package: String, file: String)
    /// A license file holds a control character.
    case licenseControlCharacter(package: String, file: String)
    /// A license file name is not a plain file name.
    case invalidLicenseName(package: String, file: String)
    /// A manual entry points outside the project folder.
    case manualEntryOutsideProject(name: String, path: String)
}
