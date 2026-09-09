import CliToolsCore
import SwiftUI

struct ToolListView: View {
  @Environment(CatalogViewModel.self) private var model

  var body: some View {
    @Bindable var model = model

    VStack(spacing: 0) {
      ListHeader()

      List(selection: $model.selection) {
        ForEach(model.visibleTools) { tool in
          ToolRow(tool: tool, isSelected: model.selection == tool.id)
            .tag(tool.id)
            .listRowSeparator(.hidden)
            .contextMenu {
              Button(tool.isFavorite ? "Remove Favorite" : "Add Favorite") {
                Task { await model.toggleFavorite(tool) }
              }

              Button(tool.isArchived ? "Restore" : "Archive") {
                Task { await model.toggleArchived(tool) }
              }
            }
        }
      }
      .listStyle(.inset)
      .scrollContentBackground(.hidden)
      .overlay {
        if model.visibleTools.isEmpty && !model.isScanning {
          ContentUnavailableView {
            Label {
              Text(model.section.rawValue)
            } icon: {
              Image(systemName: model.section.icon)
                .foregroundStyle(model.section.tint)
            }
          } description: {
            Text(model.section.emptyMessage)
          }
        }
      }
    }
    .background(.background)
    .searchable(text: $model.search, placement: .toolbar, prompt: "Search tools")
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
  }
}

private struct ListHeader: View {
  @Environment(CatalogViewModel.self) private var model

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .firstTextBaseline, spacing: 10) {
        Image(systemName: model.section.icon)
          .font(.title2)
          .foregroundStyle(model.section.tint)

        Text(model.section.rawValue)
          .font(.system(size: 28, weight: .bold))

        Spacer()

        Text("\(model.visibleTools.count) tools")
          .font(.callout)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }

      if model.availableSources.count > 1 {
        SourceFilterBar()
      }
    }
    .padding(.horizontal, 24)
    .padding(.top, 16)
    .padding(.bottom, 10)
  }
}

private struct SourceFilterBar: View {
  @Environment(CatalogViewModel.self) private var model

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 6) {
        FilterChip(
          title: "All",
          count: model.sectionTools.count,
          isSelected: model.sourceFilter == nil
        ) {
          model.sourceFilter = nil
        }

        ForEach(model.availableSources, id: \.self) { source in
          FilterChip(
            title: source.label,
            count: model.count(for: source),
            isSelected: model.sourceFilter == source
          ) {
            model.sourceFilter = source
          }
        }
      }
    }
  }
}

private struct FilterChip: View {
  let title: String
  let count: Int
  let isSelected: Bool
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      HStack(spacing: 5) {
        Text(title)
          .fontWeight(.medium)
        Text(count, format: .number)
          .monospacedDigit()
          .opacity(0.6)
      }
      .font(.callout)
      .padding(.horizontal, 11)
      .padding(.vertical, 5)
      .foregroundStyle(foreground)
      .background(Capsule().fill(background))
      .contentShape(Capsule())
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
  }

  private var foreground: Color {
    isSelected ? Color(nsColor: .windowBackgroundColor) : Color(nsColor: .secondaryLabelColor)
  }

  private var background: Color {
    if isSelected {
      Color(nsColor: .labelColor).opacity(0.85)
    } else if isHovering {
      Color(nsColor: .labelColor).opacity(0.12)
    } else {
      Color(nsColor: .labelColor).opacity(0.06)
    }
  }
}

private struct ToolRow: View {
  let tool: CLITool
  let isSelected: Bool

  var body: some View {
    HStack(spacing: 12) {
      ToolIcon(tool: tool)

      VStack(alignment: .leading, spacing: 2) {
        HStack(spacing: 6) {
          Text(tool.name)
            .font(.system(.body, design: .monospaced, weight: .semibold))

          if tool.isFavorite {
            Image(systemName: "star.fill")
              .font(.caption2)
              .foregroundStyle(.yellow)
          }

          if !tool.isAvailable {
            Image(systemName: "exclamationmark.triangle.fill")
              .font(.caption2)
              .foregroundStyle(.orange)
          }
        }

        Text(tool.subtitle)
          .font(.callout)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      Spacer(minLength: 12)

      SourceBadge(source: tool.source, isOnSelection: isSelected)

      if let installedAt = tool.installedAt {
        Text(installedAt, format: .relative(presentation: .named))
          .font(.caption)
          .foregroundStyle(.tertiary)
          .frame(width: 88, alignment: .trailing)
          .lineLimit(1)
      }
    }
    .padding(.vertical, 5)
    .padding(.horizontal, 4)
  }
}
