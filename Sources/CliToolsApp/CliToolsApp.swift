import CliToolsCore
import SwiftUI

@main
struct CliToolsDesktopApp: App {
  @State private var model = CatalogViewModel()
  @Environment(\.scenePhase) private var scenePhase

  var body: some Scene {
    WindowGroup("CLI Tools") {
      CatalogView()
        .environment(model)
        .frame(minWidth: 960, minHeight: 560)
        .task {
          await model.refresh()

          while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(300))
            await model.refresh()
          }
        }
    }
    .defaultSize(width: 1360, height: 840)
    .windowToolbarStyle(.unified(showsTitle: false))
    .onChange(of: scenePhase) { _, phase in
      if phase == .active {
        Task { await model.refresh() }
      }
    }
  }
}

struct CatalogView: View {
  @Environment(CatalogViewModel.self) private var model

  var body: some View {
    @Bindable var model = model

    NavigationSplitView {
      SidebarView()
        .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 300)
    } detail: {
      ToolListView()
        .inspector(isPresented: $model.isInspectorPresented) {
          if let tool = model.selectedTool {
            ToolDetailView(tool: tool)
              .inspectorColumnWidth(min: 560, ideal: 700, max: 1100)
          }
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
