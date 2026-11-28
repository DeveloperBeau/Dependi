/// One significant piece of project file text and the bytes it covers.
struct PBXTextSpan: Equatable {
    enum Kind: Equatable {
        /// A quoted string. The range includes the quotes.
        case string
        /// An unquoted word.
        case word
        /// One of `{ } ( ) = ; ,`.
        case punctuation
    }

    let kind: Kind
    let range: Range<Int>
}
