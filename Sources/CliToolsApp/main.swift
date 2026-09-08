import CliToolsCore
import Observation
import SwiftUI

@main
struct CliToolsDesktopApp: App {
  @State private var model = CatalogViewModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup("CLI Tools") {
      CatalogView()
        .environment(model)
        .task {
          await model.refresh()

          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            await model.refresh()
          }
        }
    }
    .defaultSize(width: 980, height: 640)
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.refresh() }
      }
    }
  }
}

private enum CatalogSection: String, CaseIterable, Identifiable {
  case all = "All Tools"
  case favorites = "Favorites"
  case archived = "Archive"
  case unavailable = "Unavailable"

  var id: Self { self }

  var icon: String {
    switch self {
    case .all: "terminal"
    case .favorites: "star"
    case .archived: "archivebox"
    case .unavailable: "questionmark.folder"
    }
  }
}

@MainActor
@Observable
private final class CatalogViewModel {
  var catalog = Catalog()
  var selection: CLITool.ID?
  var section = CatalogSection.all
  var search = ""
  var isScanning = false
  var inspectingToolID: CLITool.ID?
  var errorMessage: String?

  @ObservationIgnored
  private let repository = CatalogRepository()

  @ObservationIgnored
  private let inspector = ToolInspector()

  var visibleTools: [CLITool] {
    catalog.tools.filter { tool in
      let belongsToSection = switch section {
      case .all: !tool.isArchived && tool.isAvailable
      case .favorites: tool.isFavorite && !tool.isArchived && tool.isAvailable
      case .archived: tool.isArchived
      case .unavailable: !tool.isAvailable
      }

      let matchesSearch = search.isEmpty
        || tool.name.localizedCaseInsensitiveContains(search)
        || tool.source.label.localizedCaseInsensitiveContains(search)
        || tool.commandNames.contains {
          $0.localizedCaseInsensitiveContains(search)
        }

      return belongsToSection && matchesSearch
    }
  }

  var selectedTool: CLITool? {
    catalog.tools.first { $0.id == selection }
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
    guard inspectingToolID == nil else { return }
    inspectingToolID = tool.id
    defer { inspectingToolID = nil }

    let inspection = await inspector.inspect(tool)

    do {
      catalog = try await repository.updateMetadata(
        tool: tool.id,
        version: inspection.version,
        help: inspection.help,
        summary: inspection.summary,
        homepage: inspection.homepage
      )
    } catch {
      errorMessage = error.localizedDescription
    }
  }
}

private struct CatalogView: View {
  @Environment(CatalogViewModel.self) private var model

  var body: some View {
    @Bindable var model = model

    NavigationSplitView {
      List(CatalogSection.allCases, selection: $model.section) { section in
        Label(section.rawValue, systemImage: section.icon)
          .tag(section)
      }
      .navigationTitle("CLI Tools")
    } content: {
      List(model.visibleTools, selection: $model.selection) { tool in
        ToolRow(tool: tool)
          .tag(tool.id)
          .contextMenu {
            Button(tool.isFavorite ? "Remove Favorite" : "Add Favorite") {
              Task { await model.toggleFavorite(tool) }
            }

            Button(tool.isArchived ? "Restore" : "Archive") {
              Task { await model.toggleArchived(tool) }
            }
          }
      }
      .navigationTitle(model.section.rawValue)
      .searchable(text: $model.search, prompt: "Search tools")
      .overlay {
        if model.visibleTools.isEmpty && !model.isScanning {
          ContentUnavailableView(
            "No Tools",
            systemImage: model.section.icon,
            description: Text("Run a scan or choose another section.")
          )
        }
      }
      .toolbar {
        ToolbarItem {
          Button {
            Task { await model.refresh() }
          } label: {
            if model.isScanning {
              ProgressView()
                .controlSize(.small)
            } else {
              Label("Scan", systemImage: "arrow.clockwise")
            }
          }
          .disabled(model.isScanning)
          .help("Scan for installed CLI tools")
        }
      }
    } detail: {
      if let tool = model.selectedTool {
        ToolDetail(tool: tool)
      } else {
        ContentUnavailableView(
          "Select a CLI Tool",
          systemImage: "terminal",
          description: Text("Choose a tool to see its details.")
        )
      }
    }
    .alert(
      "CLI Tools",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { if !$0 { model.errorMessage = nil } }
      )
    ) {
      Button("OK") { model.errorMessage = nil }
    } message: {
      Text(model.errorMessage ?? "")
    }
  }
}

private struct ToolRow: View {
  let tool: CLITool

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: "terminal.fill")
        .foregroundStyle(.secondary)
        .frame(width: 24)

      VStack(alignment: .leading, spacing: 3) {
        Text(tool.name)
          .font(.headline)

        Text(tool.source.label)
          .font(.caption)
          .foregroundStyle(.secondary)

        if tool.commandNames.count > 1 {
          Text("\(tool.commandNames.count) commands")
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
      }

      Spacer()

      if tool.isFavorite {
        Image(systemName: "star.fill")
          .foregroundStyle(.yellow)
      }

      if !tool.isAvailable {
        Image(systemName: "exclamationmark.triangle.fill")
          .foregroundStyle(.orange)
      }
    }
    .padding(.vertical, 3)
  }
}

private struct ToolDetail: View {
  @Environment(CatalogViewModel.self) private var model
  let tool: CLITool

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        HStack(alignment: .top) {
          Image(systemName: "terminal.fill")
            .font(.system(size: 38))
            .foregroundStyle(.tint)

          VStack(alignment: .leading, spacing: 4) {
            Text(tool.name)
              .font(.largeTitle.bold())
            Text(tool.source.label)
              .foregroundStyle(.secondary)
          }

          Spacer()
        }

        HStack {
          Button {
            Task { await model.inspect(tool) }
          } label: {
            if model.inspectingToolID == tool.id {
              ProgressView()
                .controlSize(.small)
            } else {
              Text(tool.help == nil ? "Load Usage" : "Refresh Usage")
            }
          }
          .buttonStyle(.borderedProminent)
          .disabled(model.inspectingToolID != nil)

          Button(tool.isFavorite ? "Favorited" : "Favorite") {
            Task { await model.toggleFavorite(tool) }
          }
          .buttonStyle(.bordered)

          Button(tool.isArchived ? "Restore" : "Archive") {
            Task { await model.toggleArchived(tool) }
          }
          .buttonStyle(.bordered)

          Button("Copy Command") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(tool.name, forType: .string)
          }
          .buttonStyle(.bordered)
        }

        GroupBox("Location") {
          if let packageName = tool.packageName {
            LabeledContent("Package", value: packageName)
          }
          LabeledContent("Command", value: tool.name)
          LabeledContent("Path", value: tool.path)
          LabeledContent("Resolved path", value: tool.resolvedPath)
          LabeledContent("Available", value: tool.isAvailable ? "Yes" : "No")
        }

        if tool.commandNames.count > 1 {
          GroupBox("Commands") {
            Text(tool.commandNames.joined(separator: ", "))
              .font(.system(.body, design: .monospaced))
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }

        if let summary = tool.summary {
          GroupBox("About") {
            Text(summary)
              .frame(maxWidth: .infinity, alignment: .leading)

            if let homepage = tool.homepage {
              Link(homepage.absoluteString, destination: homepage)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }

        if let version = tool.version {
          GroupBox("Version") {
            Text(version)
              .textSelection(.enabled)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }

        if let help = tool.help {
          GroupBox("Usage") {
            ScrollView(.horizontal) {
              Text(help)
                .font(.system(.body, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
          }
        }

        GroupBox("Discovery") {
          LabeledContent("First seen", value: tool.firstSeenAt.formatted())
          LabeledContent("Last seen", value: tool.lastSeenAt.formatted())
        }
      }
      .padding(28)
      .frame(maxWidth: 720, alignment: .leading)
    }
    .navigationTitle(tool.name)
  }
}
