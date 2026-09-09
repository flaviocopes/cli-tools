import Foundation
import Testing
@testable import CliToolsCore

struct ToolExamplesTests {
  @Test
  func parsesTLDRPage() {
    let page = TLDRPage.parse(
      """
      # gh

      > Work seamlessly with GitHub.
      > Some subcommands such as `gh config` have their own usage documentation.
      > More information: <https://cli.github.com/manual/gh>.

      - Clone a GitHub repository locally:

      `gh repo clone {{owner}}/{{repository}}`

      - Create a new issue:

      `gh issue create`
      """
    )

    #expect(page.summary == "Work seamlessly with GitHub.")
    #expect(page.homepage == URL(string: "https://cli.github.com/manual/gh"))
    #expect(
      page.examples == [
        ToolExample(description: "Clone a GitHub repository locally", command: "gh repo clone owner/repository"),
        ToolExample(description: "Create a new issue", command: "gh issue create")
      ]
    )
  }

  @Test
  func parsesExamplesSectionFromHelp() {
    let examples = ToolExample.parse(
      help: """
        Usage: bat [OPTIONS] [FILE]...

        Examples:
          # Show a file with line numbers
          $ bat --number src/main.rs
          bat --paging=never README.md  # Skip the pager

        Options:
          -A, --show-all
        """,
      toolName: "bat"
    )

    #expect(
      examples == [
        ToolExample(description: "Show a file with line numbers", command: "bat --number src/main.rs"),
        ToolExample(description: "Skip the pager", command: "bat --paging=never README.md")
      ]
    )
  }

  @Test
  func ignoresHelpWithoutExamples() {
    let examples = ToolExample.parse(help: "Usage: eza [OPTIONS]", toolName: "eza")
    #expect(examples.isEmpty)
  }
}
