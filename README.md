# CLI Tools

CLI Tools gives you one catalog for every command-line tool on your Mac.

The native app scans your `PATH` and common package-manager directories. You can search, favorite, archive, and inspect each tool.

The companion CLI reads the same catalog. AI agents can use its JSON output to discover the tools available on your system.

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
