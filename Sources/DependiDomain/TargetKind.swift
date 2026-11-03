/// The type of a target in a package manifest.
public enum TargetKind: String, Equatable, Sendable {
    /// Code that is linked into the product.
    case regular
    /// A Swift macro that runs at build time.
    case macro
    /// A build tool or command plugin that runs at build time.
    case plugin
    /// A prebuilt binary.
    case binary
    /// An executable.
    case executable
    /// A test target.
    case test
    /// Any other type.
    case other
}
