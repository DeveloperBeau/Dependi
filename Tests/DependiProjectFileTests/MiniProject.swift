/// A small project file in Xcode layout, for the cases that no real fixture has.
enum MiniProject {
    /// The text of a project with one app target. `settings` is the text of the `buildSettings`
    /// value of its one configuration, or `nil` for a target with no configurations.
    static func text(settings: String?, resourceFiles: String) -> String {
        let configurationSections =
            settings.map {
                """

                /* Begin XCBuildConfiguration section */
                \t\tH0 /* Debug */ = {
                \t\t\tisa = XCBuildConfiguration;
                \t\t\tbuildSettings = \($0);
                \t\t\tname = Debug;
                \t\t};
                /* End XCBuildConfiguration section */

                /* Begin XCConfigurationList section */
                \t\tG0 /* list */ = {
                \t\t\tisa = XCConfigurationList;
                \t\t\tbuildConfigurations = (
                \t\t\t\tH0 /* Debug */,
                \t\t\t);
                \t\t\tdefaultConfigurationName = Debug;
                \t\t};
                /* End XCConfigurationList section */

                """
            } ?? ""
        let list = settings == nil ? "" : "\t\t\tbuildConfigurationList = G0 /* list */;\n"
        return """
            // !$*UTF8*$!
            {
            \tarchiveVersion = 1;
            \tclasses = {
            \t};
            \tobjectVersion = 46;
            \tobjects = {

            /* Begin PBXBuildFile section */
            /* End PBXBuildFile section */

            /* Begin PBXFileReference section */
            \t\tC0 /* App.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; path = App.app; sourceTree = BUILT_PRODUCTS_DIR; };
            /* End PBXFileReference section */

            /* Begin PBXGroup section */
            \t\tB0 = {
            \t\t\tisa = PBXGroup;
            \t\t\tchildren = (
            \t\t\t\tC0 /* App.app */,
            \t\t\t);
            \t\t\tsourceTree = "<group>";
            \t\t};
            /* End PBXGroup section */

            /* Begin PBXNativeTarget section */
            \t\tD0 /* App */ = {
            \t\t\tisa = PBXNativeTarget;
            \(list)\t\t\tbuildPhases = (
            \t\t\t\tE0 /* Resources */,
            \t\t\t);
            \t\t\tname = App;
            \t\t\tproductType = "com.apple.product-type.application";
            \t\t};
            /* End PBXNativeTarget section */

            /* Begin PBXProject section */
            \t\tF0 /* Project object */ = {
            \t\t\tisa = PBXProject;
            \t\t\tmainGroup = B0;
            \t\t\ttargets = (
            \t\t\t\tD0 /* App */,
            \t\t\t);
            \t\t};
            /* End PBXProject section */

            /* Begin PBXResourcesBuildPhase section */
            \t\tE0 /* Resources */ = {
            \t\t\tisa = PBXResourcesBuildPhase;
            \t\t\tbuildActionMask = 2147483647;
            \t\t\tfiles = (
            \(resourceFiles)\t\t\t);
            \t\t\trunOnlyForDeploymentPostprocessing = 0;
            \t\t};
            /* End PBXResourcesBuildPhase section */
            \(configurationSections)\t};
            \trootObject = F0 /* Project object */;
            }

            """
    }
}
