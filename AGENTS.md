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
