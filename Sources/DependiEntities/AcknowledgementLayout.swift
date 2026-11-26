/// How the acknowledgements are laid out in the settings bundle.
public enum AcknowledgementLayout: String, Hashable, Sendable, Codable, CaseIterable {
    /// One child pane for each package, listed on an index pane. This is the default.
    case panePerPackage
    /// Every license on the index pane itself, with no child panes.
    case singlePage
}
