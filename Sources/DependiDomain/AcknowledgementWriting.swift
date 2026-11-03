import DependiEntities

/// Writes acknowledgements into a settings bundle.
public protocol AcknowledgementWriting: Sendable {
    /// Writes one pane for each acknowledgement and an index pane into the bundle folder.
    func write(_ acknowledgements: [Acknowledgement], intoBundleAt bundlePath: String)
        throws(DomainError)
}
