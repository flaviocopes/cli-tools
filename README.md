# CLI Tools

CLI Tools gives you one catalog for every command-line tool on your Mac.

The native app finds packages you explicitly installed with Homebrew, npm, and Cargo. It also scans trusted user command directories. Package commands stay grouped, so one package does not flood the catalog with helper executables.

The companion CLI reads the same catalog. AI agents can use its JSON output to discover the tools available on your system.

![CLI Tools showing the stripe tool with ready-made examples and its help output](docs/screenshot.png)

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

![The clitools help output listing every command](docs/cli.png)

Install the `clitools` command:

```bash
./Scripts/install-cli.sh
```

This builds the release binary and symlinks it into `~/.local/bin`. Pass a different directory to install somewhere else, for example `./Scripts/install-cli.sh /opt/homebrew/bin`. Without installing, run the same commands with `swift run clitools` instead of `clitools`.

Scan your Mac:

```bash
clitools scan
```

The scan tells you how many tools it found per source, and which ones appeared or disappeared since the last scan.

List what is installed:

```bash
clitools list
clitools list --favorites
clitools list --source homebrew
clitools list --sort usage
clitools list --unused
clitools list --json
```

Every list shows the star, name, source, version, and description. `--sort usage` orders by how often you ran each tool, from your shell history. `--unused` shows tools that never appear in it, handy when cleaning up.

Find a tool by name, command, package, or description:

```bash
clitools search markdown
```

Learn about a tool:

```bash
clitools show gh
clitools inspect gh
clitools examples gh
```

`show` prints what the catalog already knows. `inspect` runs the tool with `--version` and `--help`, and fetches its description, homepage, and examples. Homebrew tools get their official description. Examples come from the tool's [tldr page](https://github.com/tldr-pages/tldr) and from the examples section of its help output. Inspection only happens when you ask for it, never during a scan.

Tools can be found by any of their commands. `clitools show psql` finds the PostgreSQL package. Typos get a "did you mean" hint.

Manage tools, one or many at a time:

```bash
clitools favorite gh bat
clitools archive vercel
clitools restore vercel
```

See how you used a tool:

```bash
clitools history gh
clitools history gh --limit 10
```

This reads your shell history (zsh, bash, and fish) and groups the commands that ran the tool. Nothing from your history is written to the catalog.

Get a summary of the catalog:

```bash
clitools stats
```

Every command accepts `--help`, and most accept `--json`. Hints and footers only show up in a terminal, so piped output stays clean.

## Catalog location

The app and CLI share this file:

```text
~/Library/Application Support/CliTools/catalog.json
```

Print its path from the CLI:

```bash
clitools catalog-path
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
