import Testing
@testable import CliToolsCore

struct LoginShellTests {
  @Test
  func readsPathAfterShellGreeting() {
    let output = """
      Welcome to fish, the friendly interactive shell
      __CLITOOLS_PATH__/Users/flavio/bin:/opt/homebrew/bin:/usr/bin

      """

    #expect(LoginShell.parse(output) == "/Users/flavio/bin:/opt/homebrew/bin:/usr/bin")
  }

  @Test
  func ignoresOutputWithoutPath() {
    #expect(LoginShell.parse("zsh: command not found: printenv") == nil)
    #expect(LoginShell.parse("__CLITOOLS_PATH__\n") == nil)
  }

  @Test
  func putsShellFoldersFirstWithoutDuplicates() {
    let merged = LoginShell.merge(
      "/Users/flavio/bin:/opt/homebrew/bin:/usr/bin",
      "/usr/bin:/bin:/usr/sbin:/sbin"
    )

    #expect(merged == "/Users/flavio/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin")
  }
}
