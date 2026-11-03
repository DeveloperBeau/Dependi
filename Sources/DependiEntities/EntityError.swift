/// The ways that building or decoding an entity can fail.
public enum EntityError: Error, Equatable, Sendable {
    /// A license file name is empty or holds a path separator or a control character.
    case invalidLicenseFileName(String)
    /// The configuration holds a key that Dependi does not know.
    case unknownConfigurationKey(String)
    /// The pinned version is not three numbers separated by dots.
    case invalidVersion(String)
    /// The pinned commit is not 40 lowercase hexadecimal characters.
    case invalidCommit(String)
}
