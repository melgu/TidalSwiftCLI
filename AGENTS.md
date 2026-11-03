# Repository Guidelines

## About This Project

TidalSwiftCLI is the `tidal` command line tool for Tidal, built on [TidalSwiftLib](https://github.com/melgu/TidalSwiftLib). It searches, lists artist releases and new releases, edits playlists and favorites, downloads, and runs as an MCP server (`tidal mcp`).

## Project Structure & Module Organization

`Sources/tidal` holds the executable target. `Commands` holds the argument parsing and text output, `MCP` the MCP server (`tidal mcp`, on stdio, where stdout carries only protocol messages), and `Operations` the logic both share. Add new features to `Operations` first, then expose them in both the commands and the MCP tools.
The tool keeps its own login under the Keychain service `de.melgu.TidalSwift.cli`, apart from the app's.

Dependencies: TidalSwiftLib, `swift-argument-parser`, and the MCP `swift-sdk`.

## Architecture

API calls go through TidalSwiftLib's `Session`. Changes the tool needs in the library belong in the TidalSwiftLib repo, and need a new library version before the tool can depend on them.

Output: text by default, JSON with `--json`, both on stdout. Messages and progress go to stderr, so piping the output keeps working. In `tidal mcp`, stdout is reserved for protocol messages, so nothing else may print there.

## Build, Test, and Development Commands

- `./build.sh [debug|release|install]`
  Build the tool and sign it with the development certificate. Use this instead of plain `swift build`: an ad hoc signed build counts as a new app to the Keychain and asks for access after every build. `install` builds release and copies it to `/usr/local/bin` (or `TIDAL_INSTALL_DIR`), so the installed `tidal` and MCP clients using it aren't affected by development builds. It also installs zsh completion.
- `./release.sh <version>`
  Prepare a release: sets `toolVersion` in `Tidal.swift`, builds and checks `tidal --version`, commits "Bump version to …" and creates the tag. It refuses to run with uncommitted changes, off main, or while `Package.swift` depends on a local package. Don't change `toolVersion` by hand; versions follow semantic versioning (`1.2.0`).

To work on the library at the same time, clone TidalSwiftLib next to this repo and point `Package.swift` to it with `.package(path: "../TidalSwiftLib")`, without committing that change.

There is no automated test suite. Test commands against a real account, and restore any playlists or favorites a test changes.

## Coding Style & Naming Conventions

Indent with tabs, one per level, never spaces. Xcode and many tools default to four spaces, so check new code. `.editorconfig` encodes this for editors that support it.
Types use `UpperCamelCase`; functions/properties use `lowerCamelCase`; file names match the primary type/feature.
Prefer `async/await` over callback-style APIs.
Never mess with indentation or whitespace on unrelated lines, but make sure that new or edited blocks have correct indentation.
Blank lines inside a type or function carry the indentation of the surrounding block (e.g. a single tab between two methods), they are not left empty. Only blank lines at the top level of a file are empty. Editors and tools tend to strip this whitespace, so check the diff of new or edited code for bare blank lines (`git diff | grep -n '^+$'`).
The target is nonisolated by default, with the upcoming features `InferIsolatedConformances` and `NonisolatedNonsendingByDefault`. Code that uses `Session` runs on the `@MainActor`.

## Commit & Pull Request Guidelines

Match the existing commit style: short, imperative, and specific (`Add install step to command line build script`).
Keep commits scoped to one logical change.
PRs should include:
- concise summary of user-visible/technical changes
- linked issue (if available)
- manual test notes

## Security & Configuration Tips

Do not add personal tokens, account data, or local secrets to commits, and don't paste account data from command output into issues or commits.
