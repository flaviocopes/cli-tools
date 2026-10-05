import Foundation
import Testing
@testable import CliToolsCore

struct ToolCapabilitiesTests {
  private let postdeckJSON = """
    {
      "name": "postdeck",
      "version": "1.1.0",
      "summary": "Builds slideshows in the Postdeck app from posts on X, text slides and images.",
      "capabilities": [
        { "description": "Add a post from X as a slide", "command": "postdeck add-post 'Launch' --file post.json" },
        { "description": "Turn a slideshow into a video script" }
      ],
      "changelog": [
        { "version": "1.1.0", "date": "2026-10-05", "changes": ["Added capabilities"] },
        { "version": "1.0.0", "changes": ["First release"] }
      ]
    }
    """

  @Test
  func parsesManifest() throws {
    let manifest = try #require(ToolCapabilities.parse(postdeckJSON))

    #expect(manifest.name == "postdeck")
    #expect(manifest.version == "1.1.0")
    #expect(manifest.capabilities.count == 2)
    #expect(manifest.capabilities[0].command == "postdeck add-post 'Launch' --file post.json")
    #expect(manifest.capabilities[1].command == nil)
    #expect(manifest.changelog.map(\.version) == ["1.1.0", "1.0.0"])
    #expect(manifest.changelog[1].date == nil)
  }

  @Test
  func ignoresTextAroundTheJSON() throws {
    let output = "Opening the library…\n\(postdeckJSON)\n"
    #expect(ToolCapabilities.parse(output)?.name == "postdeck")
  }

  @Test
  func rejectsOutputWithoutCapabilities() {
    #expect(ToolCapabilities.parse(#"{"name": "mindmap", "capabilities": []}"#) == nil)
    #expect(ToolCapabilities.parse(#"{"error": "Unknown command"}"#) == nil)
    #expect(ToolCapabilities.parse("mindmap: unknown command capabilities") == nil)
  }

  @Test
  func detectsAdvertisedCommand() {
    let listed = """
      Commands:
        list          List the slideshows
        capabilities  What postdeck can do, and what changed in each version
      """
    let afterName = """
      Usage:
        mindmap create [--theme <theme>] [file]
        mindmap capabilities [--json]
      """
    let mentioned = """
      Usage: docker run [OPTIONS] IMAGE
        --cap-add list   Add Linux capabilities
      Linux capabilities are dropped by default.
      """

    #expect(ToolCapabilities.isAdvertised(in: listed, commandNames: ["postdeck"]))
    #expect(ToolCapabilities.isAdvertised(in: afterName, commandNames: ["mindmap"]))
    #expect(!ToolCapabilities.isAdvertised(in: afterName, commandNames: ["other"]))
    #expect(!ToolCapabilities.isAdvertised(in: mentioned, commandNames: ["docker"]))
  }

  @Test
  func decodesCatalogWithoutCapabilities() throws {
    let json = """
      {"tools": [{
        "id": "/Users/flavio/.local/bin/postdeck", "name": "postdeck",
        "path": "/Users/flavio/.local/bin/postdeck", "resolvedPath": "/Users/flavio/.local/bin/postdeck",
        "source": "local", "isFavorite": false, "isArchived": false, "isAvailable": true,
        "firstSeenAt": 0, "lastSeenAt": 0
      }]}
      """
    let catalog = try JSONDecoder().decode(Catalog.self, from: Data(json.utf8))
    #expect(catalog.tools.first?.capabilities == nil)
  }

  @Test
  func searchMatchesCapabilities() throws {
    let manifest = try #require(ToolCapabilities.parse(postdeckJSON))
    let catalog = Catalog(tools: [
      CLITool(
        id: "local:postdeck",
        name: "postdeck",
        path: "/Users/flavio/.local/bin/postdeck",
        resolvedPath: "/Users/flavio/.local/bin/postdeck",
        source: .local,
        capabilities: manifest
      ),
      CLITool(id: "homebrew:gh", name: "gh", path: "/opt/homebrew/bin/gh", resolvedPath: "/opt/homebrew/bin/gh", source: .homebrew)
    ])

    #expect(catalog.search("slide").map(\.name) == ["postdeck"])
    #expect(catalog.search("video script").map(\.name) == ["postdeck"])
  }

  @Test
  func asksTheToolAndSavesTheAnswer() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let bin = root.appending(path: "bin", directoryHint: .isDirectory)
    let executable = bin.appending(path: "postdeck")
    let manifestFile = root.appending(path: "manifest.json")

    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try Data(postdeckJSON.utf8).write(to: manifestFile)
    let script = """
      #!/bin/sh
      if [ "$1" = "capabilities" ] && [ "$2" = "--json" ]; then
        echo "warming up" >&2
        cat '\(manifestFile.path)'
      fi
      """
    try Data(script.utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    defer { try? FileManager.default.removeItem(at: root) }

    let repository = CatalogRepository(
      fileURL: root.appending(path: "catalog.json"),
      discovery: ToolDiscovery(
        environment: ["PATH": bin.path],
        homeDirectory: root,
        includePackageManagers: false
      )
    )
    let tool = try #require(try await repository.refresh().tools.first { $0.name == "postdeck" })

    let manifest = try #require(await ToolInspector().capabilities(of: tool))
    let catalog = try await repository.updateCapabilities([tool.id: manifest])
    let saved = try #require(catalog.tools.first { $0.id == tool.id })

    #expect(saved.capabilities?.capabilities.count == 2)
    #expect(saved.summary == manifest.summary)

    let refreshed = try await repository.refreshCapabilities()
    #expect(refreshed.map(\.name) == ["postdeck"])
    #expect(refreshed.first?.capabilities?.version == "1.1.0")
  }
}
