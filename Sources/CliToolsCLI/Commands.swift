import CliToolsCore
import Foundation

enum Commands {
  static let version = "1.3.0"

  /// What `clitools capabilities` prints. Add a changelog entry for every release, newest first.
  static let manifest = ToolCapabilities(
    name: "clitools",
    version: version,
    summary: "Discover the CLI tools installed on this Mac, and find the one that can do a task.",
    capabilities: [
      .init("See what every installed tool that supports 'capabilities' can do, in one call", command: "clitools capabilities --all --json"),
      .init("Find a tool by name, package, description, or what it can do", command: "clitools search slideshow --json"),
      .init("List the CLI tools installed with Homebrew, npm, Cargo, or by hand", command: "clitools list --json"),
      .init("Learn about one tool: version, description, help, and examples", command: "clitools inspect gh --json"),
      .init("Print ready-to-use examples for a tool", command: "clitools examples rg"),
      .init("Show how you, or your AI agents, ran a tool", command: "clitools history gh --agents"),
      .init("Find the tools you never run", command: "clitools list --unused"),
      .init("Rescan the Mac and report the tools that appeared or disappeared", command: "clitools scan")
    ],
    changelog: [
      .init(version: "1.3.0", date: "2026-10-05", changes: [
        "The app's tool list shows only each tool's name when the window is narrow. The CLI didn't change."
      ]),
      .init(version: "1.2.0", date: "2026-10-05", changes: [
        "New 'capabilities' command. Alone it describes clitools, with a tool it asks that tool, and with --all it lists what every tool that supports it can do.",
        "'inspect' saves a tool's capabilities when its help lists a 'capabilities' command, and 'search' matches them.",
        "Finds commands linked into /opt/homebrew/bin from your home folder, like testvm."
      ]),
      .init(version: "1.1.0", date: "2026-10-03", changes: [
        "Signed with a Developer ID and notarized. The CLI didn't change."
      ]),
      .init(version: "1.0.0", date: "2026-09-30", changes: [
        "First release: scan, list, search, show, inspect, examples, history, favorite, archive, and stats, all with --json."
      ])
    ]
  )

  static let json = Option(name: "--json", help: "Print JSON instead of text.")

  static let all: [CommandSpec] = [
    CommandSpec(
      name: "scan",
      summary: "Rescan the Mac and update the catalog.",
      usage: "clitools scan [--json]",
      options: [json],
      details: "Reports tools that appeared or disappeared since the last scan."
    ),
    CommandSpec(
      name: "list",
      summary: "List the tools in the catalog.",
      usage: "clitools list [query] [options]",
      options: [
        Option(name: "--favorites", help: "Only favorites.", aliases: ["-f"]),
        Option(name: "--archived", help: "Only archived tools."),
        Option(name: "--unavailable", help: "Include tools that are no longer installed."),
        Option(name: "--all", help: "Include archived and unavailable tools.", aliases: ["-a"]),
        Option(name: "--source", help: "Only one source: homebrew, npm, cargo, python, local, path.", takesValue: true),
        Option(name: "--unused", help: "Only tools that never appear in your shell history."),
        Option(name: "--sort", help: "Order by name (default), source, installed, or usage.", takesValue: true),
        Option(name: "--limit", help: "Show at most this many tools.", takesValue: true),
        Option(name: "--names", help: "Print one name per line, handy for piping."),
        json
      ],
      details: """
        A query filters by name, command, package, or summary.
        Without options, archived and missing tools stay hidden.
        """,
      aliases: ["ls"]
    ),
    CommandSpec(
      name: "search",
      summary: "Find tools by name, command, package, or summary.",
      usage: "clitools search <query> [--json]",
      options: [json],
      details: "Same as 'clitools list <query>'. Searches every tool, including archived ones."
    ),
    CommandSpec(
      name: "show",
      summary: "Show what the catalog knows about a tool.",
      usage: "clitools show <tool> [--json]",
      options: [json],
      details: "Reads cached data only. Run 'clitools inspect' to fetch fresh details.",
      aliases: ["info"]
    ),
    CommandSpec(
      name: "inspect",
      summary: "Run a tool's --version and --help and fetch its description and examples.",
      usage: "clitools inspect <tool> [--json] [--no-help]",
      options: [
        Option(name: "--no-help", help: "Skip the full help text in the output."),
        json
      ],
      details: """
        Runs the tool with --version and --help. Homebrew tools get their official
        description and homepage. Examples come from tldr pages and the help text.
        Results are saved to the catalog, so 'show' and 'examples' can reuse them.
        """
    ),
    CommandSpec(
      name: "examples",
      summary: "Print ready-to-use examples for a tool.",
      usage: "clitools examples <tool> [--json]",
      options: [json],
      details: "Uses cached examples. Inspects the tool first if there are none yet.",
      aliases: ["ex"]
    ),
    CommandSpec(
      name: "capabilities",
      summary: "What clitools, or another tool, can do, and what changed in each version.",
      usage: "clitools capabilities [<tool> | --all] [--json]",
      options: [
        Option(name: "--all", help: "Every installed tool that supports 'capabilities'.", aliases: ["-a"]),
        json
      ],
      details: """
        Alone, it describes clitools. With a tool, it runs '<tool> capabilities --json'
        and saves the answer to the catalog. Only tools whose help lists a
        'capabilities' command get asked.
        --all asks again every tool that answered before, so the list is always fresh.
        A new tool joins it once 'clitools capabilities <tool>' or 'clitools inspect <tool>' has asked it.
        """
    ),
    CommandSpec(
      name: "history",
      summary: "Show how you ran a tool, from your shell history.",
      usage: "clitools history <tool> [--agents] [--limit <n>] [--json]",
      options: [
        Option(name: "--agents", help: "Show runs by AI agents (Cursor, Codex, Claude Code) instead of yours."),
        Option(name: "--limit", help: "Show at most this many commands.", takesValue: true),
        json
      ],
      details: """
        Reads zsh, bash, and fish history. Nothing is written to the catalog.
        With --agents it reads the session transcripts that Cursor, Codex, and
        Claude Code keep in your home folder. That can take a few seconds.
        """
    ),
    CommandSpec(
      name: "favorite",
      summary: "Mark one or more tools as favorites.",
      usage: "clitools favorite <tool>...",
      options: [],
      aliases: ["fav"]
    ),
    CommandSpec(
      name: "unfavorite",
      summary: "Remove one or more tools from favorites.",
      usage: "clitools unfavorite <tool>...",
      options: [],
      aliases: ["unfav"]
    ),
    CommandSpec(
      name: "archive",
      summary: "Hide one or more tools from the default list.",
      usage: "clitools archive <tool>...",
      options: []
    ),
    CommandSpec(
      name: "restore",
      summary: "Bring archived tools back.",
      usage: "clitools restore <tool>...",
      options: [],
      aliases: ["unarchive"]
    ),
    CommandSpec(
      name: "stats",
      summary: "Summarize the catalog: counts by source, favorites, and more.",
      usage: "clitools stats [--json]",
      options: [json]
    ),
    CommandSpec(
      name: "catalog-path",
      summary: "Print the path of the catalog file.",
      usage: "clitools catalog-path",
      options: []
    ),
    CommandSpec(
      name: "help",
      summary: "Show help for clitools or one command.",
      usage: "clitools help [command]",
      options: []
    )
  ]

  static func spec(for name: String) -> CommandSpec? {
    all.first { $0.name == name || $0.aliases.contains(name) }
  }

  static func overview() -> String {
    let width = all.map(\.name.count).max() ?? 0
    let lines = all.map { spec in
      "  \(Output.pad(spec.name, to: width + 2))\(spec.summary)"
    }

    return """
      clitools \(version)
      Discover and manage the CLI tools installed on this Mac.

      Usage: clitools <command> [options]

      Commands:
      \(lines.joined(separator: "\n"))

      Every command accepts --help. Most accept --json for machine-readable output.

      Get started:
        clitools scan              Build the catalog.
        clitools list              See what is installed.
        clitools inspect gh        Learn about one tool.
        clitools list --unused     Find tools you never run.

      For agents:
        clitools capabilities --all --json   What every tool that supports 'capabilities' can do.
        clitools search <task> --json        Find a tool by what it does.
      """
  }

  static func help(for spec: CommandSpec) -> String {
    var text = """
      \(spec.summary)

      Usage: \(spec.usage)
      """

    if !spec.aliases.isEmpty {
      text += "\nAlias: \(spec.aliases.joined(separator: ", "))"
    }

    if !spec.options.isEmpty {
      let names = spec.options.map { ([$0.display] + $0.aliases).joined(separator: ", ") }
      let width = names.map(\.count).max() ?? 0
      let lines = zip(names, spec.options).map { name, option in
        "  \(Output.pad(name, to: width + 2))\(option.help)"
      }
      text += "\n\nOptions:\n\(lines.joined(separator: "\n"))"
    }

    if let details = spec.details {
      text += "\n\n\(details)"
    }

    return text
  }
}
