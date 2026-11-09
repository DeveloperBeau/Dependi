import DependiDomain

/// Works out the SDK names that a target supports from its build settings.
enum SupportedPlatformDeriver {
    /// Returns lowercase SDK names in sorted order. The target settings win over the project settings.
    static func platforms(of target: ProjectModel.Object, in model: ProjectModel)
        throws(DomainError) -> [String]
    {
        let targetSettings = try model.buildSettings(of: target)
        let projectSettings = try model.buildSettings(of: model.project)

        func values(_ key: String) -> [String] {
            let fromTarget = tokens(key, in: targetSettings)
            return fromTarget.isEmpty ? tokens(key, in: projectSettings) : fromTarget
        }

        var result = Set<String>()
        let supported = values("SUPPORTED_PLATFORMS").flatMap { $0.split(separator: " ") }
            .map(String.init)
        for sdk in values("SDKROOT") where sdk != "auto" { result.insert(sdk) }
        result.formUnion(supported)
        if values("SUPPORTS_MACCATALYST").contains("yes") { result.insert("maccatalyst") }
        if values("SUPPORTS_XR_DESIGNED_FOR_VISIONOS").contains("yes") { result.insert("xros") }
        return result.sorted()
    }

    /// Collects the lowercase values of one setting over all configurations.
    private static func tokens(_ key: String, in settings: [[String: Any]]) -> [String] {
        var result: [String] = []
        for entry in settings {
            let text: String?
            if let single = entry[key] as? String {
                text = single
            } else if let list = entry[key] as? [String] {
                text = list.joined(separator: " ")
            } else {
                text = nil
            }
            guard let text else { continue }
            let kept = text.split(separator: " ").filter { !$0.hasPrefix("$(") }
                .map { $0.lowercased() }
            if !kept.isEmpty { result.append(kept.joined(separator: " ")) }
        }
        return result
    }
}
