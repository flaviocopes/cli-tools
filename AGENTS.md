# CLI Tools

A Swift package with three targets. No Xcode project, no external dependencies.

- `Sources/CliToolsCore`: discovery, catalog persistence, inspection, shell history. All logic lives here.
- `Sources/CliToolsCLI`: the `clitools` command-line executable.
- `Sources/CliToolsApp`: the SwiftUI macOS app.
- `Tests/CliToolsCoreTests`: Swift Testing tests for the core.

## Build and test

Requirements: macOS 14+, Swift 6.2 (Xcode 26). Check with `swift --version`.

```bash
swift build              # build every target (debug)
swift test               # run the tests, must pass before committing
swift run clitools list  # run the CLI from source
swift run CliToolsApp    # run the app from source
./Scripts/build-app.sh   # release build, produces dist/CLI Tools.app (ad-hoc signed)
open "dist/CLI Tools.app"
./Scripts/install-cli.sh # release build of clitools, symlinked into ~/.local/bin (or the dir passed as $1)
```

Build output goes to `.build/`, the app bundle to `dist/`. Both are ignored by git.

## Working on the code

- Add logic to `CliToolsCore` and cover it with a test. Keep the CLI and the app thin.
- Any new field on `CLITool` must be optional so old `catalog.json` files still decode.
- The app has no automated UI tests. Verify visual changes by running `./Scripts/build-app.sh` and opening the app.
- Inspection runs tools with `--version` and `--help` and does network requests (Homebrew metadata, tldr pages). It only runs for a selected tool, never during a scan.
- Never write shell history contents to the catalog.

## Learned User Preferences
- Keep the catalog focused on CLI tools the user explicitly installed; exclude operating-system tools and transitive package helpers.
- Load cached usage automatically when a tool is selected, then refresh it in the background while its detail view stays open.
- Favor a modern, sleek macOS interface inspired by Things without copying its design.
- When a filtered section excludes the current selection, show the detail pane's empty state instead of stale tool details.

## Learned Workspace Facts
- This project provides both a native macOS SwiftUI desktop app and a `clitools` command-line interface for discovering and managing installed CLI tools.
- The catalog supports favorites, archives, installation-date filters, usage help, and automatic rescanning.
- Tool discovery inventories explicitly installed Homebrew packages, global npm packages including linked packages, Cargo tools, and trusted user command directories.
- Package commands stay grouped under their package so helper executables do not flood the catalog.
- Homebrew discovery reads local installation receipts because aggregate Homebrew metadata can omit tapped formulas.
- The persisted catalog lives at `~/Library/Application Support/CliTools/catalog.json`.
