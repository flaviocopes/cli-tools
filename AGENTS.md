# CLI Tools Cabinet

A Swift package with three targets. No Xcode project, no external dependencies.

- `Sources/CliToolsCore`: discovery, catalog persistence, inspection, shell history. All logic lives here.
- `Sources/CliToolsCLI`: the `clitools` command-line executable. `Commands.swift` declares every command and its options (the help text comes from there), `Arguments.swift` parses them, `Output.swift` renders tables and JSON, `CliToolsCommand.swift` dispatches. Adding a command means adding a `CommandSpec` plus a `case` in the dispatcher.
- `Sources/CliToolsApp`: the SwiftUI macOS app.
- `Tests/CliToolsCoreTests`: Swift Testing tests for the core.

## Build and test

Requirements: macOS 14+, Swift 6.2 (Xcode 26). Check with `swift --version`.

```bash
swift build              # build every target (debug)
swift test               # run the tests, must pass before committing
swift run clitools list  # run the CLI from source
swift run CliToolsApp    # run the app from source
./Scripts/build-app.sh   # universal release build, produces dist/CLI Tools Cabinet.app (Developer ID when the certificate is in the keychain, ad-hoc otherwise)
./Scripts/build-release.sh # builds, notarizes when Developer ID signed, staples, and writes dist/CLI-Tools-Cabinet-<version>.zip
open "dist/CLI Tools Cabinet.app"
./Scripts/install-cli.sh # release build of clitools, symlinked into ~/.local/bin (or the dir passed as $1)
```

Build output goes to `.build/`, the app bundle to `dist/`. Both are ignored by git.

## Working on the code

- Add logic to `CliToolsCore` and cover it with a test. Keep the CLI and the app thin.
- Any new field on `CLITool` must be optional so old `catalog.json` files still decode.
- The version lives in `Commands.version` in `Sources/CliToolsCLI/Commands.swift`. The CLI prints it, and `Scripts/build-app.sh` writes it into the app's `Info.plist`.
- Releases are signed with Flavio's Developer ID (team `DGFKNTAG99`) with the hardened runtime, and notarized by `Scripts/build-release.sh`. It needs the certificate in the keychain and a notarytool keychain profile named `notary`, and it skips notarization on an ad-hoc build. CI and forks have no certificate, so `Scripts/build-app.sh` signs ad-hoc there. Every release gets a section in `CHANGELOG.md` when that file exists, newest first.
- `Sources/CliToolsApp/AppUpdater.swift` checks the GitHub releases once a day and installs updates. It's an identical copy of the template in the `mac-app-updater` skill, so change the template and copy it over instead of editing it here. Every release needs its `vX.Y.Z` tag, the zip from `Scripts/build-release.sh` attached, and a `Commands.version` that matches the tag, or the app refuses the update.
- The app has no automated UI tests. Verify visual changes by running `./Scripts/build-app.sh` and opening the app.
- Inspection runs tools with `--version` and `--help` and does network requests (Homebrew metadata, tldr pages). It only runs for a selected tool, never during a scan.
- `capabilities` is the standard command every one of Flavio's CLIs implements (spec in the `agent-ready-cli` skill). `clitools` only runs `<tool> capabilities --json` on tools whose help lists that command (`ToolCapabilities.isAdvertised`), or that answered it before. Never probe other tools with it: `claude capabilities` would start an agent session, and `code capabilities` would open a file.
- `clitools capabilities` describes clitools itself from `Commands.manifest`. Add a changelog entry there for every release, newest first, next to the `Commands.version` bump.
- Never write shell history contents to the catalog.
- Resolve tool names through `Catalog.tool(matching:)` / `lookup(_:)`. It matches IDs, names, command names, and package names, and produces the "did you mean" and ambiguity errors.
- CLI hints and footers go through `Output.hint`, which prints only on a terminal. Keep piped and `--json` output free of them.

## Learned User Preferences
- Keep the catalog focused on CLI tools the user explicitly installed; exclude operating-system tools and transitive package helpers.
- Load cached usage automatically when a tool is selected, then refresh it in the background while its detail view stays open.
- Favor a modern, sleek macOS interface inspired by Things without copying its design.
- When a filtered section excludes the current selection, show the detail pane's empty state instead of stale tool details.
- Scan AI agent transcripts for a tool's runs only on demand (the "Find agent runs" button or `clitools history --agents`), never automatically when a tool opens.
- Add new screenshots to both the README and the flaviocopes.com post about CLI Tools Cabinet.

## Learned Workspace Facts
- This project provides both a native macOS SwiftUI desktop app and a `clitools` command-line interface for discovering and managing installed CLI tools.
- The catalog supports favorites, archives, installation-date filters, usage help, and automatic rescanning.
- Tool discovery inventories explicitly installed Homebrew packages, global npm packages including linked packages, Cargo tools, and trusted user command directories.
- Package commands stay grouped under their package so helper executables do not flood the catalog.
- Homebrew discovery reads local installation receipts because aggregate Homebrew metadata can omit tapped formulas.
- The persisted catalog lives at `~/Library/Application Support/CliTools/catalog.json`.
- The app icon source is `Assets/AppIcon.png`; `Scripts/build-app.sh` turns it into `AppIcon.icns` inside the bundle.
- README images live in `docs/`; the companion blog post is `~/www/flaviocopes.com/src/posts/cli-tools-cabinet.md`, with images in `public/images/cli-tools-cabinet/`.
- The demo video is hosted on flaviocopes.com (`public/images/cli-tools-cabinet/demo.mp4`, embedded in `src/posts/cli-tools-cabinet.md`), not in this repo; the README's `docs/showreel-poster.jpg` links to that post. The video comes from the separate Remotion project `~/dev/cli-tools-cabinet-showreel`, where `npm run build` renders `out/cli-tools-cabinet-showreel.mp4`.

`Scripts/screenshot.sh` builds a screenshot app with generated tools. Run it in the test VM with an output folder to capture both appearances without reading a real catalog.

## Naming compatibility

The public app name is CLI Tools Cabinet. Keep its existing bundle ID, saved data paths, URL schemes, CLI commands and internal Swift targets so installed copies and agent integrations remain compatible. Use the renamed checkout folder and GitHub repository in new links and build instructions.
