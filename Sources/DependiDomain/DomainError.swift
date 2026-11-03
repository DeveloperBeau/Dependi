/// The ways that a domain operation can fail. Each message names the file or command involved.
public enum DomainError: Error, Equatable, Sendable {
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
}
