import CliToolsCore
import SwiftUI

struct ToolDetailView: View {
  @Environment(CatalogViewModel.self) private var model
  let tool: CLITool

  @State private var copied = false
  @State private var usage: [CommandUsage] = []
  @State private var showAllUsage = false

  private var historyKey: String {
    "\(tool.id)|\(model.history?.loadedAt.timeIntervalSince1970 ?? 0)"
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        header
        actions

        if let summary = tool.summary, !summary.isEmpty {
          DetailSection("About") {
            Card {
              VStack(alignment: .leading, spacing: 8) {
                Text(summary)
                  .textSelection(.enabled)

                if let homepage = tool.homepage {
                  Link(destination: homepage) {
                    Label(homepage.host() ?? homepage.absoluteString, systemImage: "safari")
                      .font(.callout)
                  }
                }
              }
            }
          }
        }

        DetailSection("Location") {
          Card {
            VStack(alignment: .leading, spacing: 10) {
              if let packageName = tool.packageName, packageName != tool.name {
                DetailRow("Package", value: packageName)
                Divider()
              }
              DetailRow("Path", value: tool.path)
              if tool.resolvedPath != tool.path {
                Divider()
                DetailRow("Resolves to", value: tool.resolvedPath)
              }
            }
          }
        }

        yourHistory
        examples

        if tool.commandNames.count > 1 {
          DetailSection("Commands") {
            CodeBlock(text: tool.commandNames.joined(separator: "\n"))
          }
        }

        helpSection

        DetailSection("Timeline") {
          Card {
            VStack(spacing: 8) {
              if let installedAt = tool.installedAt {
                HistoryRow("Installed", date: installedAt)
              }
              HistoryRow("First seen", date: tool.firstSeenAt)
              HistoryRow("Last seen", date: tool.lastSeenAt)
            }
          }
        }
      }
      .padding(20)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .task(id: historyKey) {
      showAllUsage = false
      usage = await model.usage(of: tool)
    }
    .task(id: tool.id) {
      await model.inspect(tool)

      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(300))
        guard !Task.isCancelled else { return }
        await model.inspect(tool)
      }
    }
  }

  private var header: some View {
    HStack(alignment: .top, spacing: 14) {
      ToolIcon(tool: tool, size: 56)

      VStack(alignment: .leading, spacing: 6) {
        Text(tool.name)
          .font(.system(.title2, design: .monospaced, weight: .bold))
          .textSelection(.enabled)

        HStack(spacing: 8) {
          SourceBadge(source: tool.source)

          if let version = tool.shortVersion {
            Text(version)
              .font(.caption)
              .foregroundStyle(.secondary)
              .lineLimit(1)
              .textSelection(.enabled)
          }
        }

        if !tool.isAvailable {
          Label("Not found on this Mac", systemImage: "exclamationmark.triangle.fill")
            .font(.caption)
            .foregroundStyle(.orange)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      Button {
        model.selection = nil
      } label: {
        Image(systemName: "xmark.circle.fill")
          .font(.title3)
          .foregroundStyle(.tertiary)
      }
      .buttonStyle(.plain)
      .help("Close")
    }
  }

  private var actions: some View {
    HStack(spacing: 8) {
      ActionTile(
        title: tool.isFavorite ? "Favorited" : "Favorite",
        icon: tool.isFavorite ? "star.fill" : "star",
        tint: tool.isFavorite ? .yellow : nil
      ) {
        Task { await model.toggleFavorite(tool) }
      }

      ActionTile(
        title: tool.isArchived ? "Restore" : "Archive",
        icon: tool.isArchived ? "arrow.uturn.backward" : "archivebox"
      ) {
        Task { await model.toggleArchived(tool) }
      }

      ActionTile(
        title: copied ? "Copied" : "Copy",
        icon: copied ? "checkmark" : "doc.on.doc",
        tint: copied ? .green : nil
      ) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(tool.name, forType: .string)
        copied = true
        Task {
          try? await Task.sleep(for: .seconds(1.5))
          copied = false
        }
      }
    }
  }

  @ViewBuilder
  private var yourHistory: some View {
    let visible = showAllUsage ? usage : Array(usage.prefix(8))
    let runs = usage.reduce(0) { $0 + $1.count }

    DetailSection("Your History") {
      if usage.isEmpty {
        Card {
          Text(model.history == nil ? "Reading your shell history…" : "No runs found in your shell history.")
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      } else {
        VStack(alignment: .leading, spacing: 8) {
          Text("^[\(runs) run](inflect: true) · ^[\(usage.count) distinct command](inflect: true)")
            .font(.caption)
            .foregroundStyle(.secondary)

          ForEach(visible) { item in
            UsageCard(usage: item)
          }

          if usage.count > 8 {
            Button(showAllUsage ? "Show fewer" : "Show all \(usage.count)") {
              showAllUsage.toggle()
            }
            .buttonStyle(.link)
            .font(.callout)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var examples: some View {
    if let examples = tool.examples, !examples.isEmpty {
      DetailSection("Examples") {
        VStack(spacing: 8) {
          ForEach(examples, id: \.self) { example in
            ExampleCard(example: example)
          }
        }
      }
    } else if model.inspectingToolIDs.contains(tool.id) {
      DetailSection("Examples") {
        Card {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Looking for examples…")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }

  @ViewBuilder
  private var helpSection: some View {
    if let help = tool.help, !help.isEmpty {
      DetailSection("Help") {
        CodeBlock(text: help)
      }
    } else if model.inspectingToolIDs.contains(tool.id) {
      DetailSection("Help") {
        Card {
          HStack(spacing: 8) {
            ProgressView()
              .controlSize(.small)
            Text("Loading usage…")
              .foregroundStyle(.secondary)
          }
        }
      }
    }
  }
}

private struct ActionTile: View {
  let title: String
  let icon: String
  var tint: Color? = nil
  let action: () -> Void

  @State private var isHovering = false

  var body: some View {
    Button(action: action) {
      VStack(spacing: 6) {
        Image(systemName: icon)
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(tint ?? .accentColor)
          .frame(height: 18)

        Text(title)
          .font(.caption)
          .foregroundStyle(.primary)
      }
      .frame(maxWidth: .infinity)
      .padding(.vertical, 10)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.quaternary.opacity(isHovering ? 0.8 : 0.4))
      )
      .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
    .buttonStyle(.plain)
    .onHover { isHovering = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovering)
  }
}

private struct UsageCard: View {
  let usage: CommandUsage

  var body: some View {
    Card {
      HStack(alignment: .top, spacing: 10) {
        VStack(alignment: .leading, spacing: 5) {
          Text(usage.command)
            .font(.system(size: 12.5, design: .monospaced))
            .textSelection(.enabled)
            .lineLimit(4)

          HStack(spacing: 6) {
            Text("×\(usage.count)")
              .fontWeight(.semibold)
              .monospacedDigit()

            if let lastUsed = usage.lastUsed {
              Text("·")
              Text(lastUsed, format: .relative(presentation: .named))
            }
          }
          .font(.caption)
          .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        CopyButton(text: usage.command)
      }
    }
  }
}

private struct ExampleCard: View {
  let example: ToolExample

  var body: some View {
    Card {
      VStack(alignment: .leading, spacing: 8) {
        if !example.description.isEmpty {
          Text(example.description)
            .font(.callout)
            .foregroundStyle(.secondary)
        }

        HStack(alignment: .top, spacing: 10) {
          Text(example.command)
            .font(.system(size: 12.5, design: .monospaced))
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)

          CopyButton(text: example.command)
        }
      }
    }
  }
}

private struct DetailSection<Content: View>: View {
  let title: String
  @ViewBuilder let content: Content

  init(_ title: String, @ViewBuilder content: () -> Content) {
    self.title = title
    self.content = content()
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title.uppercased())
        .font(.caption.weight(.semibold))
        .kerning(0.6)
        .foregroundStyle(.secondary)

      content
    }
  }
}

private struct DetailRow: View {
  let label: String
  let value: String

  init(_ label: String, value: String) {
    self.label = label
    self.value = value
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 3) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)

      Text(value)
        .font(.system(.callout, design: .monospaced))
        .textSelection(.enabled)
    }
  }
}

private struct HistoryRow: View {
  let label: String
  let date: Date

  init(_ label: String, date: Date) {
    self.label = label
    self.date = date
  }

  var body: some View {
    HStack {
      Text(label)
        .foregroundStyle(.secondary)
      Spacer()
      Text(date, format: .dateTime.day().month(.abbreviated).year().hour().minute())
        .monospacedDigit()
    }
    .font(.callout)
  }
}

private struct CodeBlock: View {
  let text: String

  var body: some View {
    ScrollView(.horizontal) {
      Text(text)
        .font(.system(size: 12, design: .monospaced))
        .textSelection(.enabled)
        .padding(12)
    }
    .background(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .fill(.quaternary.opacity(0.4))
    )
  }
}
