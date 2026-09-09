import Foundation

/// An AI coding agent that keeps session transcripts on this Mac.
public enum Agent: String, Codable, CaseIterable, Comparable, Sendable {
  case cursor
  case codex
  case claude

  public var label: String {
    switch self {
    case .cursor: "Cursor"
    case .codex: "Codex"
    case .claude: "Claude Code"
    }
  }

  public static func < (lhs: Agent, rhs: Agent) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

/// Reads the shell commands that AI agents ran, from their session transcripts.
///
/// Agents run commands in their own processes, so nothing reaches your shell
/// history. Each agent does keep a JSONL transcript per session, and every
/// shell call is recorded there. The formats are undocumented, so each parser
/// skips anything it does not recognize.
public struct AgentHistory: Sendable {
  public var entries: [HistoryEntry]
  public var loadedAt: Date

  public init(entries: [HistoryEntry], loadedAt: Date = .now) {
    self.entries = entries
    self.loadedAt = loadedAt
  }

  /// Reads every transcript on disk. This can take a few seconds, so call it on demand.
  public static func load(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> AgentHistory {
    var entries: [HistoryEntry] = []

    for url in transcripts(under: home.appending(path: ".cursor/projects"), matching: "agent-transcripts") {
      entries += parseCursor(lines(in: url))
    }
    for url in transcripts(under: home.appending(path: ".codex/sessions")) {
      entries += parseCodex(lines(in: url))
    }
    for url in transcripts(under: home.appending(path: ".claude/projects")) {
      entries += parseClaude(lines(in: url))
    }

    return AgentHistory(entries: entries)
  }

  /// Groups the agent commands that invoke the tool, most recent first.
  public func usage(of tool: CLITool) -> [CommandUsage] {
    CommandUsage.group(entries, for: tool)
  }

  // MARK: - Parsers

  /// Cursor writes one JSON object per line. Shell calls are `tool_use` blocks
  /// named `Shell`. Calls carry no timestamp, so we date them by the user turn
  /// that started them, which carries a `<timestamp>` tag.
  public static func parseCursor(_ lines: some Sequence<Data>) -> [HistoryEntry] {
    let shellMarker = Data("\"name\":\"Shell\"".utf8)
    let timestampMarker = Data("<timestamp>".utf8)
    var entries: [HistoryEntry] = []
    var turnDate: Date?

    for line in lines {
      if line.contains(marker: timestampMarker) {
        let text = String(decoding: line, as: UTF8.self)
        if let date = cursorTimestamp(in: text) {
          turnDate = date
        }
        continue
      }

      guard line.contains(marker: shellMarker), let object = json(line) else { continue }

      for block in toolUses(in: object) where block["name"] as? String == "Shell" {
        if let input = block["input"] as? [String: Any], let command = input["command"] as? String {
          entries.append(HistoryEntry(command: command, date: turnDate, agent: .cursor))
        }
      }
    }

    return entries
  }

  /// Codex records tool calls as `function_call` payloads. The shell tool has
  /// been renamed over time: `shell` (command as an argv array), `shell_command`,
  /// and `exec_command` (command as a string). Every line has an ISO timestamp.
  public static func parseCodex(_ lines: some Sequence<Data>) -> [HistoryEntry] {
    let marker = Data("\"type\":\"function_call\"".utf8)
    let shellTools: Set<String> = ["shell", "shell_command", "exec_command"]
    var entries: [HistoryEntry] = []

    for line in lines where line.contains(marker: marker) {
      guard
        let object = json(line),
        let payload = object["payload"] as? [String: Any],
        payload["type"] as? String == "function_call",
        let name = payload["name"] as? String,
        shellTools.contains(name),
        let arguments = payload["arguments"] as? String,
        let call = json(Data(arguments.utf8))
      else { continue }

      let command: String?
      if let text = call["cmd"] as? String {
        command = text
      } else if let text = call["command"] as? String {
        command = text
      } else if let argv = call["command"] as? [String] {
        command = argvCommand(argv)
      } else {
        command = nil
      }

      guard let command else { continue }
      let date = (object["timestamp"] as? String).flatMap(isoDate)
      entries.append(HistoryEntry(command: command, date: date, agent: .codex))
    }

    return entries
  }

  /// Claude Code writes assistant messages with `tool_use` blocks named `Bash`.
  /// Each line has an ISO timestamp.
  public static func parseClaude(_ lines: some Sequence<Data>) -> [HistoryEntry] {
    let marker = Data("\"name\":\"Bash\"".utf8)
    var entries: [HistoryEntry] = []

    for line in lines where line.contains(marker: marker) {
      guard let object = json(line) else { continue }
      let date = (object["timestamp"] as? String).flatMap(isoDate)

      for block in toolUses(in: object) where block["name"] as? String == "Bash" {
        if let input = block["input"] as? [String: Any], let command = input["command"] as? String {
          entries.append(HistoryEntry(command: command, date: date, agent: .claude))
        }
      }
    }

    return entries
  }

  // MARK: - Helpers

  private static func transcripts(under root: URL, matching component: String? = nil) -> [URL] {
    guard
      let enumerator = FileManager.default.enumerator(
        at: root,
        includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles, .skipsPackageDescendants]
      )
    else { return [] }

    var urls: [URL] = []
    for case let url as URL in enumerator where url.pathExtension == "jsonl" {
      if let component, !url.pathComponents.contains(component) { continue }
      urls.append(url)
    }
    return urls
  }

  private static func lines(in url: URL) -> FileLines {
    FileLines(url: url)
  }

  private static func json(_ data: Data) -> [String: Any]? {
    (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }

  private static func toolUses(in object: [String: Any]) -> [[String: Any]] {
    guard
      let message = object["message"] as? [String: Any],
      let content = message["content"] as? [[String: Any]]
    else { return [] }
    return content.filter { $0["type"] as? String == "tool_use" }
  }

  /// `["bash", "-lc", "ls -la"]` is really just `ls -la`.
  static func argvCommand(_ argv: [String]) -> String? {
    let shells: Set<String> = ["bash", "zsh", "sh"]
    if argv.count == 3, shells.contains(argv[0]), argv[1].hasPrefix("-") && argv[1].contains("c") {
      return argv[2]
    }
    return argv.isEmpty ? nil : argv.joined(separator: " ")
  }

  private static func isoDate(_ text: String) -> Date? {
    (try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true)))
      ?? (try? Date(text, strategy: .iso8601))
  }

  /// Parses `<timestamp>Wednesday, Sep 9, 2026, 11:19 AM (UTC+2)</timestamp>`.
  static func cursorTimestamp(in text: String) -> Date? {
    guard
      let open = text.range(of: "<timestamp>"),
      let close = text.range(of: "</timestamp>", range: open.upperBound..<text.endIndex)
    else { return nil }

    var value = String(text[open.upperBound..<close.lowerBound])
    var timeZone = TimeZone.current

    if let zone = value.range(of: #"\(UTC[+-]?\d{1,2}(:\d{2})?\)"#, options: .regularExpression) {
      let offset = value[zone].dropFirst(4).dropLast()
      let parts = offset.split(separator: ":")
      if let hours = Int(parts[0]) {
        let minutes = parts.count > 1 ? Int(parts[1]) ?? 0 : 0
        let sign = hours < 0 ? -1 : 1
        timeZone = TimeZone(secondsFromGMT: sign * (abs(hours) * 3600 + minutes * 60)) ?? timeZone
      }
      value.removeSubrange(zone)
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = timeZone
    formatter.dateFormat = "EEEE, MMM d, yyyy, h:mm a"
    return formatter.date(from: value.trimmingCharacters(in: .whitespaces))
  }
}

extension Data {
  /// A fast substring check. `Data.range(of:)` is far too slow for gigabytes of transcripts.
  func contains(marker: Data) -> Bool {
    guard count >= marker.count, !marker.isEmpty else { return false }
    return withUnsafeBytes { haystack in
      marker.withUnsafeBytes { needle in
        memmem(haystack.baseAddress, haystack.count, needle.baseAddress, needle.count) != nil
      }
    }
  }
}

/// Streams a file one line at a time, so large transcripts never sit in memory whole.
struct FileLines: Sequence, IteratorProtocol {
  private let handle: FileHandle?
  private var buffer: [UInt8] = []
  private var position = 0
  private var finished: Bool

  init(url: URL) {
    handle = try? FileHandle(forReadingFrom: url)
    finished = handle == nil
  }

  mutating func next() -> Data? {
    while true {
      let newline = buffer.withUnsafeBytes { bytes -> Int? in
        guard let base = bytes.baseAddress, position < bytes.count else { return nil }
        guard let hit = memchr(base + position, 0x0A, bytes.count - position) else { return nil }
        return UnsafeRawPointer(hit) - base
      }

      if let newline {
        let line = Data(buffer[position..<newline])
        position = newline + 1
        return line
      }

      if finished {
        guard position < buffer.count else { return nil }
        let line = Data(buffer[position...])
        position = buffer.count
        return line
      }

      if let chunk = try? handle?.read(upToCount: 1 << 20), !chunk.isEmpty {
        buffer.removeSubrange(0..<position)
        buffer.append(contentsOf: chunk)
        position = 0
      } else {
        finished = true
        try? handle?.close()
      }
    }
  }
}
