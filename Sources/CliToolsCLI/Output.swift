import CliToolsCore
import Foundation

enum Output {
  static let isTerminal = isatty(STDOUT_FILENO) != 0

  /// Columns available for text output. Falls back to 100 when unknown.
  static var terminalWidth: Int {
    if let raw = ProcessInfo.processInfo.environment["COLUMNS"], let columns = Int(raw), columns > 20 {
      return columns
    }

    var size = winsize()
    if isTerminal, ioctl(STDOUT_FILENO, TIOCGWINSZ, &size) == 0, size.ws_col > 20 {
      return Int(size.ws_col)
    }

    return 100
  }

  static func json<T: Encodable>(_ value: T) throws {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let data = try encoder.encode(value)
    print(String(decoding: data, as: UTF8.self))
  }

  /// Prints a hint below the main output. Skipped when piping, so scripts stay clean.
  static func hint(_ message: String) {
    guard isTerminal else { return }
    print("\n\(message)")
  }

  static func error(_ message: String) {
    note("Error: \(message)")
  }

  /// Writes to stderr, flushing stdout first so the two streams stay in order.
  static func note(_ message: String) {
    fflush(stdout)
    FileHandle.standardError.write(Data("\(message)\n".utf8))
  }

  /// Pads without ever cutting the text, unlike `String.padding`.
  static func pad(_ text: String, to width: Int) -> String {
    let missing = width - text.count
    return missing > 0 ? text + String(repeating: " ", count: missing) : text
  }

  static func truncate(_ text: String, to width: Int) -> String {
    guard width > 1, text.count > width else { return text }
    return String(text.prefix(width - 1)) + "…"
  }

  /// One line per tool: star, name, source, version, and summary.
  static func table(_ tools: [CLITool], runCounts: [String: Int]? = nil) {
    guard !tools.isEmpty else {
      print("No matching CLI tools.")
      return
    }

    let nameWidth = min(tools.map(\.name.count).max() ?? 0, 28)
    let sourceWidth = tools.map(\.source.label.count).max() ?? 0
    let versions = tools.map { $0.version.map { truncate(shortVersion($0), to: 16) } ?? "" }
    let versionWidth = versions.map(\.count).max() ?? 0
    let runsWidth = runCounts == nil ? 0 : 7
    let fixed = 2 + nameWidth + 2 + sourceWidth + 2 + (versionWidth > 0 ? versionWidth + 2 : 0) + runsWidth
    let summaryWidth = isTerminal ? max(terminalWidth - fixed, 0) : Int.max

    for (tool, version) in zip(tools, versions) {
      var line = tool.isFavorite ? "★ " : "  "
      line += pad(truncate(tool.name, to: nameWidth), to: nameWidth + 2)
      line += pad(tool.source.label, to: sourceWidth + 2)
      if versionWidth > 0 {
        line += pad(version, to: versionWidth + 2)
      }
      if let runCounts {
        let runs = runCounts[tool.id] ?? 0
        line += pad(runs > 0 ? "×\(runs)" : "-", to: runsWidth)
      }

      var notes: [String] = []
      if !tool.isAvailable { notes.append("missing") }
      if tool.isArchived { notes.append("archived") }
      var summary = tool.summary ?? ""
      if !notes.isEmpty {
        summary = "[\(notes.joined(separator: ", "))] \(summary)"
      }
      line += truncate(summary, to: summaryWidth)
      print(trimTrailingSpaces(line))
    }
  }

  /// Pulls the version number out of a raw `--version` line, e.g. "gh version 2.80.0 (2026-01-01)" → "2.80.0".
  static func shortVersion(_ raw: String) -> String {
    guard let match = raw.firstMatch(of: /\d+(?:\.\d+)+[0-9A-Za-z.\-+]*/) else {
      return raw
    }
    return String(match.output).trimmingCharacters(in: CharacterSet(charactersIn: ".-+"))
  }

  static func trimTrailingSpaces(_ line: String) -> String {
    var trimmed = line
    while trimmed.last == " " { trimmed.removeLast() }
    return trimmed
  }

  static func details(_ tool: CLITool, includeHelp: Bool) {
    var title = tool.name
    if tool.isFavorite { title = "★ " + title }
    print(title)
    if let summary = tool.summary, !summary.isEmpty {
      print(summary)
    }
    print("")

    var rows: [(String, String)] = []
    rows.append(("Source", tool.source.label))
    if let version = tool.version { rows.append(("Version", version)) }
    if let package = tool.packageName, package != tool.name {
      rows.append(("Package", package))
    }
    if tool.commandNames.count > 1 {
      rows.append(("Commands", tool.commandNames.joined(separator: ", ")))
    }
    rows.append(("Path", tool.path))
    if tool.resolvedPath != tool.path {
      rows.append(("Resolves to", tool.resolvedPath))
    }
    if let homepage = tool.homepage { rows.append(("Homepage", homepage.absoluteString)) }
    if let installedAt = tool.installedAt {
      rows.append(("Installed", installedAt.formatted(date: .abbreviated, time: .omitted)))
    }
    var status: [String] = []
    if tool.isArchived { status.append("archived") }
    if !tool.isAvailable { status.append("not installed anymore") }
    if !status.isEmpty { rows.append(("Status", status.joined(separator: ", "))) }

    let width = rows.map(\.0.count).max() ?? 0
    for (label, value) in rows {
      print("\(pad(label + ":", to: width + 2))\(value)")
    }

    if let examples = tool.examples, !examples.isEmpty {
      print("\nExamples:")
      self.examples(examples)
    }

    if includeHelp, let help = tool.help {
      print("\nHelp:\n\(help)")
    }
  }

  static func examples(_ examples: [ToolExample]) {
    for (index, example) in examples.enumerated() {
      if index > 0 { print("") }
      if !example.description.isEmpty {
        print("  \(example.description)")
      }
      print("    $ \(example.command)")
    }
  }

  static func usage(_ usage: [CommandUsage]) {
    let countWidth = usage.map { "×\($0.count)".count }.max() ?? 2
    for item in usage {
      let count = pad("×\(item.count)", to: countWidth + 2)
      let date = item.lastUsed?.formatted(date: .abbreviated, time: .omitted) ?? "unknown date"
      print("\(count)\(pad(date, to: 14))\(item.command)")
    }
  }
}
