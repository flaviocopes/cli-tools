# CLI Tools

CLI Tools gives you one catalog for every command-line tool on your Mac.

The native app finds packages you explicitly installed with Homebrew, npm, and Cargo. It also scans trusted user command directories. Package commands stay grouped, so one package does not flood the catalog with helper executables.

The companion CLI reads the same catalog. AI agents can use its JSON output to discover the tools available on your system.

## Requirements

- macOS 14 or later
- Xcode 26 or a Swift 6.2 toolchain

## Run the app

Build the macOS app bundle:

```bash
./Scripts/build-app.sh
```

Then open it:

```bash
open "dist/CLI Tools.app"
```

You can also run the development build:

```bash
swift run CliToolsApp
```

## Use the CLI

Install the `clitools` command:

```bash
./Scripts/install-cli.sh
```

This builds the release binary and symlinks it into `~/.local/bin`. Pass a different directory to install somewhere else, for example `./Scripts/install-cli.sh /opt/homebrew/bin`. After that, replace `swift run clitools` with `clitools` in the commands below.

Scan your Mac:

```bash
swift run clitools scan
```

List the active tools as JSON:

```bash
swift run clitools list --json
```

Manage a tool:

```bash
swift run clitools favorite gh
swift run clitools archive vercel
swift run clitools restore vercel
```

Load local usage details:

```bash
swift run clitools inspect gh
```

Inspection runs the selected tool with `--version` and `--help`. It only happens when you request it. Homebrew tools also receive their official description and homepage.

Inspection also collects ready-made examples. It downloads the tool's [tldr page](https://github.com/tldr-pages/tldr) when one exists, and extracts the examples section from the tool's own help output. The app shows them with one-click copy, and the JSON output includes them under `examples`.

See how you used a tool:

```bash
swift run clitools history gh
```

This reads your shell history (zsh, bash, and fish) and groups the commands that ran the tool. The app shows the same list in the tool detail. Nothing from your history is written to the catalog.

## Catalog location

The app and CLI share this file:

```text
~/Library/Application Support/CliTools/catalog.json
```

Print its path from the CLI:

```bash
swift run clitools catalog-path
```

## Run the tests

```bash
swift test
```

## Contributing

Issues and pull requests are welcome. Run `swift test` before opening a PR.

Working with an AI coding agent? Point it at [AGENTS.md](AGENTS.md). It has the build commands, the project layout, and the rules to follow.

## License

[MIT](LICENSE)
