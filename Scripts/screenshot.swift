import AppKit
import CliToolsCore
import SwiftUI

@main enum Screenshot {
  @MainActor static func main() {
    let output = URL(filePath: CommandLine.arguments[1])
    try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let model = CatalogViewModel()
    let names = ["gh", "ripgrep", "jq", "ffmpeg", "wrangler", "git", "bun", "node", "python", "tart", "tree", "wget"]
    model.catalog = Catalog(tools: names.enumerated().map { index, name in
      CLITool(id: name, name: name, path: "/opt/homebrew/bin/\(name)", resolvedPath: "/opt/homebrew/bin/\(name)", source: index == 4 ? .npm : .homebrew, isFavorite: index < 3, summary: name == "gh" ? "Work with GitHub repositories, issues, pull requests and releases from your terminal." : "A command line tool for your Mac.", version: "1.0.0", help: "Usage: \(name) [command]", examples: [ToolExample(description: "Show help", command: "\(name) --help")], installedAt: .now.addingTimeInterval(-Double(index) * 86400))
    }, lastScanAt: .now)
    let host = NSHostingView(rootView: CatalogView().environment(model).frame(width: 1360, height: 840))
    host.sceneBridgingOptions = [.toolbars]
    let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 1360, height: 840), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
    window.title = "CLI Tools Cabinet"
    window.titleVisibility = .hidden
    window.contentView = host
    window.center()
    _ = NotificationCenter.default.addObserver(forName: NSApplication.didFinishLaunchingNotification, object: nil, queue: .main) { _ in
      MainActor.assumeIsolated {
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        Task {
          for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            NSApp.appearance = NSAppearance(named: appearance)
            try? await Task.sleep(for: .seconds(1))
            let view = window.contentView!.superview!
            let representation = view.bitmapImageRepForCachingDisplay(in: view.bounds)!
            view.cacheDisplay(in: view.bounds, to: representation)
            try! representation.representation(using: .png, properties: [:])!.write(to: output.appending(path: "screenshot-\(name).png"))
          }
          NSApp.terminate(nil)
        }
      }
    }
    app.run()
  }
}
