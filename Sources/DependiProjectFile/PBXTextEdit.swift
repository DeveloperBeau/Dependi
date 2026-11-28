/// One change to the bytes of a project file: remove some bytes, then insert some text.
struct PBXTextEdit: Equatable {
    /// The byte offset in the original file.
    let offset: Int
    /// The number of original bytes that the edit removes.
    let removeCount: Int
    /// The text that goes in at `offset`.
    let insertText: String
}
