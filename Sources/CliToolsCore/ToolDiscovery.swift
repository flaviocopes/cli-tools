import Foundation

public struct ToolDiscovery: Sendable {
  private let environment: [String: String]
  private let homeDirectory: URL

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
  ) {
    self.environment = environment
    self.homeDirectory = homeDirectory
  }

  public func scan(at date: Date = .now) -> [CLITool] {
    let fileManager = FileManager.default
    var names = Set<String>()
    var tools: [CLITool] = []

    for directory in candidateDirectories() where !isSystemDirectory(directory) {
      guard let entries = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      ) else {
        continue
      }

      for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let name = entry.lastPathComponent

        guard
          !names.contains(name),
          fileManager.isExecutableFile(atPath: entry.path),
          isFileOrLink(entry)
        else {
          continue
        }

        let resolved = entry.resolvingSymlinksInPath()
        names.insert(name)
        tools.append(
          CLITool(
            id: entry.standardizedFileURL.path,
            name: name,
            path: entry.path,
            resolvedPath: resolved.path,
            source: source(for: entry, resolved: resolved),
            firstSeenAt: date,
            lastSeenAt: date
          )
        )
      }
    }

    return tools.sorted {
      $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
  }

  private func candidateDirectories() -> [URL] {
    let pathDirectories = environment["PATH", default: ""]
      .split(separator: ":")
      .map { URL(fileURLWithPath: String($0), isDirectory: true) }

    let knownDirectories = [
      URL(fileURLWithPath: "/opt/homebrew/bin", isDirectory: true),
      URL(fileURLWithPath: "/opt/homebrew/sbin", isDirectory: true),
      URL(fileURLWithPath: "/usr/local/bin", isDirectory: true),
      URL(fileURLWithPath: "/usr/local/sbin", isDirectory: true),
      homeDirectory.appending(path: ".cargo/bin", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".local/bin", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".local/share/pnpm", directoryHint: .isDirectory),
      homeDirectory.appending(path: "Library/pnpm", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".bun/bin", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".deno/bin", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".volta/bin", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".asdf/shims", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".pyenv/shims", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".local/share/mise/shims", directoryHint: .isDirectory),
      homeDirectory.appending(path: ".orbstack/bin", directoryHint: .isDirectory)
    ]

    let versionedDirectories =
      childDirectories(
        in: homeDirectory.appending(path: ".nvm/versions/node", directoryHint: .isDirectory),
        appending: "bin"
      )
      + childDirectories(
        in: homeDirectory.appending(path: "Library/Python", directoryHint: .isDirectory),
        appending: "bin"
      )

    var seen = Set<String>()
    return (pathDirectories + knownDirectories + versionedDirectories).filter {
      seen.insert($0.standardizedFileURL.path).inserted
    }
  }

  private func childDirectories(in parent: URL, appending component: String) -> [URL] {
    guard let children = try? FileManager.default.contentsOfDirectory(
      at: parent,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return children.compactMap { child in
      guard
        let values = try? child.resourceValues(forKeys: [.isDirectoryKey]),
        values.isDirectory == true
      else {
        return nil
      }

      return child.appending(path: component, directoryHint: .isDirectory)
    }
  }

  private func isSystemDirectory(_ directory: URL) -> Bool {
    let path = directory.standardizedFileURL.path
    let systemDirectories = [
      "/bin",
      "/sbin",
      "/usr/bin",
      "/usr/sbin"
    ]

    return systemDirectories.contains(path)
      || path.hasPrefix("/System/")
      || path.hasPrefix("/Library/Apple/")
  }

  private func isFileOrLink(_ url: URL) -> Bool {
    guard let values = try? url.resourceValues(
      forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
    ) else {
      return false
    }

    return values.isRegularFile == true || values.isSymbolicLink == true
  }

  private func source(for url: URL, resolved: URL) -> ToolSource {
    let path = "\(url.path) \(resolved.path)".lowercased()

    if path.contains("homebrew") || path.contains("/cellar/") {
      return .homebrew
    }

    if path.contains("/node_modules/") || path.contains("/.npm/")
      || path.contains("/.nvm/") || path.contains("/pnpm/")
      || path.contains("/.bun/") || path.contains("/.deno/")
      || path.contains("/.volta/") {
      return .npm
    }

    if path.contains("/.cargo/") {
      return .cargo
    }

    if path.contains("/python") || path.contains("/pipx/")
      || path.contains("/site-packages/") || path.contains("/.pyenv/") {
      return .python
    }

    let resolvedHome = homeDirectory.resolvingSymlinksInPath().path
    if url.path.hasPrefix(resolvedHome) {
      return .local
    }

    return .path
  }
}
