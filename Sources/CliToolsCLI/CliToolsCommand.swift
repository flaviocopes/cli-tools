import CliToolsCore
import Foundation

@main
struct CliToolsCommand {
  static func main() async {
    do {
      try await run(Array(CommandLine.arguments.dropFirst()))
    } catch {
      Output.error(error.localizedDescription)
      Foundation.exit(1)
    }
  }

  private static func run(_ arguments: [String]) async throws {
    guard let first = arguments.first else {
      try await run(["list"])
      return
    }

    switch first {
    case "--version", "-v", "version":
      print("clitools \(Commands.version)")
      return
    case "--help", "-h":
      print(Commands.overview())
      return
    default:
      break
    }

    guard let spec = Commands.spec(for: first) else {
      throw CLIError.unknownCommand(first)
    }

    let rest = Array(arguments.dropFirst())
    if rest.contains("--help") || rest.contains("-h") {
      print(Commands.help(for: spec))
      return
    }

    if spec.name == "help" {
      if let name = rest.first {
        guard let target = Commands.spec(for: name) else {
          throw CLIError.unknownCommand(name)
        }
        print(Commands.help(for: target))
      } else {
        print(Commands.overview())
      }
      return
    }

    let parsed = try ParsedArguments.parse(rest, for: spec)
    let repository = CatalogRepository()

    switch spec.name {
    case "scan":
      try await scan(parsed, repository)
    case "list":
      try await list(parsed, repository, query: parsed.positionals.joined(separator: " "))
    case "search":
      guard !parsed.positionals.isEmpty else {
        throw CLIError.missingTool(command: "search")
      }
      var options = parsed
      options.flags.insert("--all")
      try await list(options, repository, query: parsed.positionals.joined(separator: " "))
    case "show":
      try await show(parsed, repository)
    case "inspect":
      try await inspect(parsed, repository)
    case "examples":
      try await examples(parsed, repository)
    case "history":
      try await history(parsed, repository)
    case "favorite":
      try await toggle(parsed, repository, verb: "favorite") { try await $0.setFavorite(true, tool: $1) }
    case "unfavorite":
      try await toggle(parsed, repository, verb: "unfavorite") { try await $0.setFavorite(false, tool: $1) }
    case "archive":
      try await toggle(parsed, repository, verb: "archive") { try await $0.setArchived(true, tool: $1) }
    case "restore":
      try await toggle(parsed, repository, verb: "restore") { try await $0.setArchived(false, tool: $1) }
    case "stats":
      try await stats(parsed, repository)
    case "catalog-path":
      print(await repository.fileURL.path)
    default:
      throw CLIError.unknownCommand(spec.name)
    }
  }

  // MARK: - Commands

  private static func scan(_ options: ParsedArguments, _ repository: CatalogRepository) async throws {
    let summary = try await repository.scan()
    let catalog = summary.catalog

    if options.has("--json") {
      try Output.json(catalog)
      return
    }

    let active = catalog.tools.filter { $0.isAvailable && !$0.isArchived }
    print("Found \(active.count) CLI tools (\(sourceBreakdown(active))).")

    if !summary.added.isEmpty {
      print("New: \(summary.added.map(\.name).joined(separator: ", "))")
    }
    if !summary.removed.isEmpty {
      print("Gone: \(summary.removed.map(\.name).joined(separator: ", "))")
    }
    Output.hint("Run 'clitools list' to see them.")
  }

  private static func list(
    _ options: ParsedArguments,
    _ repository: CatalogRepository,
    query: String
  ) async throws {
    let catalog = try await loadCatalog(repository)
    let showAll = options.has("--all")
    let onlyArchived = options.has("--archived")
    let includeUnavailable = showAll || options.has("--unavailable")

    var source: ToolSource?
    if let raw = options.value("--source") {
      guard let match = ToolSource.allCases.first(where: {
        $0.rawValue == raw.lowercased() || $0.label.lowercased() == raw.lowercased()
      }) else {
        throw CLIError.invalidValue(option: "--source", value: raw)
      }
      source = match
    }

    var tools = query.isEmpty ? catalog.tools : catalog.search(query)
    tools = tools.filter { tool in
      if onlyArchived { return tool.isArchived }
      if !showAll && tool.isArchived { return false }
      if !includeUnavailable && !tool.isAvailable { return false }
      if options.has("--favorites") && !tool.isFavorite { return false }
      if let source, tool.source != source { return false }
      return true
    }

    let sort = options.value("--sort") ?? "name"
    var runCounts: [String: Int]?
    if sort == "usage" || options.has("--unused") {
      runCounts = ShellHistory.load().runCounts(for: tools)
    }

    if options.has("--unused"), let runCounts {
      tools = tools.filter { runCounts[$0.id] == nil }
    }

    switch sort {
    case "name":
      break
    case "source":
      tools.sort { ($0.source.label, $0.name.lowercased()) < ($1.source.label, $1.name.lowercased()) }
    case "installed":
      tools.sort { ($0.installedAt ?? .distantPast) > ($1.installedAt ?? .distantPast) }
    case "usage":
      let counts = runCounts ?? [:]
      tools.sort {
        let lhs = counts[$0.id] ?? 0, rhs = counts[$1.id] ?? 0
        return lhs != rhs ? lhs > rhs : $0.name.lowercased() < $1.name.lowercased()
      }
    default:
      throw CLIError.invalidValue(option: "--sort", value: sort)
    }

    let total = tools.count
    if let limit = try options.int("--limit") {
      tools = Array(tools.prefix(limit))
    }

    if options.has("--json") {
      try Output.json(tools)
      return
    }

    if options.has("--names") {
      tools.forEach { print($0.name) }
      return
    }

    Output.table(tools, runCounts: sort == "usage" ? runCounts : nil)

    guard !tools.isEmpty else {
      if !query.isEmpty, !showAll {
        Output.hint("Try 'clitools search \(query)' to include archived tools.")
      }
      return
    }

    var footer = tools.count == total ? "\(total) tools." : "\(tools.count) of \(total) tools."
    if options.has("--unused") {
      footer += " None of these appear in your shell history."
    }
    let uninspected = tools.filter { $0.summary == nil && $0.version == nil }.count
    if uninspected > 0 {
      footer += " Run 'clitools inspect <tool>' to add a description and version."
    }
    Output.hint(footer)
  }

  private static func show(_ options: ParsedArguments, _ repository: CatalogRepository) async throws {
    let catalog = try await loadCatalog(repository)
    let tool = try catalog.tool(matching: try identifier(options, command: "show"))

    if options.has("--json") {
      try Output.json(tool)
      return
    }

    Output.details(tool, includeHelp: false)

    if tool.version == nil && tool.summary == nil && tool.help == nil {
      Output.hint("Not inspected yet. Run 'clitools inspect \(tool.name)' for version, description, and examples.")
    } else if tool.help != nil {
      Output.hint("Run 'clitools inspect \(tool.name)' to refresh, or add --json for the full help text.")
    }
  }

  private static func inspect(_ options: ParsedArguments, _ repository: CatalogRepository) async throws {
    let tool = try await inspectTool(try identifier(options, command: "inspect"), repository)

    if options.has("--json") {
      try Output.json(tool)
    } else {
      Output.details(tool, includeHelp: !options.has("--no-help"))
    }
  }

  private static func examples(_ options: ParsedArguments, _ repository: CatalogRepository) async throws {
    let catalog = try await loadCatalog(repository)
    var tool = try catalog.tool(matching: try identifier(options, command: "examples"))

    if tool.examples?.isEmpty ?? true {
      Output.note("No cached examples for \(tool.name). Inspecting it now…")
      tool = try await inspectTool(tool.id, repository)
    }

    let examples = tool.examples ?? []

    if options.has("--json") {
      try Output.json(examples)
      return
    }

    guard !examples.isEmpty else {
      throw CLIError.noExamples(tool.name)
    }

    Output.examples(examples)
  }

  private static func history(_ options: ParsedArguments, _ repository: CatalogRepository) async throws {
    let catalog = try await loadCatalog(repository)
    let tool = try catalog.tool(matching: try identifier(options, command: "history"))
    let agents = options.has("--agents")
    var usage = agents ? AgentHistory.load().usage(of: tool) : ShellHistory.load().usage(of: tool)
    let total = usage.count

    if let limit = try options.int("--limit") {
      usage = Array(usage.prefix(limit))
    }

    if options.has("--json") {
      try Output.json(usage)
      return
    }

    guard !usage.isEmpty else {
      print("No runs of \(tool.name) found in \(agents ? "your agent transcripts" : "your shell history").")
      return
    }

    Output.usage(usage)

    let runs = usage.reduce(0) { $0 + $1.count }
    var footer = "\(runs) runs across \(total) distinct commands."
    if usage.count < total {
      footer = "Showing \(usage.count) of \(total) distinct commands."
    }
    Output.hint(footer)
  }

  private static func toggle(
    _ options: ParsedArguments,
    _ repository: CatalogRepository,
    verb: String,
    apply: (CatalogRepository, String) async throws -> Catalog
  ) async throws {
    guard !options.positionals.isEmpty else {
      throw CLIError.missingTool(command: verb)
    }

    let catalog = try await loadCatalog(repository)
    var failures = 0

    for name in options.positionals {
      do {
        let tool = try catalog.tool(matching: name)
        _ = try await apply(repository, tool.id)
        print("\(pastTense(verb)) \(tool.name).")
      } catch {
        failures += 1
        Output.error(error.localizedDescription)
      }
    }

    if failures > 0 {
      Foundation.exit(1)
    }
  }

  private static func stats(_ options: ParsedArguments, _ repository: CatalogRepository) async throws {
    let catalog = try await loadCatalog(repository)
    let tools = catalog.tools
    let active = tools.filter { $0.isAvailable && !$0.isArchived }
    let bySource = Dictionary(grouping: active, by: \.source).mapValues(\.count)

    struct Stats: Encodable {
      var total: Int
      var active: Int
      var favorites: Int
      var archived: Int
      var unavailable: Int
      var inspected: Int
      var bySource: [String: Int]
      var lastScanAt: Date?
      var catalogPath: String
    }

    let stats = Stats(
      total: tools.count,
      active: active.count,
      favorites: tools.filter(\.isFavorite).count,
      archived: tools.filter(\.isArchived).count,
      unavailable: tools.filter { !$0.isAvailable }.count,
      inspected: tools.filter { $0.version != nil || $0.summary != nil }.count,
      bySource: Dictionary(uniqueKeysWithValues: bySource.map { ($0.key.rawValue, $0.value) }),
      lastScanAt: catalog.lastScanAt,
      catalogPath: await repository.fileURL.path
    )

    if options.has("--json") {
      try Output.json(stats)
      return
    }

    print("\(stats.active) active CLI tools")
    for source in ToolSource.allCases {
      if let count = bySource[source] {
        print("  \(Output.pad(source.label, to: 10))\(count)")
      }
    }
    print("")
    print("Favorites:   \(stats.favorites)")
    print("Archived:    \(stats.archived)")
    print("Missing:     \(stats.unavailable)")
    print("Inspected:   \(stats.inspected) of \(stats.total)")
    if let lastScanAt = stats.lastScanAt {
      print("Last scan:   \(lastScanAt.formatted(date: .abbreviated, time: .shortened))")
    }
    print("Catalog:     \(stats.catalogPath)")
  }

  // MARK: - Helpers

  private static func loadCatalog(_ repository: CatalogRepository) async throws -> Catalog {
    let catalog = try await repository.load()
    if catalog.lastScanAt != nil {
      return catalog
    }

    Output.note("No catalog yet. Scanning this Mac…")
    return try await repository.refresh()
  }

  private static func inspectTool(_ identifier: String, _ repository: CatalogRepository) async throws -> CLITool {
    let catalog = try await loadCatalog(repository)
    let tool = try catalog.tool(matching: identifier)
    let inspection = await ToolInspector().inspect(tool)
    let updated = try await repository.updateMetadata(
      tool: tool.id,
      version: inspection.version,
      help: inspection.help,
      summary: inspection.summary,
      homepage: inspection.homepage,
      examples: inspection.examples
    )
    return updated.tools.first { $0.id == tool.id } ?? tool
  }

  private static func identifier(_ options: ParsedArguments, command: String) throws -> String {
    guard let value = options.positionals.first else {
      throw CLIError.missingTool(command: command)
    }
    return value
  }

  private static func sourceBreakdown(_ tools: [CLITool]) -> String {
    let counts = Dictionary(grouping: tools, by: \.source).mapValues(\.count)
    return ToolSource.allCases
      .compactMap { source in counts[source].map { "\($0) \(source.label)" } }
      .joined(separator: ", ")
  }

  private static func pastTense(_ verb: String) -> String {
    switch verb {
    case "favorite": "Favorited"
    case "unfavorite": "Unfavorited"
    case "archive": "Archived"
    case "restore": "Restored"
    default: verb.capitalized
    }
  }
}
