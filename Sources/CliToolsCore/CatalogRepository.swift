import Foundation

public enum CatalogError: LocalizedError, Sendable {
  case toolNotFound(String, suggestions: [CLITool])
  case ambiguousToolName(String, candidates: [CLITool])

  public var errorDescription: String? {
    switch self {
    case .toolNotFound(let value, let suggestions):
      var message = "No CLI tool matches '\(value)'."
      if !suggestions.isEmpty {
        message += " Did you mean: \(suggestions.map(\.name).joined(separator: ", "))?"
      }
      return message
    case .ambiguousToolName(let value, let candidates):
      let list = candidates
        .map { "  \($0.id)  (\($0.source.label))" }
        .joined(separator: "\n")
      return "More than one CLI tool matches '\(value)'. Use one of these IDs:\n\(list)"
    }
  }
}

extension Catalog {
  /// Like `lookup`, but throws a `CatalogError` when there is no single match.
  public func tool(matching identifier: String) throws -> CLITool {
    switch lookup(identifier) {
    case .found(let tool):
      return tool
    case .ambiguous(let candidates):
      throw CatalogError.ambiguousToolName(identifier, candidates: candidates)
    case .notFound(let suggestions):
      throw CatalogError.toolNotFound(identifier, suggestions: suggestions)
    }
  }
}

public actor CatalogRepository {
  public let fileURL: URL

  private let fileManager: FileManager
  private let discovery: ToolDiscovery

  public init(
    fileURL: URL = CatalogRepository.defaultFileURL,
    fileManager: FileManager = .default,
    discovery: ToolDiscovery = ToolDiscovery()
  ) {
    self.fileURL = fileURL
    self.fileManager = fileManager
    self.discovery = discovery
  }

  public static var defaultFileURL: URL {
    FileManager.default.homeDirectoryForCurrentUser
      .appending(path: "Library/Application Support/CliTools", directoryHint: .isDirectory)
      .appending(path: "catalog.json", directoryHint: .notDirectory)
  }

  public func load() throws -> Catalog {
    guard fileManager.fileExists(atPath: fileURL.path) else {
      return Catalog()
    }

    let data = try Data(contentsOf: fileURL)
    return try Self.decoder.decode(Catalog.self, from: data)
  }

  @discardableResult
  public func refresh(at date: Date = .now) throws -> Catalog {
    try scan(at: date).catalog
  }

  /// Rescans the machine and reports which tools appeared or disappeared.
  public func scan(at date: Date = .now) throws -> ScanSummary {
    var catalog = try load()
    let hadScanned = catalog.lastScanAt != nil
    let discovered = discovery.scan(at: date)
    var existingByID = Dictionary(uniqueKeysWithValues: catalog.tools.map { ($0.id, $0) })
    var added: [CLITool] = []

    catalog.tools = discovered.map { tool in
      var previous = existingByID.removeValue(forKey: tool.id)

      if previous == nil, let previousID = existingByID.first(where: {
        $0.value.name == tool.name && $0.value.source == tool.source
      })?.key {
        previous = existingByID.removeValue(forKey: previousID)
      }

      guard var existing = previous else {
        added.append(tool)
        return tool
      }

      existing.name = tool.name
      existing.path = tool.path
      existing.resolvedPath = tool.resolvedPath
      existing.source = tool.source
      existing.packageName = tool.packageName
      existing.commands = tool.commands
      existing.installedAt = tool.installedAt
      existing.isAvailable = true
      existing.lastSeenAt = date
      return existing
    }

    let removed = existingByID.values
      .filter(\.isAvailable)
      .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    for var missing in existingByID.values where missing.isFavorite || missing.isArchived {
      missing.isAvailable = false
      catalog.tools.append(missing)
    }

    catalog.tools.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    catalog.lastScanAt = date
    try save(catalog)

    return ScanSummary(
      catalog: catalog,
      added: hadScanned ? added : [],
      removed: removed
    )
  }

  @discardableResult
  public func setFavorite(_ value: Bool, tool identifier: String) throws -> Catalog {
    try update(identifier) { $0.isFavorite = value }
  }

  @discardableResult
  public func setArchived(_ value: Bool, tool identifier: String) throws -> Catalog {
    try update(identifier) { $0.isArchived = value }
  }

  @discardableResult
  public func updateMetadata(
    tool identifier: String,
    version: String?,
    help: String?,
    summary: String? = nil,
    homepage: URL? = nil,
    examples: [ToolExample]? = nil
  ) throws -> Catalog {
    try update(identifier) {
      let previous = $0.version.flatMap { ToolInspector.isPlausibleVersion($0) ? $0 : nil }
      $0.version = version ?? previous
      $0.help = help ?? $0.help
      $0.summary = summary ?? $0.summary
      $0.homepage = homepage ?? $0.homepage
      $0.examples = examples ?? $0.examples
    }
  }

  private func update(
    _ identifier: String,
    change: (inout CLITool) -> Void
  ) throws -> Catalog {
    var catalog = try load()
    let tool = try catalog.tool(matching: identifier)
    guard let index = catalog.tools.firstIndex(where: { $0.id == tool.id }) else {
      throw CatalogError.toolNotFound(identifier, suggestions: [])
    }

    change(&catalog.tools[index])
    try save(catalog)
    return catalog
  }

  private func save(_ catalog: Catalog) throws {
    try fileManager.createDirectory(
      at: fileURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try Self.encoder.encode(catalog)
    try data.write(to: fileURL, options: .atomic)
  }

  private static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return encoder
  }()

  private static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    return decoder
  }()
}
