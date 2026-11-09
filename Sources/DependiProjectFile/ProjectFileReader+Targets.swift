import DependiDomain

extension ProjectFileReader: ApplicationTargetListing {
    /// Returns the names of the native targets whose product type is an application, sorted.
    public func applicationTargets(projectFilePath: String) throws(DomainError) -> [String] {
        let model = try ProjectFileLoader.load(
            projectFile: fileLocation(projectFilePath), files: files)
        var names: [String] = []
        for target in try model.nativeTargets() {
            let object = model.object(target.id, isa: "PBXNativeTarget")
            if object?["productType"] as? String == "com.apple.product-type.application" {
                names.append(target.name)
            }
        }
        return names.sorted()
    }
}
