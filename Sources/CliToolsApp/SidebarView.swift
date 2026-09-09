import CliToolsCore
import SwiftUI

struct SidebarView: View {
  @Environment(CatalogViewModel.self) private var model

  var body: some View {
    @Bindable var model = model

    List(selection: $model.section) {
      ForEach(CatalogSection.groups, id: \.self) { group in
        Section {
          ForEach(group) { section in
            SidebarRow(section: section, count: model.count(for: section))
              .tag(section)
          }
        }
      }
    }
    .listStyle(.sidebar)
    .safeAreaInset(edge: .bottom) {
      ScanStatus()
    }
  }
}

private struct SidebarRow: View {
  let section: CatalogSection
  let count: Int

  var body: some View {
    HStack {
      Label {
        Text(section.rawValue)
      } icon: {
        Image(systemName: section.icon)
          .foregroundStyle(section.tint)
      }

      Spacer()

      if count > 0 {
        Text(count, format: .number)
          .font(.callout)
          .monospacedDigit()
          .foregroundStyle(.secondary)
      }
    }
  }
}

private struct ScanStatus: View {
  @Environment(CatalogViewModel.self) private var model

  var body: some View {
    TimelineView(.periodic(from: .now, by: 60)) { context in
      HStack(spacing: 8) {
        if model.isScanning {
          ProgressView()
            .controlSize(.mini)
        } else {
          Image(systemName: "checkmark.circle.fill")
            .foregroundStyle(.green)
        }

        Text(status(at: context.date))
          .lineLimit(1)

        Spacer(minLength: 0)
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .padding(.horizontal, 16)
      .padding(.vertical, 10)
    }
  }

  private func status(at date: Date) -> String {
    if model.isScanning {
      return "Scanning…"
    }
    guard let lastScanAt = model.catalog.lastScanAt else {
      return "Not scanned yet"
    }
    let relative = lastScanAt.formatted(
      .relative(presentation: .named).locale(.current)
    )
    return "Scanned \(relative)"
  }
}
