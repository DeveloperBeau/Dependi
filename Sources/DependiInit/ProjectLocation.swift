/// Where the project is: its folder and its project file.
struct ProjectLocation: Equatable {
    /// The folder that holds the project. Dependi's files go here.
    let root: String
    /// The path of the `.xcodeproj` folder.
    let projectFile: String
}
