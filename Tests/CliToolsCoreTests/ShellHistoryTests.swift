import Foundation
import Testing
@testable import CliToolsCore

struct ShellHistoryTests {
  @Test
  func parsesZshExtendedHistory() {
    let entries = ShellHistory.parseZsh(
      Data(
        """
        : 1725000000:0;gh pr status
        : 1725000100:2;echo one \\
        two
        ls -la
        """.utf8
      )
    )

    #expect(entries.count == 3)
    #expect(entries[0].command == "gh pr status")
    #expect(entries[0].date == Date(timeIntervalSince1970: 1_725_000_000))
    #expect(entries[1].command == "echo one \ntwo")
    #expect(entries[2].command == "ls -la")
    #expect(entries[2].date == nil)
  }

  @Test
  func parsesBashAndFishHistory() {
    let bash = ShellHistory.parseBash("#1725000000\ngh repo view\nbat README.md")
    #expect(bash[0].command == "gh repo view")
    #expect(bash[0].date == Date(timeIntervalSince1970: 1_725_000_000))
    #expect(bash[1].date == nil)

    let fish = ShellHistory.parseFish("- cmd: gh pr list\n  when: 1725000000\n- cmd: cd ~")
    #expect(fish.count == 2)
    #expect(fish[0].command == "gh pr list")
    #expect(fish[0].date == Date(timeIntervalSince1970: 1_725_000_000))
  }

  @Test
  func groupsCommandsThatInvokeTheTool() {
    let tool = CLITool(
      id: "homebrew:gh",
      name: "gh",
      path: "/opt/homebrew/bin/gh",
      resolvedPath: "/opt/homebrew/bin/gh",
      source: .homebrew
    )
    let history = ShellHistory(entries: [
      HistoryEntry(command: "gh pr status", date: Date(timeIntervalSince1970: 100)),
      HistoryEntry(command: "git push && gh pr create", date: Date(timeIntervalSince1970: 300)),
      HistoryEntry(command: "gh pr status", date: Date(timeIntervalSince1970: 200)),
      HistoryEntry(command: "sudo /opt/homebrew/bin/gh auth status", date: nil),
      HistoryEntry(command: "echo gh", date: Date(timeIntervalSince1970: 400)),
      HistoryEntry(command: "ghq get cli/cli", date: Date(timeIntervalSince1970: 500))
    ])

    let usage = history.usage(of: tool)

    #expect(usage.map(\.command) == [
      "git push && gh pr create",
      "gh pr status",
      "sudo /opt/homebrew/bin/gh auth status"
    ])
    #expect(usage[1].count == 2)
    #expect(usage[1].lastUsed == Date(timeIntervalSince1970: 200))
  }
}
