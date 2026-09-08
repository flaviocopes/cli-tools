import Foundation
import Testing
@testable import CliToolsCore

struct ToolDiscoveryTests {
  @Test
  func discoversExecutableOnPath() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let bin = root.appending(path: "bin", directoryHint: .isDirectory)
    let executable = bin.appending(path: "valley-tool")

    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let discovery = ToolDiscovery(
      environment: ["PATH": bin.path],
      homeDirectory: root,
      includePackageManagers: false
    )
    let tools = discovery.scan()
    let tool = try #require(tools.first { $0.name == "valley-tool" })

    #expect(tool.path.hasSuffix("/bin/valley-tool"))
    #expect(tool.source == .path)
  }

  @Test
  func keepsUserStateAcrossScans() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let bin = root.appending(path: "bin", directoryHint: .isDirectory)
    let executable = bin.appending(path: "course-cli")
    let catalogURL = root.appending(path: "catalog.json")

    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let repository = CatalogRepository(
      fileURL: catalogURL,
      discovery: ToolDiscovery(
        environment: ["PATH": bin.path],
        homeDirectory: root,
        includePackageManagers: false
      )
    )

    _ = try await repository.refresh()
    _ = try await repository.setFavorite(true, tool: "course-cli")
    let refreshed = try await repository.refresh()
    let tool = try #require(refreshed.tools.first { $0.name == "course-cli" })

    #expect(tool.isFavorite)
  }

  @Test
  func removesMissingToolsWithoutUserState() async throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let bin = root.appending(path: "bin", directoryHint: .isDirectory)
    let executable = bin.appending(path: "temporary-cli")
    let catalogURL = root.appending(path: "catalog.json")

    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    try Data("#!/bin/sh\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let repository = CatalogRepository(
      fileURL: catalogURL,
      discovery: ToolDiscovery(
        environment: ["PATH": bin.path],
        homeDirectory: root,
        includePackageManagers: false
      )
    )

    _ = try await repository.refresh()
    try FileManager.default.removeItem(at: executable)
    let refreshed = try await repository.refresh()

    #expect(!refreshed.tools.contains { $0.name == "temporary-cli" })
  }
}
