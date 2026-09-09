import Foundation
import Testing
@testable import CliToolsCore

struct AgentHistoryTests {
  private func lines(_ text: String) -> [Data] {
    text.split(separator: "\n").map { Data($0.utf8) }
  }

  private let gh = CLITool(
    id: "homebrew:gh",
    name: "gh",
    path: "/opt/homebrew/bin/gh",
    resolvedPath: "/opt/homebrew/bin/gh",
    source: .homebrew
  )

  @Test
  func parsesCursorTranscripts() throws {
    let entries = AgentHistory.parseCursor(lines("""
      {"role":"user","message":{"content":[{"type":"text","text":"<timestamp>Wednesday, Sep 9, 2026, 11:19 AM (UTC+2)</timestamp>\\n<user_query>hi</user_query>"}]}}
      {"role":"assistant","message":{"content":[{"type":"tool_use","name":"Shell","input":{"command":"gh pr status","working_directory":"/tmp"}}]}}
      {"role":"user","message":{"content":[{"type":"tool_result","content":"ok"}]}}
      {"role":"assistant","message":{"content":[{"type":"tool_use","name":"Read","input":{"path":"gh"}}]}}
      {"role":"assistant","message":{"content":[{"type":"tool_use","name":"Shell","input":{"command":"git log"}}]}}
      """))

    #expect(entries.map(\.command) == ["gh pr status", "git log"])
    #expect(entries.allSatisfy { $0.agent == .cursor })

    let expected = try Date("2026-09-09T09:19:00Z", strategy: .iso8601)
    #expect(entries[0].date == expected)
  }

  @Test
  func parsesCodexSessionsAcrossToolNames() throws {
    let entries = AgentHistory.parseCodex(lines("""
      {"timestamp":"2026-01-21T11:00:25.377Z","type":"response_item","payload":{"type":"function_call","name":"shell","arguments":"{\\"command\\":[\\"bash\\",\\"-lc\\",\\"ls -la\\"],\\"workdir\\":\\"/tmp\\"}","call_id":"a"}}
      {"timestamp":"2026-01-15T13:18:00.000Z","type":"response_item","payload":{"type":"function_call","name":"shell_command","arguments":"{\\"command\\":\\"gh pr list\\",\\"workdir\\":\\"/tmp\\"}","call_id":"b"}}
      {"timestamp":"2026-06-12T10:17:59.507Z","type":"response_item","payload":{"type":"function_call","name":"exec_command","arguments":"{\\"cmd\\":\\"gh pr view 1\\",\\"yield_time_ms\\":1000}","call_id":"c"}}
      {"timestamp":"2026-06-12T10:18:00.000Z","type":"response_item","payload":{"type":"function_call","name":"update_plan","arguments":"{}","call_id":"d"}}
      {"timestamp":"2026-06-12T10:18:01.000Z","type":"response_item","payload":{"type":"function_call_output","call_id":"c","output":"gh"}}
      """))

    #expect(entries.map(\.command) == ["ls -la", "gh pr list", "gh pr view 1"])
    #expect(entries.allSatisfy { $0.agent == .codex })
    #expect(entries[2].date == (try Date("2026-06-12T10:17:59.507Z", strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))))
  }

  @Test
  func parsesClaudeCodeSessions() throws {
    let entries = AgentHistory.parseClaude(lines("""
      {"type":"user","timestamp":"2026-09-05T17:04:30.000Z","message":{"role":"user","content":"run it"}}
      {"type":"assistant","timestamp":"2026-09-05T17:04:34.626Z","cwd":"/tmp","message":{"role":"assistant","content":[{"type":"text","text":"Sure."},{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"gh auth status","description":"check"}}]}}
      """))

    #expect(entries.count == 1)
    #expect(entries[0].command == "gh auth status")
    #expect(entries[0].agent == .claude)
    #expect(entries[0].date == (try Date("2026-09-05T17:04:34.626Z", strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true))))
  }

  @Test
  func unwrapsShellArgv() {
    #expect(AgentHistory.argvCommand(["bash", "-lc", "gh pr list"]) == "gh pr list")
    #expect(AgentHistory.argvCommand(["zsh", "-c", "ls"]) == "ls")
    #expect(AgentHistory.argvCommand(["gh", "pr", "list"]) == "gh pr list")
    #expect(AgentHistory.argvCommand([]) == nil)
  }

  @Test
  func groupsUsageAndRecordsWhichAgentsRanIt() {
    let history = AgentHistory(entries: [
      HistoryEntry(command: "gh pr status", date: Date(timeIntervalSince1970: 100), agent: .cursor),
      HistoryEntry(command: "gh pr status", date: Date(timeIntervalSince1970: 300), agent: .codex),
      HistoryEntry(command: "gh pr status", date: Date(timeIntervalSince1970: 200), agent: .cursor),
      HistoryEntry(command: "git push && gh pr create", date: Date(timeIntervalSince1970: 50), agent: .claude),
      HistoryEntry(command: "echo gh", date: Date(timeIntervalSince1970: 400), agent: .cursor)
    ])

    let usage = history.usage(of: gh)

    #expect(usage.map(\.command) == ["gh pr status", "git push && gh pr create"])
    #expect(usage[0].count == 3)
    #expect(usage[0].agents == [.codex, .cursor])
    #expect(usage[0].lastUsed == Date(timeIntervalSince1970: 300))
    #expect(usage[1].agents == [.claude])
  }

  @Test
  func streamsLinesAcrossChunkBoundaries() throws {
    let url = FileManager.default.temporaryDirectory.appending(path: "clitools-lines-\(UUID().uuidString).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }

    let long = String(repeating: "x", count: (1 << 20) + 17)
    try "first\n\(long)\nlast".write(to: url, atomically: true, encoding: .utf8)

    let read = Array(FileLines(url: url)).map { String(decoding: $0, as: UTF8.self) }
    #expect(read.count == 3)
    #expect(read[0] == "first")
    #expect(read[1] == long)
    #expect(read[2] == "last")
  }
}
