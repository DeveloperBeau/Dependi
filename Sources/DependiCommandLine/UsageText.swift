/// The help text that documents every command and flag.
public enum UsageText {
    /// The full usage text.
    public static let text = """
        Usage: dependi <command> [flags]

        Commands:
          generate                      Write the acknowledgements into the settings bundle.
          init --project <path> [--dry-run]
                                        Add Dependi to the project at <path>.
          version, --version            Print the version.
          help, --help, -h              Print this text.

        Flags for init:
          --project <path>              The project to change. Required.
          --dry-run                     Show what would change. Write nothing.
        """
}
