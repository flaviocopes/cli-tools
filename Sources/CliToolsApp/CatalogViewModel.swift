import CliToolsCore
import Observation
import SwiftUI

enum CatalogSection: String, CaseIterable, Identifiable {
  case all = "All Tools"
  case favorites = "Favorites"
  case today = "Installed Today"
  case lastSevenDays = "Last 7 Days"
  case thisMonth = "This Month"
  case archived = "Archive"
  case unavailable = "Unavailable"

  var id: Self { self }

  static let groups: [[CatalogSection]] = [
    [.all, .favorites],
    [.today, .lastSevenDays, .thisMonth],
    [.archived, .unavailable]
  ]

  var icon: String {
    switch self {
    case .all: "terminal.fill"
    case .favorites: "star.fill"
    case .today: "sun.max.fill"
    case .lastSevenDays: "calendar"
    case .thisMonth: "calendar.badge.clock"
    case .archived: "archivebox.fill"
    case .unavailable: "questionmark.circle.fill"
    }
  }

  var tint: Color {
    switch self {
    case .all: .blue
    case .favorites: .yellow
    case .today: .orange
    case .lastSevenDays: .red
    case .thisMonth: .purple
    case .archived: .brown
    case .unavailable: .gray
    }
  }

  var emptyMessage: String {
    switch self {
    case .all: "Run a scan to discover the CLI tools on this Mac."
    case .favorites: "Star a tool to keep it here."
    case .today, .lastSevenDays, .thisMonth: "Nothing was installed in this period."
    case .archived: "Archived tools stay out of the main list."
    case .unavailable: "Every tool in your catalog is still installed."
    }
  }
}

@MainActor
@Observable
final class CatalogViewModel {
  var catalog = Catalog()
  var selection: CLITool.ID?
  var section = CatalogSection.all {
    didSet { sourceFilter = nil }
  }
  var sourceFilter: ToolSource?
  var search = ""
  var isScanning = false
  var inspectingToolIDs: Set<CLITool.ID> = []
  var errorMessage: String?
  var history: ShellHistory?
  var agentHistory: AgentHistory?
  var isLoadingAgentHistory = false

  @ObservationIgnored
  private let repository = CatalogRepository()

  @ObservationIgnored
  private let inspector = ToolInspector()

  var sectionTools: [CLITool] {
    catalog.tools.filter { tool in
      let matchesSearch = search.isEmpty
        || tool.name.localizedCaseInsensitiveContains(search)
        || tool.source.label.localizedCaseInsensitiveContains(search)
        || tool.commandNames.contains {
          $0.localizedCaseInsensitiveContains(search)
        }

      return belongs(tool, to: section) && matchesSearch
    }
  }

  var availableSources: [ToolSource] {
    let present = Set(sectionTools.map(\.source))
    return ToolSource.allCases.filter { present.contains($0) }
  }

  var visibleTools: [CLITool] {
    guard let sourceFilter, availableSources.contains(sourceFilter) else {
      return sectionTools
    }
    return sectionTools.filter { $0.source == sourceFilter }
  }

  var selectedTool: CLITool? {
    visibleTools.first { $0.id == selection }
  }

  var isInspectorPresented: Bool {
    get { selectedTool != nil }
    set { if !newValue { selection = nil } }
  }

  func count(for section: CatalogSection) -> Int {
    catalog.tools.count { belongs($0, to: section) }
  }

  func count(for source: ToolSource) -> Int {
    sectionTools.count { $0.source == source }
  }

  private func belongs(_ tool: CLITool, to section: CatalogSection) -> Bool {
    let isActive = !tool.isArchived && tool.isAvailable
    let calendar = Calendar.current

    switch section {
    case .all:
      return isActive
    case .today:
      guard let installedAt = tool.installedAt else { return false }
      return isActive && calendar.isDateInToday(installedAt)
    case .lastSevenDays:
      guard
        let installedAt = tool.installedAt,
        let start = calendar.date(
          byAdding: .day,
          value: -6,
          to: calendar.startOfDay(for: .now)
        )
      else {
        return false
      }
      return isActive && installedAt >= start && installedAt <= .now
    case .thisMonth:
      guard
        let installedAt = tool.installedAt,
        let interval = calendar.dateInterval(of: .month, for: .now)
      else {
        return false
      }
      return isActive && interval.contains(installedAt)
    case .favorites:
      return tool.isFavorite && isActive
    case .archived:
      return tool.isArchived
    case .unavailable:
      return !tool.isAvailable
    }
  }

  func refresh() async {
    guard !isScanning else { return }
    isScanning = true
    defer { isScanning = false }

    do {
      catalog = try await repository.refresh()
      errorMessage = nil
    } catch {
      errorMessage = error.localizedDescription
    }

    history = await Task.detached(priority: .utility) {
      ShellHistory.load()
    }.value
  }

  func usage(of tool: CLITool) async -> [CommandUsage] {
    guard let history else { return [] }
    return await Task.detached(priority: .userInitiated) {
      history.usage(of: tool)
    }.value
  }

  /// Reads every agent transcript on disk. Slow, so it only runs when asked.
  func loadAgentHistory() async {
    guard !isLoadingAgentHistory else { return }
    isLoadingAgentHistory = true
    defer { isLoadingAgentHistory = false }

    agentHistory = await Task.detached(priority: .userInitiated) {
      AgentHistory.load()
    }.value
  }

  func agentUsage(of tool: CLITool) async -> [CommandUsage] {
    guard let agentHistory else { return [] }
    return await Task.detached(priority: .userInitiated) {
      agentHistory.usage(of: tool)
    }.value
  }

  func toggleFavorite(_ tool: CLITool) async {
    do {
      catalog = try await repository.setFavorite(!tool.isFavorite, tool: tool.id)
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func toggleArchived(_ tool: CLITool) async {
    do {
      catalog = try await repository.setArchived(!tool.isArchived, tool: tool.id)
      if tool.id == selection {
        selection = nil
      }
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func inspect(_ tool: CLITool) async {
    guard inspectingToolIDs.insert(tool.id).inserted else { return }
    defer { inspectingToolIDs.remove(tool.id) }

    let inspection = await inspector.inspect(tool)

    do {
      catalog = try await repository.updateMetadata(
        tool: tool.id,
        version: inspection.version,
        help: inspection.help,
        summary: inspection.summary,
        homepage: inspection.homepage,
        examples: inspection.examples
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}
