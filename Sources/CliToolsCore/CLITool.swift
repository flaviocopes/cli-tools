import Foundation

public enum ToolSource: String, Codable, CaseIterable, Sendable {
  case homebrew
  case npm
  case cargo
  case python
  case local
  case path

  public var label: String {
    switch self {
    case .homebrew: "Homebrew"
    case .npm: "npm"
    case .cargo: "Cargo"
    case .python: "Python"
    case .local: "Local"
    case .path: "PATH"
    }
  }
}

public struct CLITool: Codable, Identifiable, Hashable, Sendable {
  public let id: String
  public var name: String
  public var path: String
  public var resolvedPath: String
  public var source: ToolSource
  public var isFavorite: Bool
  public var isArchived: Bool
  public var isAvailable: Bool
  public var summary: String?
  public var version: String?
  public var help: String?
  public var homepage: URL?
  public var packageName: String?
  public var commands: [String]?
  public var firstSeenAt: Date
  public var lastSeenAt: Date

  public init(
    id: String,
    name: String,
    path: String,
    resolvedPath: String,
    source: ToolSource,
    isFavorite: Bool = false,
    isArchived: Bool = false,
    isAvailable: Bool = true,
    summary: String? = nil,
    version: String? = nil,
    help: String? = nil,
    homepage: URL? = nil,
    packageName: String? = nil,
    commands: [String]? = nil,
    firstSeenAt: Date = .now,
    lastSeenAt: Date = .now
  ) {
    self.id = id
    self.name = name
    self.path = path
    self.resolvedPath = resolvedPath
    self.source = source
    self.isFavorite = isFavorite
    self.isArchived = isArchived
    self.isAvailable = isAvailable
    self.summary = summary
    self.version = version
    self.help = help
    self.homepage = homepage
    self.packageName = packageName
    self.commands = commands
    self.firstSeenAt = firstSeenAt
    self.lastSeenAt = lastSeenAt
  }

  public var commandNames: [String] {
    commands ?? [name]
  }
}

public struct Catalog: Codable, Sendable {
  public var tools: [CLITool]
  public var lastScanAt: Date?

  public init(tools: [CLITool] = [], lastScanAt: Date? = nil) {
    self.tools = tools
    self.lastScanAt = lastScanAt
  }
}
