# TidalSwiftCLI

`tidal`, a command line tool for Tidal: search, artist releases, new releases of your favorite artists, playlists, favorites, and downloads. It also runs as an MCP server, so AI assistants can use your Tidal account. Built on [TidalSwiftLib](https://github.com/melgu/TidalSwiftLib), the library behind the [TidalSwift](https://github.com/melgu/TidalSwift) app.

Requires macOS 14.



## Installation

Build it from source with Swift 6.2:

```sh
git clone https://github.com/melgu/TidalSwiftCLI
cd TidalSwiftCLI
./build.sh install
```

This installs `tidal` to `/usr/local/bin` and its zsh completion to `/usr/local/share/zsh/site-functions`. `build.sh` signs the binary with an "Apple Development" certificate, so the Keychain remembers its access to the login.



## Usage

```sh
tidal login                       # approve this device in the browser
tidal search "Jacob Collier"
tidal artist https://tidal.com/browse/artist/123456 --type eps-and-singles
tidal new-releases --include-eps-and-singles
tidal playlists list
tidal favorites add https://tidal.com/browse/album/123456
tidal download https://tidal.com/browse/album/123456
```

Items are given as Tidal links or IDs. Most commands take `--json` for output that other tools can read. `tidal help <command>` shows all options.



## MCP Server

`tidal mcp` runs an MCP server on stdin and stdout with tools for search, releases, playlists, favorites and downloads. If the account isn't logged in yet, it asks the client to show the login link. To add it to Claude Code for all projects:

```sh
claude mcp add -s user tidal -- tidal mcp
```

Other clients take the command `tidal` with the argument `mcp`.
