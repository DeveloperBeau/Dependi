/// A repeatable random number generator. The same seed always gives the same sequence.
public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    /// The seed that every fuzz test uses unless a test passes another.
    public static let defaultSeed: UInt64 = 0x00D3_9E4D_1C0F_FEE5

    /// Creates a generator that starts from the given seed.
    public init(seed: UInt64 = SeededGenerator.defaultSeed) {
        state = seed
    }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
