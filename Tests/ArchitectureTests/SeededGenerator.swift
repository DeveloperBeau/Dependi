/// A repeatable random number generator. The same seed always gives the same sequence.
struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    /// The seed that every fuzz test uses unless a test passes another.
    static let defaultSeed: UInt64 = 0x00D3_9E4D_1C0F_FEE5

    init(seed: UInt64 = SeededGenerator.defaultSeed) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
