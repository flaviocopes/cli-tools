import Foundation
import Testing
@testable import CliToolsCore

struct CatalogQueriesTests {
  private func tool(
    _ name: String,
    id: String? = nil,
    source: ToolSource = .homebrew,
    package: String? = nil,
    commands: [String]? = nil,
    summary: String? = nil
  ) -> CLITool {
    CLITool(
      id: id ?? "\(source.rawValue):\(package ?? name)",
      name: name,
      path: "/opt/homebrew/bin/\(name)",
      resolvedPath: "/opt/homebrew/bin/\(name)",
      source: source,
      summary: summary,
      packageName: package,
      commands: commands
    )
  }

  private var catalog: Catalog {
    Catalog(tools: [
      tool("gh", summary: "GitHub command-line tool"),
      tool("ghq"),
      tool("ripgrep", commands: ["rg"], summary: "Search tool like grep"),
      tool("postgresql", package: "postgresql", commands: ["psql", "pg_dump"]),
      tool("vercel", source: .npm),
      tool("vercel", source: .homebrew),
      tool("vps", source: .npm, summary: "Poll DigitalOcean droplets over SSH")
    ])
  }

  @Test
  func findsByNameCommandPackageAndID() throws {
    #expect(try catalog.tool(matching: "gh").name == "gh")
    #expect(try catalog.tool(matching: "rg").name == "ripgrep")
    #expect(try catalog.tool(matching: "psql").name == "postgresql")
    #expect(try catalog.tool(matching: "npm:vercel").source == .npm)
    #expect(try catalog.tool(matching: "GH").name == "gh")
  }

  @Test
  func reportsAmbiguousNamesWithCandidates() {
    guard case .ambiguous(let candidates) = catalog.lookup("vercel") else {
      Issue.record("Expected an ambiguous lookup")
      return
    }

    #expect(candidates.count == 2)
    #expect(Set(candidates.map(\.id)) == ["npm:vercel", "homebrew:vercel"])

    let error = CatalogError.ambiguousToolName("vercel", candidates: candidates)
    #expect(error.localizedDescription.contains("npm:vercel"))
  }

  @Test
  func suggestsCloseNamesWhenNothingMatches() {
    guard case .notFound(let suggestions) = catalog.lookup("gj") else {
      Issue.record("Expected a not-found lookup")
      return
    }

    #expect(suggestions.map(\.name).contains("gh"))
    #expect(!suggestions.map(\.name).contains("postgresql"))

    let error = CatalogError.toolNotFound("gj", suggestions: suggestions)
    #expect(error.localizedDescription.contains("Did you mean"))
  }

  @Test
  func searchesNamesCommandsAndSummaries() {
    #expect(catalog.search("grep").map(\.name) == ["ripgrep"])
    #expect(catalog.search("pg_dump").map(\.name) == ["postgresql"])
    #expect(catalog.search("github").map(\.name) == ["gh"])
    #expect(catalog.search("search grep").map(\.name) == ["ripgrep"])
    #expect(catalog.search("digital").map(\.name) == ["vps"])
    #expect(!catalog.search("git").map(\.name).contains("vps"))
    #expect(catalog.search("nothing-here").isEmpty)
  }

  @Test
  func countsRunsPerTool() {
    let tools = [tool("gh"), tool("ripgrep", commands: ["rg"])]
    let history = ShellHistory(entries: [
      HistoryEntry(command: "gh pr status"),
      HistoryEntry(command: "rg TODO | gh gist create"),
      HistoryEntry(command: "git status")
    ])

    let counts = history.runCounts(for: tools)

    #expect(counts["homebrew:gh"] == 2)
    #expect(counts["homebrew:ripgrep"] == 1)
  }

  @Test
  func scanReportsAddedAndRemovedTools() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let bin = root.appending(path: "bin", directoryHint: .isDirectory)
    let first = bin.appending(path: "first-cli")
    let second = bin.appending(path: "second-cli")

    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    for executable in [first, second] {
      try Data("#!/bin/sh\n".utf8).write(to: executable)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: executable.path
      )
    }
    defer { try? FileManager.default.removeItem(at: root) }

    let repository = CatalogRepository(
      fileURL: root.appending(path: "catalog.json"),
      discovery: ToolDiscovery(
        environment: ["PATH": bin.path],
        homeDirectory: root,
        includePackageManagers: false
      )
    )

    let initial = try await repository.scan()
    #expect(initial.added.isEmpty)
    #expect(initial.removed.isEmpty)

    try FileManager.default.removeItem(at: second)
    let third = bin.appending(path: "third-cli")
    try Data("#!/bin/sh\n".utf8).write(to: third)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: third.path)

    let summary = try await repository.scan()
    #expect(summary.added.map(\.name) == ["third-cli"])
    #expect(summary.removed.map(\.name) == ["second-cli"])
  }
}
