import Foundation

/// What a tool prints for `<tool> capabilities --json`: what it can do, and what changed in each version.
public struct ToolCapabilities: Codable, Hashable, Sendable {
  public var name: String
  public var version: String?
  public var summary: String?
  public var capabilities: [Capability]
  public var changelog: [Release]

  public struct Capability: Codable, Hashable, Sendable {
    public var description: String
    public var command: String?

    public init(_ description: String, command: String? = nil) {
      self.description = description
      self.command = command
    }
  }

  public struct Release: Codable, Hashable, Sendable {
    public var version: String
    public var date: String?
    public var changes: [String]

    public init(version: String, date: String? = nil, changes: [String]) {
      self.version = version
      self.date = date
      self.changes = changes
    }
  }

  public init(
    name: String,
    version: String? = nil,
    summary: String? = nil,
    capabilities: [Capability],
    changelog: [Release] = []
  ) {
    self.name = name
    self.version = version
    self.summary = summary
    self.capabilities = capabilities
    self.changelog = changelog
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    name = try container.decode(String.self, forKey: .name)
    version = try container.decodeIfPresent(String.self, forKey: .version)
    summary = try container.decodeIfPresent(String.self, forKey: .summary)
    capabilities = try container.decodeIfPresent([Capability].self, forKey: .capabilities) ?? []
    changelog = try container.decodeIfPresent([Release].self, forKey: .changelog) ?? []
  }

  /// Decodes a tool's `capabilities --json` output. Returns nil unless it lists at least one capability.
  public static func parse(_ output: String) -> ToolCapabilities? {
    guard
      let start = output.firstIndex(of: "{"),
      let end = output.lastIndex(of: "}"),
      let manifest = try? JSONDecoder().decode(
        ToolCapabilities.self,
        from: Data(output[start...end].utf8)
      ),
      !manifest.capabilities.isEmpty
    else {
      return nil
    }

    return manifest
  }

  /// True when the help text lists a `capabilities` command, either on its own
  /// ("  capabilities  What this tool can do") or after the tool's name ("  mindmap capabilities").
  /// Only those tools get asked, so a tool that reads `capabilities` as a file or a prompt never sees it.
  public static func isAdvertised(in help: String, commandNames: [String]) -> Bool {
    help.split(whereSeparator: \.isNewline).contains { line in
      let words = line.split(whereSeparator: \.isWhitespace).prefix(2).map(String.init)
      guard let first = words.first else { return false }
      if first == "capabilities" { return true }
      return words.count == 2 && words[1] == "capabilities" && commandNames.contains(first)
    }
  }
}
