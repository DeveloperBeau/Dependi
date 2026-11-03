import DependiDomain
import DependiEnvironment
import Foundation
import TestHelpers
import Testing

@Suite("Process environment")
struct ProcessEnvironmentTests {
    @Test("a set variable returns its value")
    func setValue() {
        let environment = ProcessEnvironment(variables: ["HOME_DIR": "/x", "MODE": "Release"])
        #expect(environment.value(for: "MODE") == "Release")
        #expect(environment.value(for: "HOME_DIR") == "/x")
    }

    @Test("a missing variable returns nil")
    func missingValue() {
        let environment = ProcessEnvironment(variables: ["MODE": "Release"])
        #expect(environment.value(for: "OTHER") == nil)
        #expect(environment.value(for: "mode") == nil)
        #expect(ProcessEnvironment(variables: [:]).value(for: "MODE") == nil)
    }

    @Test("an empty value stays empty and is not nil")
    func emptyValue() {
        let environment = ProcessEnvironment(variables: ["EMPTY": ""])
        #expect(environment.value(for: "EMPTY") == "")
    }

    @Test("current reads a variable that the test process certainly has")
    func currentHasPath() {
        let path = ProcessEnvironment.current().value(for: "PATH")
        #expect(path != nil)
        #expect(path?.isEmpty == false)
        #expect(ProcessEnvironment.current().value(for: "DEPENDI_SURELY_UNSET_VARIABLE") == nil)
    }

    @Test("current matches the process environment")
    func currentMatchesProcess() {
        let current = ProcessEnvironment.current()
        for (name, value) in ProcessInfo.processInfo.environment {
            #expect(current.value(for: name) == value)
        }
    }

    @Test("random dictionaries answer exactly their own keys")
    func fuzzDictionaries() {
        let seed = SeededGenerator.defaultSeed
        var generator = SeededGenerator(seed: seed)
        let letters = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ_é日 ")
        func word(_ generator: inout SeededGenerator, minimum: Int) -> String {
            String(
                (0..<Int.random(in: minimum...8, using: &generator)).map { _ in
                    letters.randomElement(using: &generator)!
                })
        }
        for round in 0..<100 {
            var variables: [String: String] = [:]
            for _ in 0..<Int.random(in: 0...12, using: &generator) {
                variables[word(&generator, minimum: 1)] = word(&generator, minimum: 0)
            }
            let environment = ProcessEnvironment(variables: variables)
            for (name, value) in variables {
                #expect(environment.value(for: name) == value, "seed \(seed) round \(round)")
            }
            let absent = "absent-" + word(&generator, minimum: 1)
            #expect(environment.value(for: absent) == nil, "seed \(seed) round \(round)")
        }
    }
}
