import Foundation

/// The result of looking a tool up by name, command, package, or ID.
public enum ToolLookup: Sendable {
  case found(CLITool)
  case ambiguous([CLITool])
  case notFound(suggestions: [CLITool])
}

extension Catalog {
  /// Finds a tool by ID, name, command name, or package name.
  ///
  /// Exact matches win. When nothing matches, the result carries a few
  /// close names so callers can print a "did you mean" hint.
  public func lookup(_ identifier: String) -> ToolLookup {
    let value = identifier.trimmingCharacters(in: .whitespaces)
    guard !value.isEmpty else {
      return .notFound(suggestions: [])
    }

    if let tool = tools.first(where: { $0.id == value }) {
      return .found(tool)
    }

    let byName = tools.filter { $0.name == value }
    if byName.count == 1 {
      return .found(byName[0])
    }
    if byName.count > 1 {
      return .ambiguous(byName)
    }

    let lowered = value.lowercased()
    let related = tools.filter { tool in
      tool.name.lowercased() == lowered
        || tool.commandNames.contains(where: { $0.lowercased() == lowered })
        || tool.packageName?.lowercased() == lowered
    }
    if related.count == 1 {
      return .found(related[0])
    }
    if related.count > 1 {
      return .ambiguous(related)
    }

    return .notFound(suggestions: suggestions(for: lowered))
  }

  /// Tools whose name, commands, or package contain the query, or whose
  /// summary has a word starting with it.
  public func search(_ query: String) -> [CLITool] {
    let terms = query
      .lowercased()
      .split(whereSeparator: \.isWhitespace)
      .map(String.init)
    guard !terms.isEmpty else { return tools }

    return tools.filter { tool in
      let names = ([tool.name, tool.packageName ?? ""] + tool.commandNames)
        .joined(separator: " ")
        .lowercased()
      let words = (tool.summary ?? "")
        .lowercased()
        .split { !$0.isLetter && !$0.isNumber }
      return terms.allSatisfy { term in
        names.contains(term) || words.contains { $0.hasPrefix(term) }
      }
    }
  }

  private func suggestions(for query: String, limit: Int = 5) -> [CLITool] {
    let scored = tools.compactMap { tool -> (CLITool, Int)? in
      let names = [tool.name] + tool.commandNames + [tool.packageName ?? ""]
      let best = names
        .filter { !$0.isEmpty }
        .map { Self.similarity(query, $0.lowercased()) }
        .max() ?? 0
      return best > 0 ? (tool, best) : nil
    }

    return scored
      .sorted { lhs, rhs in
        if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
        return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
      }
      .prefix(limit)
      .map(\.0)
  }

  /// Higher is closer. Zero means the names are unrelated.
  static func similarity(_ query: String, _ candidate: String) -> Int {
    if candidate.hasPrefix(query) || query.hasPrefix(candidate) { return 3 }
    if candidate.contains(query) { return 2 }

    let distance = editDistance(query, candidate)
    let allowed = max(1, min(query.count, candidate.count) / 3)
    return distance <= allowed ? 1 : 0
  }

  static func editDistance(_ a: String, _ b: String) -> Int {
    let a = Array(a), b = Array(b)
    if a.isEmpty { return b.count }
    if b.isEmpty { return a.count }

    var previous = Array(0...b.count)
    var current = [Int](repeating: 0, count: b.count + 1)

    for i in 1...a.count {
      current[0] = i
      for j in 1...b.count {
        let cost = a[i - 1] == b[j - 1] ? 0 : 1
        current[j] = min(previous[j] + 1, current[j - 1] + 1, previous[j - 1] + cost)
      }
      swap(&previous, &current)
    }

    return previous[b.count]
  }
}

/// What changed between two scans.
public struct ScanSummary: Sendable {
  public var catalog: Catalog
  public var added: [CLITool]
  public var removed: [CLITool]

  public init(catalog: Catalog, added: [CLITool] = [], removed: [CLITool] = []) {
    self.catalog = catalog
    self.added = added
    self.removed = removed
  }
}
