import Foundation

public struct HistoryEntry: Hashable, Sendable {
  public var command: String
  public var date: Date?
  /// Set when an AI agent ran the command instead of you.
  public var agent: Agent?

  public init(command: String, date: Date? = nil, agent: Agent? = nil) {
    self.command = command
    self.date = date
    self.agent = agent
  }
}

public struct CommandUsage: Codable, Hashable, Sendable, Identifiable {
  public var command: String
  public var count: Int
  public var lastUsed: Date?
  /// The agents that ran this command, if any.
  public var agents: [Agent]

  public var id: String { command }

  public init(command: String, count: Int, lastUsed: Date? = nil, agents: [Agent] = []) {
    self.command = command
    self.count = count
    self.lastUsed = lastUsed
    self.agents = agents
  }

  /// Groups the entries that invoke the tool, most recent first.
  public static func group(_ entries: [HistoryEntry], for tool: CLITool) -> [CommandUsage] {
    let names = Set(tool.commandNames + [tool.name])
    var grouped: [String: CommandUsage] = [:]
    var order: [String] = []

    for entry in entries where ShellHistory.invokes(names, in: entry.command) {
      let command = entry.command.trimmingCharacters(in: .whitespacesAndNewlines)
      var usage = grouped[command] ?? {
        order.append(command)
        return CommandUsage(command: command, count: 0)
      }()

      usage.count += 1
      if let date = entry.date, date > (usage.lastUsed ?? .distantPast) {
        usage.lastUsed = date
      }
      if let agent = entry.agent, !usage.agents.contains(agent) {
        usage.agents.append(agent)
        usage.agents.sort()
      }
      grouped[command] = usage
    }

    return order
      .compactMap { grouped[$0] }
      .sorted {
        switch ($0.lastUsed, $1.lastUsed) {
        case let (a?, b?): a > b
        case (nil, .some): false
        case (.some, nil): true
        case (nil, nil): false
        }
      }
  }
}

/// Reads the command history written by zsh, bash, and fish.
public struct ShellHistory: Sendable {
  public var entries: [HistoryEntry]
  public var loadedAt: Date

  public init(entries: [HistoryEntry], loadedAt: Date = .now) {
    self.entries = entries
    self.loadedAt = loadedAt
  }

  public static func load(
    home: URL = FileManager.default.homeDirectoryForCurrentUser,
    environment: [String: String] = ProcessInfo.processInfo.environment
  ) -> ShellHistory {
    var files: [(URL, Shell)] = [
      (home.appending(path: ".zsh_history"), .zsh),
      (home.appending(path: ".zhistory"), .zsh),
      (home.appending(path: ".histfile"), .zsh),
      (home.appending(path: ".bash_history"), .bash),
      (home.appending(path: ".local/share/fish/fish_history"), .fish)
    ]

    if let custom = environment["HISTFILE"], !custom.isEmpty {
      let url = URL(fileURLWithPath: custom)
      files.insert((url, custom.contains("bash") ? .bash : .zsh), at: 0)
    }

    var seen: Set<String> = []
    var entries: [HistoryEntry] = []

    for (url, shell) in files where seen.insert(url.standardizedFileURL.path).inserted {
      guard let data = try? Data(contentsOf: url) else { continue }

      switch shell {
      case .zsh:
        entries += parseZsh(data)
      case .bash:
        entries += parseBash(String(decoding: data, as: UTF8.self))
      case .fish:
        entries += parseFish(String(decoding: data, as: UTF8.self))
      }
    }

    return ShellHistory(entries: entries)
  }

  /// Groups the history entries that invoke the tool, most recent first.
  public func usage(of tool: CLITool) -> [CommandUsage] {
    CommandUsage.group(entries, for: tool)
  }

  /// How many history entries ran each tool, keyed by tool ID.
  /// One pass over the history, so it stays fast for large catalogs.
  public func runCounts(for tools: [CLITool]) -> [String: Int] {
    var toolIDs: [String: [String]] = [:]
    for tool in tools {
      for name in Set(tool.commandNames + [tool.name]) {
        toolIDs[name, default: []].append(tool.id)
      }
    }

    var counts: [String: Int] = [:]
    for entry in entries {
      var seen: Set<String> = []
      for executable in Self.invokedExecutables(in: entry.command) {
        for id in toolIDs[executable] ?? [] where seen.insert(id).inserted {
          counts[id, default: 0] += 1
        }
      }
    }

    return counts
  }

  public static func invokes(_ names: Set<String>, in command: String) -> Bool {
    invokedExecutables(in: command).contains(where: names.contains)
  }

  static func invokedExecutables(in command: String) -> [String] {
    command
      .replacingOccurrences(of: "&&", with: "|")
      .replacingOccurrences(of: "||", with: "|")
      .replacingOccurrences(of: ";", with: "|")
      .split(separator: "|")
      .compactMap { invokedExecutable(in: String($0)) }
  }

  private static let wrappers: Set<String> = [
    "sudo", "time", "nohup", "env", "exec", "command", "builtin",
    "npx", "bunx", "pnpx", "nice", "caffeinate", "watch", "xargs"
  ]

  static func invokedExecutable(in segment: String) -> String? {
    for token in segment.split(whereSeparator: \.isWhitespace) {
      let word = String(token)

      if word.hasPrefix("-") || word.contains("=") || word.hasPrefix("(") {
        continue
      }

      let name = word.split(separator: "/").last.map(String.init) ?? word
      if wrappers.contains(name) {
        continue
      }
      return name
    }
    return nil
  }

  // MARK: - Parsers

  /// zsh extended history: `: <timestamp>:<duration>;<command>`.
  public static func parseZsh(_ data: Data) -> [HistoryEntry] {
    let text = String(decoding: unmetafy(data), as: UTF8.self)
    var entries: [HistoryEntry] = []
    var pending: (date: Date?, lines: [String])?

    func flush() {
      guard let pending else { return }
      let command = pending.lines.joined(separator: "\n")
      if !command.isEmpty {
        entries.append(HistoryEntry(command: command, date: pending.date))
      }
    }

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      var line = String(rawLine)

      if let continuation = pending, continuation.lines.last?.hasSuffix("\\") == true {
        pending?.lines[continuation.lines.count - 1].removeLast()
        pending?.lines.append(line)
        continue
      }

      flush()
      pending = nil

      var date: Date?
      if line.hasPrefix(": "), let separator = line.firstIndex(of: ";") {
        let header = line[line.index(line.startIndex, offsetBy: 2)..<separator]
        if let stamp = header.split(separator: ":").first, let seconds = TimeInterval(stamp) {
          date = Date(timeIntervalSince1970: seconds)
        }
        line = String(line[line.index(after: separator)...])
      }

      if !line.isEmpty {
        pending = (date, [line])
      }
    }

    flush()
    return entries
  }

  /// bash history, with optional `#<timestamp>` lines when HISTTIMEFORMAT is set.
  public static func parseBash(_ text: String) -> [HistoryEntry] {
    var entries: [HistoryEntry] = []
    var date: Date?

    for line in text.split(whereSeparator: \.isNewline) {
      if line.hasPrefix("#"), let seconds = TimeInterval(line.dropFirst()) {
        date = Date(timeIntervalSince1970: seconds)
        continue
      }
      entries.append(HistoryEntry(command: String(line), date: date))
      date = nil
    }

    return entries
  }

  /// fish history: `- cmd: <command>` followed by `  when: <timestamp>`.
  public static func parseFish(_ text: String) -> [HistoryEntry] {
    var entries: [HistoryEntry] = []

    for line in text.split(whereSeparator: \.isNewline) {
      if line.hasPrefix("- cmd: ") {
        entries.append(HistoryEntry(command: String(line.dropFirst(7))))
      } else if line.hasPrefix("  when: "), let seconds = TimeInterval(line.dropFirst(8)), !entries.isEmpty {
        entries[entries.count - 1].date = Date(timeIntervalSince1970: seconds)
      }
    }

    return entries
  }

  /// zsh escapes bytes above 0x7F with a 0x83 marker followed by the byte XOR 0x20.
  private static func unmetafy(_ data: Data) -> Data {
    guard data.contains(0x83) else { return data }

    var result = Data(capacity: data.count)
    var iterator = data.makeIterator()

    while let byte = iterator.next() {
      if byte == 0x83, let next = iterator.next() {
        result.append(next ^ 0x20)
      } else {
        result.append(byte)
      }
    }

    return result
  }

  private enum Shell {
    case zsh, bash, fish
  }
}
