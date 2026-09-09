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
    #expect(tool.installedAt != nil)
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

  @Test
  func discoversGlobalNpmPackageCommands() throws {
    let root = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let package = root.appending(path: "dev/things-cli", directoryHint: .isDirectory)
    let packageLink = root.appending(
      path: ".nvm/versions/node/v24/lib/node_modules/things-cli",
      directoryHint: .isDirectory
    )
    let executable = package.appending(path: "bin/things.js")

    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("#!/usr/bin/env node\n".utf8).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )
    try Data(
      """
      {
        "name": "things-cli",
        "version": "0.1.0",
        "description": "Manage Things from the terminal",
        "bin": { "things": "./bin/things.js" }
      }
      """.utf8
    ).write(to: package.appending(path: "package.json"))
    try FileManager.default.createDirectory(
      at: packageLink.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try FileManager.default.createSymbolicLink(
      at: packageLink,
      withDestinationURL: package
    )
    defer { try? FileManager.default.removeItem(at: root) }

    let tools = ToolDiscovery(
      environment: ["PATH": ""],
      homeDirectory: root,
      includePackageManagers: false
    ).scan()
    let tool = try #require(tools.first { $0.packageName == "things-cli" })

    #expect(tool.name == "things")
    #expect(tool.commandNames == ["things"])
    #expect(tool.source == .npm)
  }
}
