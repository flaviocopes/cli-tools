import Foundation

public enum CatalogError: LocalizedError, Sendable {
  case toolNotFound(String)
  case ambiguousToolName(String)

  public var errorDescription: String? {
    switch self {
    case .toolNotFound(let value):
      "No CLI tool matches '\(value)'."
    case .ambiguousToolName(let value):
      "More than one CLI tool matches '\(value)'. Use its full ID."
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
    var catalog = try load()
    let discovered = discovery.scan(at: date)
    var existingByID = Dictionary(uniqueKeysWithValues: catalog.tools.map { ($0.id, $0) })

    catalog.tools = discovered.map { tool in
      guard var existing = existingByID.removeValue(forKey: tool.id) else {
        return tool
      }

      existing.name = tool.name
      existing.path = tool.path
      existing.resolvedPath = tool.resolvedPath
      existing.source = tool.source
      existing.isAvailable = true
      existing.lastSeenAt = date
      return existing
    }

    for var missing in existingByID.values {
      missing.isAvailable = false
      catalog.tools.append(missing)
    }

    catalog.tools.sort {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    catalog.lastScanAt = date
    try save(catalog)
    return catalog
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
    homepage: URL? = nil
  ) throws -> Catalog {
    try update(identifier) {
      $0.version = version ?? $0.version
      $0.help = help ?? $0.help
      $0.summary = summary ?? $0.summary
      $0.homepage = homepage ?? $0.homepage
    }
  }

  private func update(
    _ identifier: String,
    change: (inout CLITool) -> Void
  ) throws -> Catalog {
    var catalog = try load()
    let matches = catalog.tools.indices.filter {
      catalog.tools[$0].id == identifier || catalog.tools[$0].name == identifier
    }

    guard !matches.isEmpty else {
      throw CatalogError.toolNotFound(identifier)
    }

    guard matches.count == 1, let index = matches.first else {
      throw CatalogError.ambiguousToolName(identifier)
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
