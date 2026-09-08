import Foundation

public struct ToolInspection: Sendable {
  public var version: String?
  public var help: String?
  public var summary: String?
  public var homepage: URL?

  public init(
    version: String? = nil,
    help: String? = nil,
    summary: String? = nil,
    homepage: URL? = nil
  ) {
    self.version = version
    self.help = help
    self.summary = summary
    self.homepage = homepage
  }
}

public actor ToolInspector {
  public init() {}

  public func inspect(_ tool: CLITool) -> ToolInspection {
    var inspection = ToolInspection(
      version: firstLine(run(tool.resolvedPath, arguments: ["--version"])),
      help: run(tool.resolvedPath, arguments: ["--help"])
    )

    if inspection.help == nil {
      inspection.help = run(tool.resolvedPath, arguments: ["-h"])
    }

    if tool.source == .homebrew, let metadata = homebrewMetadata(for: tool) {
      inspection.summary = metadata.summary
      inspection.homepage = metadata.homepage
      inspection.version = inspection.version ?? metadata.version
    }

    return inspection
  }

  private func run(
    _ executable: String,
    arguments: [String],
    timeout: TimeInterval = 2
  ) -> String? {
    guard FileManager.default.isExecutableFile(atPath: executable) else {
      return nil
    }

    let outputURL = FileManager.default.temporaryDirectory
      .appending(path: "clitools-\(UUID().uuidString).txt")
    FileManager.default.createFile(atPath: outputURL.path, contents: nil)

    guard let output = try? FileHandle(forWritingTo: outputURL) else {
      return nil
    }

    defer {
      try? output.close()
      try? FileManager.default.removeItem(at: outputURL)
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["NO_COLOR": "1", "TERM": "dumb"]
    ) { _, new in new }
    process.standardOutput = output
    process.standardError = output

    let finished = DispatchSemaphore(value: 0)
    process.terminationHandler = { _ in finished.signal() }

    do {
      try process.run()
    } catch {
      return nil
    }

    if finished.wait(timeout: .now() + timeout) == .timedOut {
      process.terminate()
      _ = finished.wait(timeout: .now() + 0.5)
    }

    try? output.synchronize()

    guard
      let data = try? Data(contentsOf: outputURL),
      !data.isEmpty
    else {
      return nil
    }

    let value = String(decoding: data.prefix(50_000), as: UTF8.self)
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return value.isEmpty ? nil : value
  }

  private func firstLine(_ value: String?) -> String? {
    value?
      .split(whereSeparator: \.isNewline)
      .first
      .map(String.init)
  }

  private func homebrewMetadata(for tool: CLITool) -> BrewMetadata? {
    let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    guard let brew = candidates.first(where: FileManager.default.isExecutableFile) else {
      return nil
    }

    let formula = URL(fileURLWithPath: tool.resolvedPath)
      .pathComponents
      .drop { $0 != "Cellar" }
      .dropFirst()
      .first ?? tool.name

    guard
      let output = run(brew, arguments: ["info", "--json=v2", formula], timeout: 5),
      let data = output.data(using: .utf8),
      let info = try? JSONDecoder().decode(BrewInfo.self, from: data),
      let item = info.formulae.first
    else {
      return nil
    }

    return BrewMetadata(
      summary: item.desc,
      homepage: URL(string: item.homepage),
      version: item.versions.stable
    )
  }
}

private struct BrewInfo: Decodable {
  let formulae: [Formula]

  struct Formula: Decodable {
    let desc: String
    let homepage: String
    let versions: Versions
  }

  struct Versions: Decodable {
    let stable: String?
  }
}

private struct BrewMetadata {
  let summary: String
  let homepage: URL?
  let version: String?
}
