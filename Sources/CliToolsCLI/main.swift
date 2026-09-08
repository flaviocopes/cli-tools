import CliToolsCore
import Foundation

@main
struct CliToolsCommand {
  static func main() async {
    do {
      try await run()
    } catch {
      writeError(error.localizedDescription)
      Foundation.exit(1)
    }
  }

  private static func run() async throws {
    let arguments = Array(CommandLine.arguments.dropFirst())
    let command = arguments.first ?? "list"
    let options = Array(arguments.dropFirst())
    let repository = CatalogRepository()

    switch command {
    case "scan":
      let catalog = try await repository.refresh()
      if options.contains("--json") {
        try printJSON(catalog)
      } else {
        let available = catalog.tools.filter(\.isAvailable).count
        print("Found \(available) CLI tools.")
      }

    case "list":
      var catalog = try await repository.load()
      if catalog.lastScanAt == nil {
        catalog = try await repository.refresh()
      }

      let tools = filteredTools(catalog.tools, options: options)
      if options.contains("--json") {
        try printJSON(tools)
      } else {
        printTable(tools)
      }

    case "favorite":
      _ = try await repository.setFavorite(true, tool: try identifier(in: options))
      print("Tool added to favorites.")

    case "unfavorite":
      _ = try await repository.setFavorite(false, tool: try identifier(in: options))
      print("Tool removed from favorites.")

    case "archive":
      _ = try await repository.setArchived(true, tool: try identifier(in: options))
      print("Tool archived.")

    case "restore":
      _ = try await repository.setArchived(false, tool: try identifier(in: options))
      print("Tool restored.")

    case "inspect":
      let value = try identifier(in: options)
      var catalog = try await repository.load()
      if catalog.lastScanAt == nil {
        catalog = try await repository.refresh()
      }

      let matches = catalog.tools.filter { $0.id == value || $0.name == value }
      guard let tool = matches.first, matches.count == 1 else {
        if matches.isEmpty {
          throw CatalogError.toolNotFound(value)
        }
        throw CatalogError.ambiguousToolName(value)
      }

      let inspection = await ToolInspector().inspect(tool)
      let updated = try await repository.updateMetadata(
        tool: tool.id,
        version: inspection.version,
        help: inspection.help,
        summary: inspection.summary,
        homepage: inspection.homepage
      )
      let inspectedTool = updated.tools.first { $0.id == tool.id }

      if options.contains("--json") {
        try printJSON(inspectedTool)
      } else if let inspectedTool {
        printInspection(inspectedTool)
      }

    case "catalog-path":
      print(await repository.fileURL.path)

    case "help", "--help", "-h":
      printHelp()

    default:
      throw CLIError.unknownCommand(command)
    }
  }

  private static func filteredTools(
    _ tools: [CLITool],
    options: [String]
  ) -> [CLITool] {
    tools.filter { tool in
      if options.contains("--archived") && !tool.isArchived {
        return false
      }

      if !options.contains("--archived") && tool.isArchived {
        return false
      }

      if options.contains("--favorites") && !tool.isFavorite {
        return false
      }

      if !options.contains("--unavailable") && !tool.isAvailable {
        return false
      }

      return true
    }
  }

  private static func identifier(in options: [String]) throws -> String {
    guard let value = options.first(where: { !$0.hasPrefix("-") }) else {
      throw CLIError.missingTool
    }

    return value
  }

  private static func printJSON<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
  }

  private static func printTable(_ tools: [CLITool]) {
    guard !tools.isEmpty else {
      print("No matching CLI tools.")
      return
    }

    for tool in tools {
      let favorite = tool.isFavorite ? "★" : " "
      let available = tool.isAvailable ? " " : "missing"
      print("\(favorite) \(tool.name.padding(toLength: 24, withPad: " ", startingAt: 0)) \(tool.source.label.padding(toLength: 10, withPad: " ", startingAt: 0)) \(available)")
    }
  }

  private static func printInspection(_ tool: CLITool) {
    print(tool.name)
    if let summary = tool.summary {
      print(summary)
    }
    if let version = tool.version {
      print("Version: \(version)")
    }
    if let homepage = tool.homepage {
      print("Homepage: \(homepage.absoluteString)")
    }
    print("Path: \(tool.path)")

    if let help = tool.help {
      print("\n\(help)")
    }
  }

  private static func printHelp() {
    print(
      """
      Discover and manage CLI tools installed on this Mac.

      Usage:
        clitools scan [--json]
        clitools list [--json] [--favorites] [--archived] [--unavailable]
        clitools favorite <name-or-id>
        clitools unfavorite <name-or-id>
        clitools archive <name-or-id>
        clitools restore <name-or-id>
        clitools inspect <name-or-id> [--json]
        clitools catalog-path
      """
    )
  }

  private static func writeError(_ message: String) {
    FileHandle.standardError.write(Data("Error: \(message)\n".utf8))
  }
}

private enum CLIError: LocalizedError {
  case missingTool
  case unknownCommand(String)

  var errorDescription: String? {
    switch self {
    case .missingTool:
      "Add a tool name or ID."
    case .unknownCommand(let command):
      "Unknown command '\(command)'. Run 'clitools help'."
    }
  }
}
