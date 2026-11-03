import DependiDomain
import DependiFileSystem
import Foundation
import TestHelpers
import Testing

@Suite("Disk file system fuzz")
struct DiskFuzzTests {
    private static let pieces = [
        "a", "b", "k", "z", "0", "7", " ", "-", "_", ".", "é", "ü", "日", "本", "ж", "😀",
    ]

    private static func randomName(_ generator: inout SeededGenerator) -> String {
        let length = Int.random(in: 1...10, using: &generator)
        let name = (0..<length).map { _ in pieces.randomElement(using: &generator)! }.joined()
        // A name of only dots is a special entry. A prefix keeps every name ordinary.
        return name.allSatisfy { $0 == "." } ? "n" + name : name
    }

    @Test("names with unicode and spaces round-trip, and listing equals the sorted set written")
    func namesRoundTrip() throws {
        let seed = SeededGenerator.defaultSeed
        var generator = SeededGenerator(seed: seed)
        let disk = DiskFileSystem()
        try TempFolder.run { temp in
            for round in 0..<25 {
                let folder = temp.real + "/round\(round)"
                try disk.createDirectory(at: folder)
                var written: [String: Data] = [:]
                for _ in 0..<Int.random(in: 1...15, using: &generator) {
                    let name = Self.randomName(&generator)
                    let bytes = Data(
                        (0..<Int.random(in: 0...40, using: &generator)).map { _ in
                            UInt8.random(in: 0...255, using: &generator)
                        })
                    try disk.write(bytes, toPath: folder + "/" + name)
                    written[name] = bytes
                }
                let listed = try disk.topLevelNames(in: folder)
                #expect(
                    listed == written.keys.sorted(), "seed \(seed) round \(round): \(listed)")
                for (name, bytes) in written {
                    let read = try disk.readRegularFile(at: folder + "/" + name, upToBytes: 100)
                    #expect(read == bytes, "seed \(seed) round \(round) name \(name)")
                }
            }
        }
    }

    @Test(
        "a read never returns more than limit plus one bytes and never fewer than the file allows")
    func readLengthProperty() throws {
        let seed = SeededGenerator.defaultSeed
        var generator = SeededGenerator(seed: seed)
        let disk = DiskFileSystem()
        try TempFolder.run { temp in
            for round in 0..<40 {
                let size = Int.random(in: 0...200, using: &generator)
                let limit = Int.random(in: 0...200, using: &generator)
                let path = temp.real + "/f\(round)"
                try disk.write(Data(repeating: 0x41, count: size), toPath: path)
                let count = try disk.readRegularFile(at: path, upToBytes: limit).count
                #expect(count == min(size, limit + 1), "seed \(seed) size \(size) limit \(limit)")
            }
        }
    }
}
