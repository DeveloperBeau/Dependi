extension DomainError: CustomStringConvertible {
    /// A plain sentence that names the package, file or command involved.
    public var description: String {
        switch self {
        case .fileNotFound(let path): return "The file or folder \(path) does not exist."
        case .fileUnreadable(let path, let reason): return "Cannot read \(path): \(reason)."
        case .notRegularFile(let path): return "\(path) is not a regular file."
        case .fileUnwritable(let path, let reason): return "Cannot write \(path): \(reason)."
        case .symlinkLoop(let path): return "The links at \(path) form a loop."
        case .processFailed(let command, let reason):
            return "The command \(command) failed: \(reason)."
        case .inputEnded: return "The input ended before an answer was given."
        case .configurationCorrupt(let path, let reason):
            return "The configuration \(path) is not valid: \(reason)."
        case .sourcePackagesNotFound(let tried):
            return
                "Cannot find the SourcePackages folder from \(tried). Set sourcePackagesPath in .dependi.json."
        case .buildContextIncomplete(let missing):
            return "These build settings are missing: \(missing.joined(separator: ", "))."
        case .identityConflict(let first, let second):
            return "Two packages have the same name: \(first) and \(second)."
        case .slugCollision(let first, let second):
            return "Two packages would write to the same file: \(first) and \(second)."
        case .productUnmatched(let product): return "No package provides the product \(product)."
        case .productAmbiguous(let product, let candidates):
            return
                "More than one package provides the product \(product): \(candidates.joined(separator: ", "))."
        case .unmatchedExclude(let name): return "The exclude \(name) matches no package."
        case .licenseMissing(let package): return "The package \(package) has no license file."
        case .licenseOutsideCheckout(let package, let path):
            return "A license file of \(package) resolves outside the package, to \(path)."
        case .licenseTooLarge(let package, let file):
            return "The license file \(file) of \(package) is too large."
        case .licenseEncoding(let package, let file):
            return "The license file \(file) of \(package) is not valid text."
        case .licenseControlCharacter(let package, let file):
            return "The license file \(file) of \(package) holds a control character."
        case .invalidLicenseName(let package, let file):
            return "The license file name \(file) of \(package) is not a plain file name."
        case .manualEntryOutsideProject(let name, let path):
            return
                "The license path \(path) of the manual entry \(name) is outside the project folder."
        case .revisionMismatch(let package, let pinned, let checkedOut):
            return
                "The package \(package) is checked out at \(checkedOut) but Package.resolved pins \(pinned). Resolve the packages again."
        case .packagesUnreached(let names):
            return
                "These resolved packages are not linked by the app: \(names.joined(separator: ", ")). Exclude them or set allowUnreached."
        case .scriptSandboxEnabled:
            return
                "The user script sandbox is on, so Dependi cannot read the package checkouts. Set ENABLE_USER_SCRIPT_SANDBOXING to NO for the target that runs Dependi."
        case .invalidOutputLocation(let path, let reason):
            return "The output location \(path) is not allowed: \(reason)."
        case .projectNotFound(let path): return "There is no Xcode project at \(path)."
        case .initRefused(let reason): return "Cannot set up Dependi: \(reason)"
        }
    }
}
