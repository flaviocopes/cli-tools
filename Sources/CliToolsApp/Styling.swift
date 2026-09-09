import CliToolsCore
import SwiftUI

extension ToolSource {
  var color: Color {
    switch self {
    case .homebrew: .orange
    case .npm: .red
    case .cargo: .brown
    case .python: .blue
    case .local: .green
    case .path: .gray
    }
  }
}

extension CLITool {
  var shortVersion: String? {
    version?
      .split(whereSeparator: \.isNewline)
      .first
      .map { String($0).trimmingCharacters(in: .whitespaces) }
  }

  var subtitle: String {
    if let summary, !summary.isEmpty {
      return summary
    }

    var parts: [String] = []
    if let packageName, packageName != name {
      parts.append(packageName)
    }
    if commandNames.count > 1 {
      parts.append("\(commandNames.count) commands")
    }
    if parts.isEmpty {
      parts.append(path)
    }
    return parts.joined(separator: " · ")
  }
}

struct ToolIcon: View {
  let tool: CLITool
  var size: CGFloat = 30

  var body: some View {
    RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
      .fill(tool.source.color.gradient)
      .frame(width: size, height: size)
      .overlay {
        Text(tool.name.prefix(1).uppercased())
          .font(.system(size: size * 0.5, weight: .bold, design: .monospaced))
          .foregroundStyle(.white)
      }
      .saturation(tool.isAvailable ? 1 : 0)
      .opacity(tool.isAvailable ? 1 : 0.6)
  }
}

struct SourceBadge: View {
  let source: ToolSource
  var isOnSelection = false

  var body: some View {
    Text(source.label)
      .font(.caption2.weight(.semibold))
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .foregroundStyle(isOnSelection ? AnyShapeStyle(.primary) : AnyShapeStyle(source.color))
      .background(
        Capsule().fill(
          isOnSelection ? AnyShapeStyle(.primary.opacity(0.15)) : AnyShapeStyle(source.color.opacity(0.14))
        )
      )
  }
}

struct Card<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    content
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(12)
      .background(
        RoundedRectangle(cornerRadius: 10, style: .continuous)
          .fill(.quaternary.opacity(0.4))
      )
  }
}
