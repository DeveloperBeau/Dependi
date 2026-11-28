import DependiDomain
import Foundation

/// The result of planning: the text edits, the lines that report them and what they touch.
struct BuildSetupPlan {
    /// The only keys of an edited object that may differ after the edit.
    private static let editableKeys: Set<String> = [
        "files", "children", "buildPhases", "buildSettings",
    ]

    var edits: [PBXTextEdit] = []
    /// One line for each change, and one for each warning.
    var lines: [String] = []
    /// The ids of the objects that the edits add.
    var addedIDs: Set<String> = []
    /// The ids of the existing objects that the edits change.
    var editedIDs: Set<String> = []

    /// Whether the project needs no change.
    var isEmpty: Bool { edits.isEmpty }

    /// Applies the edits from the last offset to the first, so earlier offsets stay valid.
    func apply(to bytes: [UInt8]) -> [UInt8] {
        var result = bytes
        for edit in edits.sorted(by: { $0.offset > $1.offset }) {
            result.replaceSubrange(
                edit.offset..<(edit.offset + edit.removeCount), with: Array(edit.insertText.utf8))
        }
        return result
    }

    /// Checks that the project after the edit differs from the one before only as planned.
    func verify(before: ProjectModel, after: ProjectModel) throws(DomainError) {
        func fail(_ why: String) -> DomainError {
            .fileUnreadable(
                path: before.path,
                reason: "the edit did not give the expected project (\(why)). Nothing was written.")
        }
        guard after.objects.count == before.objects.count + addedIDs.count else {
            throw fail("the object count is wrong")
        }
        for (id, object) in after.objects {
            if addedIDs.contains(id) { continue }
            guard let original = before.objects[id] else { throw fail("an unexpected object") }
            if NSDictionary(dictionary: original).isEqual(to: object) { continue }
            guard editedIDs.contains(id) else {
                throw fail("an object changed that is not planned")
            }
            for key in Set(original.keys).union(object.keys) {
                let same = Self.isEqual(original[key], object[key])
                if same { continue }
                guard Self.editableKeys.contains(key) else { throw fail("the key \(key) changed") }
                if key == "buildSettings" {
                    try checkSettings(original[key], object[key], fail)
                } else if !Self.isSubsequence(
                    original[key] as? [String], of: object[key] as? [String])
                {
                    throw fail("the list \(key) lost or reordered an entry")
                }
            }
        }
        for id in editedIDs where after.objects[id] == nil { throw fail("an object is gone") }
    }

    private func checkSettings(
        _ old: Any?, _ new: Any?, _ fail: (String) -> DomainError
    ) throws(DomainError) {
        guard var old = old as? [String: Any], var new = new as? [String: Any] else {
            throw fail("the build settings are not a dictionary")
        }
        old["ENABLE_USER_SCRIPT_SANDBOXING"] = nil
        new["ENABLE_USER_SCRIPT_SANDBOXING"] = nil
        guard NSDictionary(dictionary: old).isEqual(to: new) else {
            throw fail("a build setting other than the sandbox setting changed")
        }
    }

    /// Whether every item of `small` is in `large`, in the same order.
    private static func isSubsequence(_ small: [String]?, of large: [String]?) -> Bool {
        guard let small, let large else { return false }
        var rest = large[...]
        for item in small {
            guard let index = rest.firstIndex(of: item) else { return false }
            rest = rest[(index + 1)...]
        }
        return true
    }

    private static func isEqual(_ left: Any?, _ right: Any?) -> Bool {
        switch (left, right) {
        case (nil, nil): return true
        case (let left?, let right?): return (left as AnyObject).isEqual(right)
        default: return false
        }
    }
}
