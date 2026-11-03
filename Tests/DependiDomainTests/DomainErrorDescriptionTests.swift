import DependiDomain
import Testing

@Suite("Domain error messages", .timeLimit(.minutes(1)))
struct DomainErrorDescriptionTests {
    @Test("a message names the package, file or command it is about")
    func messagesNamePayloads() {
        #expect(
            DomainError.fileNotFound(path: "/a/b").description
                == "The file or folder /a/b does not exist.")
        #expect(
            DomainError.licenseMissing(package: "kit").description
                == "The package kit has no license file.")
        #expect(
            DomainError.packagesUnreached(["a", "b"]).description
                == "These resolved packages are not linked by the app: a, b. Exclude them or set allowUnreached."
        )
        #expect(
            DomainError.revisionMismatch(package: "kit", pinned: "p", checkedOut: "c").description
                == "The package kit is checked out at c but Package.resolved pins p. Resolve the packages again."
        )
        #expect(
            DomainError.identityConflict(first: "a/utils", second: "b/utils").description
                == "Two packages have the same name: a/utils and b/utils.")
    }

    @Test("the sandbox message names the setting to change")
    func sandboxMessageNamesTheFix() {
        #expect(
            DomainError.scriptSandboxEnabled.description.contains(
                "Set ENABLE_USER_SCRIPT_SANDBOXING to NO"))
    }

    @Test("every error has a non-empty message that holds each text it carries")
    func everyErrorCarriesItsPayload() {
        let cases: [(DomainError, [String])] = [
            (.fileNotFound(path: "P1"), ["P1"]),
            (.fileUnreadable(path: "P2", reason: "R2"), ["P2", "R2"]),
            (.notRegularFile(path: "P3"), ["P3"]),
            (.fileUnwritable(path: "P4", reason: "R4"), ["P4", "R4"]),
            (.symlinkLoop(path: "P5"), ["P5"]),
            (.processFailed(command: "C6", reason: "R6"), ["C6", "R6"]),
            (.inputEnded, []),
            (.configurationCorrupt(path: "P7", reason: "R7"), ["P7", "R7"]),
            (.sourcePackagesNotFound(tried: "T8"), ["T8"]),
            (.buildContextIncomplete(missing: ["M9", "N9"]), ["M9", "N9"]),
            (.identityConflict(first: "F10", second: "S10"), ["F10", "S10"]),
            (.slugCollision(first: "F11", second: "S11"), ["F11", "S11"]),
            (.productUnmatched(product: "P12"), ["P12"]),
            (
                .productAmbiguous(product: "P13", candidates: ["A13", "B13"]),
                ["P13", "A13", "B13"]
            ),
            (.unmatchedExclude("E14"), ["E14"]),
            (.licenseMissing(package: "K15"), ["K15"]),
            (.licenseOutsideCheckout(package: "K16", file: "F16"), ["K16", "F16"]),
            (.licenseTooLarge(package: "K17", file: "F17"), ["K17", "F17"]),
            (.licenseEncoding(package: "K18", file: "F18"), ["K18", "F18"]),
            (.licenseControlCharacter(package: "K19", file: "F19"), ["K19", "F19"]),
            (.invalidLicenseName(package: "K20", file: "F20"), ["K20", "F20"]),
            (.manualEntryOutsideProject(name: "N21", path: "P21"), ["N21", "P21"]),
            (
                .revisionMismatch(package: "K22", pinned: "P22", checkedOut: "C22"),
                ["K22", "P22", "C22"]
            ),
            (.packagesUnreached(["U23", "V23"]), ["U23", "V23"]),
            (.scriptSandboxEnabled, []),
            (.invalidOutputLocation(path: "P24", reason: "R24"), ["P24", "R24"]),
            (.projectNotFound(path: "P25"), ["P25"]),
            (.initRefused(reason: "R26"), ["R26"]),
        ]
        for (error, texts) in cases {
            #expect(!error.description.isEmpty)
            for text in texts {
                #expect(error.description.contains(text), "\(error) lacks \(text)")
            }
        }
    }
}

@Suite("Outside-checkout message")
struct OutsideCheckoutMessageTests {
    @Test("the message names the package and the file and nothing about where the link leads")
    func messageHoldsNoTarget() {
        let error = DomainError.licenseOutsideCheckout(package: "kit", file: "NOTICE")
        #expect(
            error.description == "The license file NOTICE of kit resolves outside the package.")
    }
}
