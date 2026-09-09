import Foundation

public struct ToolDiscovery: Sendable {
  private let environment: [String: String]
  private let homeDirectory: URL
  private let includePackageManagers: Bool

  public init(
    environment: [String: String] = ProcessInfo.processInfo.environment,
    homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
    includePackageManagers: Bool = true
  ) {
    self.environment = environment
    self.homeDirectory = homeDirectory
    self.includePackageManagers = includePackageManagers
  }

  public func scan(at date: Date = .now) -> [CLITool] {
    let fileManager = FileManager.default
    let homebrew = homebrewInventory()
    let formulaByCellarFolder = homebrew.formulae.reduce(into: [String: String]()) {
      let folder = $1.split(separator: "/").last.map(String.init) ?? $1
      $0[folder] = $1
    }
    let cargoPackages = cargoInventory()
    var homebrewCommands: [String: [URL]] = [:]
    var cargoCommands: [String: [URL]] = [:]
    var applicationCommands: [String: [URL]] = [:]
    var runtimeCommands: [String: [URL]] = [:]
    var names = Set<String>()
    var tools = npmTools(at: date)
    names.formUnion(tools.flatMap(\.commandNames))

    for directory in candidateDirectories()
    where !isSystemDirectory(directory) && !isInternalDirectory(directory) {
      guard let entries = try? fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
        options: [.skipsHiddenFiles]
      ) else {
        continue
      }

      for entry in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
        let name = entry.lastPathComponent
        let resolved = entry.resolvingSymlinksInPath()

        if let application = applicationName(in: resolved.path) {
          applicationCommands[application, default: []].append(entry)
          continue
        }

        if let folder = cellarFolder(in: resolved.path) {
          if let formula = formulaByCellarFolder[folder] {
            homebrewCommands[formula, default: []].append(entry)
          }
          continue
        }

        if directory.path.hasSuffix("/.cargo/bin") {
          if let package = cargoPackages[name] {
            cargoCommands[package, default: []].append(entry)
          } else if resolved.lastPathComponent == "rustup" {
            cargoCommands["rustup", default: []].append(entry)
          }
          continue
        }

        if resolved.path.contains("/Python.framework/") {
          runtimeCommands["python", default: []].append(entry)
          continue
        }

        if isHomebrewDirectory(directory) {
          if homebrew.casks.contains(name) {
            homebrewCommands[name, default: []].append(entry)
          }
          continue
        }

        guard
          !names.contains(name),
          fileManager.isExecutableFile(atPath: entry.path),
          isFileOrLink(entry)
        else {
          continue
        }

        names.insert(name)
        tools.append(
          CLITool(
            id: entry.standardizedFileURL.path,
            name: name,
            path: entry.path,
            resolvedPath: resolved.path,
            source: source(for: entry, resolved: resolved),
            installedAt: installationDate(for: entry, resolved: resolved),
            firstSeenAt: date,
            lastSeenAt: date
          )
        )
      }
    }

    tools.append(contentsOf: homebrewCommands.map { package, entries in
      return packagedTool(
        idPrefix: "homebrew",
        package: package,
        entries: entries,
        source: .homebrew,
        installedAt: homebrew.installedAt[package],
        date: date
      )
    })
    tools.append(contentsOf: cargoCommands.map { package, entries in
      packagedTool(
        idPrefix: "cargo",
        package: package,
        entries: entries,
        source: .cargo,
        date: date
      )
    })
    tools.append(contentsOf: applicationCommands.compactMap { application, entries in
      guard entries.allSatisfy({ !names.contains($0.lastPathComponent) }) else {
        return nil
      }

      return packagedTool(
        idPrefix: "application",
        package: application,
        entries: entries,
        source: .local,
        date: date
      )
    })
    tools.append(contentsOf: runtimeCommands.map { runtime, entries in
      packagedTool(
        idPrefix: "runtime",
        package: runtime,
        entries: entries,
        source: .local,
        date: date
      )
    })

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

    let versionedDirectories = childDirectories(
      in: homeDirectory.appending(path: ".nvm/versions/node", directoryHint: .isDirectory),
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

  private func isInternalDirectory(_ directory: URL) -> Bool {
    let path = directory.standardizedFileURL.path
    return path.contains(".app/Contents/")
      || path.contains("/node_modules/")
      || path.contains("/Library/Application Support/")
  }

  private func isHomebrewDirectory(_ directory: URL) -> Bool {
    let path = directory.standardizedFileURL.path
    return path == "/opt/homebrew/bin"
      || path == "/opt/homebrew/sbin"
      || path == "/usr/local/Homebrew/bin"
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

  private func cellarFolder(in path: String) -> String? {
    let components = URL(fileURLWithPath: path).pathComponents
    guard
      let cellarIndex = components.firstIndex(of: "Cellar"),
      components.indices.contains(cellarIndex + 1)
    else {
      return nil
    }

    return components[cellarIndex + 1]
  }

  private func packagedTool(
    idPrefix: String,
    package: String,
    entries: [URL],
    source: ToolSource,
    commandNames: [String]? = nil,
    installedAt: Date? = nil,
    date: Date
  ) -> CLITool {
    let sortedEntries = entries.sorted { $0.lastPathComponent < $1.lastPathComponent }
    let shortPackage = package.split(separator: "/").last.map(String.init) ?? package
    let baseName = shortPackage.split(separator: "@").first.map(String.init) ?? shortPackage
    let preferredNames = [baseName, shortPackage, preferredCommand(for: baseName)]
    let primary = preferredNames
      .compactMap { preferred in
        sortedEntries.first { $0.lastPathComponent == preferred }
      }
      .first
      ?? sortedEntries.first!
    let commands = commandNames
      ?? Array(Set(sortedEntries.map(\.lastPathComponent))).sorted()
    let displayName = commands.count == 1 ? commands[0] : shortPackage

    return CLITool(
      id: "\(idPrefix):\(package)",
      name: displayName,
      path: primary.path,
      resolvedPath: primary.resolvingSymlinksInPath().path,
      source: source,
      packageName: package,
      commands: commands,
      installedAt: installedAt ?? installationDate(
        for: primary,
        resolved: primary.resolvingSymlinksInPath()
      ),
      firstSeenAt: date,
      lastSeenAt: date
    )
  }

  private func preferredCommand(for package: String) -> String {
    switch package {
    case "postgresql": "psql"
    case "coreutils": "gdate"
    case "git-delta": "delta"
    case "stripe": "stripe"
    default: package
    }
  }

  private func homebrewInventory() -> HomebrewInventory {
    guard includePackageManagers else {
      return HomebrewInventory()
    }

    guard let brew = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
      .first(where: FileManager.default.isExecutableFile)
    else {
      return HomebrewInventory()
    }

    let prefix = URL(fileURLWithPath: brew)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
    var inventory = homebrewFormulaInventory(prefix: prefix)
    let output = commandOutput(
      executable: brew,
      arguments: ["info", "--json=v2", "--installed"]
    )

    guard
      let data = output.data(using: .utf8),
      let info = try? JSONDecoder().decode(HomebrewInfo.self, from: data)
    else {
      return inventory
    }

    for cask in info.casks {
      inventory.casks.insert(cask.token)
      if let timestamp = cask.installedTime {
        inventory.installedAt[cask.token] = Date(timeIntervalSince1970: timestamp)
      }
    }

    return inventory
  }

  private func homebrewFormulaInventory(prefix: URL) -> HomebrewInventory {
    let cellar = prefix.appending(path: "Cellar", directoryHint: .isDirectory)
    var inventory = HomebrewInventory()

    for formulaDirectory in contentsOfDirectories(in: cellar) {
      for versionDirectory in contentsOfDirectories(in: formulaDirectory) {
        let receiptURL = versionDirectory.appending(path: "INSTALL_RECEIPT.json")
        guard
          let data = try? Data(contentsOf: receiptURL),
          let receipt = try? JSONDecoder().decode(HomebrewReceipt.self, from: data),
          receipt.installedOnRequest
        else {
          continue
        }

        let formula = formulaDirectory.lastPathComponent
        let tap = receipt.source?.tap
        let package = if let tap, tap != "homebrew/core" {
          "\(tap)/\(formula)"
        } else {
          formula
        }

        inventory.formulae.insert(package)

        if let timestamp = receipt.time {
          let installedAt = Date(timeIntervalSince1970: timestamp)
          inventory.installedAt[package] = max(
            inventory.installedAt[package] ?? .distantPast,
            installedAt
          )
        }
      }
    }

    return inventory
  }

  private func cargoInventory() -> [String: String] {
    guard includePackageManagers else {
      return [:]
    }

    let cargo = homeDirectory.appending(path: ".cargo/bin/cargo").path
    let output = commandOutput(executable: cargo, arguments: ["install", "--list"])
    var currentPackage: String?
    var packages: [String: String] = [:]

    for line in output.split(whereSeparator: \.isNewline) {
      if line.first?.isWhitespace == false {
        currentPackage = line.split(separator: " ").first.map(String.init)
      } else if let currentPackage {
        let command = line.trimmingCharacters(in: .whitespaces)
        if !command.isEmpty {
          packages[command] = currentPackage
        }
      }
    }

    return packages
  }

  private func npmTools(at date: Date) -> [CLITool] {
    npmRoots().flatMap { root in
      npmPackageDirectories(in: root).compactMap { packageDirectory in
        npmTool(in: packageDirectory, root: root, date: date)
      }
    }
  }

  private func npmRoots() -> [URL] {
    var roots: [URL] = []

    if includePackageManagers {
      roots.append(URL(fileURLWithPath: "/opt/homebrew/lib/node_modules"))
      roots.append(URL(fileURLWithPath: "/usr/local/lib/node_modules"))
    }

    let nvmRoot = homeDirectory.appending(
      path: ".nvm/versions/node",
      directoryHint: .isDirectory
    )
    roots.append(contentsOf:
      contentsOfDirectories(in: nvmRoot).map {
        $0.appending(path: "lib/node_modules", directoryHint: .isDirectory)
      }
    )

    var seen = Set<String>()
    return roots.filter {
      seen.insert($0.standardizedFileURL.path).inserted
    }
  }

  private func npmPackageDirectories(in root: URL) -> [URL] {
    contentsOfDirectories(in: root).flatMap { directory in
      if directory.lastPathComponent.hasPrefix("@") {
        return contentsOfDirectories(in: directory)
      }

      return [directory]
    }
  }

  private func contentsOfDirectories(in parent: URL) -> [URL] {
    guard let entries = try? FileManager.default.contentsOfDirectory(
      at: parent,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else {
      return []
    }

    return entries.filter {
      if (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
        return true
      }

      let resolved = $0.resolvingSymlinksInPath()
      return (try? resolved.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
    }
  }

  private func npmTool(
    in packageDirectory: URL,
    root: URL,
    date: Date
  ) -> CLITool? {
    let manifestURL = packageDirectory.appending(path: "package.json")
    guard
      let data = try? Data(contentsOf: manifestURL),
      let manifest = try? JSONDecoder().decode(NpmPackageManifest.self, from: data),
      !["npm", "corepack"].contains(manifest.name),
      var bins = manifest.bin?.commands
    else {
      return nil
    }

    if let relativePath = bins.removeValue(forKey: "") {
      let command = manifest.name.split(separator: "/").last.map(String.init)
        ?? manifest.name
      bins[command] = relativePath
    }

    guard !bins.isEmpty else {
      return nil
    }

    let prefix = root.deletingLastPathComponent().deletingLastPathComponent()
    let entries = bins.compactMap { command, relativePath -> URL? in
      let linked = prefix.appending(path: "bin/\(command)")
      if FileManager.default.isExecutableFile(atPath: linked.path) {
        return linked
      }

      let direct = packageDirectory.appending(path: relativePath)
      return FileManager.default.isExecutableFile(atPath: direct.path) ? direct : nil
    }

    guard !entries.isEmpty else {
      return nil
    }

    var tool = packagedTool(
      idPrefix: "npm:\(root.standardizedFileURL.path)",
      package: manifest.name,
      entries: entries,
      source: .npm,
      commandNames: bins.keys.sorted(),
      installedAt: installationDate(for: packageDirectory, resolved: packageDirectory),
      date: date
    )
    tool.summary = manifest.description
    tool.version = manifest.version
    tool.homepage = manifest.homepage.flatMap(URL.init(string:))
    return tool
  }

  private func applicationName(in path: String) -> String? {
    URL(fileURLWithPath: path).pathComponents
      .first { $0.hasSuffix(".app") }?
      .dropLast(4)
      .description
  }

  private func installationDate(for url: URL, resolved: URL) -> Date? {
    let keys: Set<URLResourceKey> = [.creationDateKey, .contentModificationDateKey]
    let resolvedValues = try? resolved.resourceValues(forKeys: keys)
    let linkValues = try? url.resourceValues(forKeys: keys)

    return resolvedValues?.creationDate
      ?? linkValues?.creationDate
      ?? resolvedValues?.contentModificationDate
      ?? linkValues?.contentModificationDate
  }

  private func commandOutput(executable: String, arguments: [String]) -> String {
    let outputURL = FileManager.default.temporaryDirectory
      .appending(path: "clitools-inventory-\(UUID().uuidString).json")
    _ = FileManager.default.createFile(atPath: outputURL.path, contents: nil)

    guard let output = try? FileHandle(forWritingTo: outputURL) else {
      return ""
    }

    defer {
      try? output.close()
      try? FileManager.default.removeItem(at: outputURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = environment
    process.standardOutput = output
    process.standardError = FileHandle.nullDevice

    do {
      try process.run()
      process.waitUntilExit()
      try output.synchronize()
      let data = try Data(contentsOf: outputURL)
      return String(decoding: data, as: UTF8.self)
    } catch {
      return ""
    }
  }
}

private struct HomebrewInventory {
  var formulae = Set<String>()
  var casks = Set<String>()
  var installedAt: [String: Date] = [:]
}

private struct HomebrewInfo: Decodable {
  let formulae: [Formula]
  let casks: [Cask]

  struct Formula: Decodable {
    let fullName: String
    let installed: [Installation]

    enum CodingKeys: String, CodingKey {
      case fullName = "full_name"
      case installed
    }
  }

  struct Installation: Decodable {
    let time: TimeInterval?
    let installedOnRequest: Bool

    enum CodingKeys: String, CodingKey {
      case time
      case installedOnRequest = "installed_on_request"
    }
  }

  struct Cask: Decodable {
    let token: String
    let installedTime: TimeInterval?

    enum CodingKeys: String, CodingKey {
      case token
      case installedTime = "installed_time"
    }
  }
}

private struct HomebrewReceipt: Decodable {
  let installedOnRequest: Bool
  let time: TimeInterval?
  let source: Source?

  enum CodingKeys: String, CodingKey {
    case installedOnRequest = "installed_on_request"
    case time
    case source
  }

  struct Source: Decodable {
    let tap: String?
  }
}

private struct NpmPackageManifest: Decodable {
  let name: String
  let version: String?
  let description: String?
  let homepage: String?
  let bin: NpmBin?
}

private struct NpmBin: Decodable {
  let commands: [String: String]

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()

    if let path = try? container.decode(String.self) {
      commands = ["": path]
    } else {
      commands = try container.decode([String: String].self)
    }
  }
}
