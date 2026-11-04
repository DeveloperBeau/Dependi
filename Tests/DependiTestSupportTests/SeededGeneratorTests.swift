import TestHelpers
import Testing

@Suite("Seeded generator", .timeLimit(.minutes(1)))
struct SeededGeneratorTests {
    @Test("the default seed gives these first values, computed by hand with the SplitMix64 steps")
    func defaultSeedFirstValues() {
        var generator = SeededGenerator()
        #expect(generator.next() == 0x6FB8_FDC7_B8E1_F137)
        #expect(generator.next() == 0xD729_B0F1_5C23_76AF)
        #expect(generator.next() == 0xE4AB_8C08_8281_3BB3)
    }

    @Test("two generators with the same seed give the same sequence and other seeds differ")
    func sameSeedSameSequence() {
        var first = SeededGenerator(seed: 99)
        var second = SeededGenerator(seed: 99)
        var other = SeededGenerator(seed: 100)
        let one = (0..<8).map { _ in first.next() }
        #expect(one == (0..<8).map { _ in second.next() })
        #expect(one != (0..<8).map { _ in other.next() })
    }
}
